import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'dart:math';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:io';
import 'dart:ui' show Rect;
import 'package:flutter/services.dart';

class DetectionResult {
  final String label;
  final double confidence;
  final Rect boundingBox;

  DetectionResult({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });
}

class TFLiteDetector {
  Interpreter? _interpreter;
  List<String> _labels = [];
  int _modelClassCount = 0;
  int _inputSize = 640;
  // YOLO exports often need a lower threshold on mobile images.
  static const double confidenceThreshold = 0.35;
  static const double nmsThreshold =
      0.3; // Increased from 0.1 to 0.3 to allow more detections

  // Configurable thresholds for testing
  double _currentConfidenceThreshold = confidenceThreshold;
  double _currentNmsThreshold = nmsThreshold;

  double _sigmoid(double x) => 1.0 / (1.0 + exp(-x));

  bool _shouldApplySigmoid({
    required double objMin,
    required double objMax,
    required double clsMin,
    required double clsMax,
  }) {
    // Clear logits signal
    if (objMin < 0.0 || objMax > 1.0) return true;
    if (clsMin < 0.0 || clsMax > 1.0) return true;

    // Heuristic: if everything is stuck very small but still within 0..1,
    // it's likely logits that were clipped/scaled; sigmoid will un-squash them.
    // This helps cases where confidence prints ~0.00% even on training images.
    if (objMax < 0.25 && clsMax < 0.25) return true;

    return false;
  }

  img.Image letterbox(img.Image src, int targetW, int targetH) {
    final srcW = src.width;
    final srcH = src.height;
    final scale =
        srcW / srcH > targetW / targetH ? targetW / srcW : targetH / srcH;
    final newW = (srcW * scale).round();
    final newH = (srcH * scale).round();
    final resized = img.copyResize(src, width: newW, height: newH);
    final out = img.Image(targetW, targetH);
    // Ultralytics letterbox padding uses 114 gray by default.
    img.fill(out, img.getColor(114, 114, 114));
    final dx = ((targetW - newW) / 2).round();
    final dy = ((targetH - newH) / 2).round();
    img.copyInto(out, resized, dstX: dx, dstY: dy);
    return out;
  }

  Future<void> loadModel() async {
    try {
      final labelData = await rootBundle.loadString('assets/labels.txt');
      _labels =
          labelData
              .split('\n')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty && e.toLowerCase() != 'place')
              .toList();
      _interpreter = await Interpreter.fromAsset('assets/yolomodel.tflite');

      final inTensor = _interpreter!.getInputTensor(0);
      final outTensor = _interpreter!.getOutputTensor(0);
      final inShape = inTensor.shape; // e.g. [1, 640, 640, 3]
      final outShape =
          outTensor
              .shape; // e.g. [1, 300, 6] for YOLOv8 (N boxes, 4+obj+classes)

      // Set expected input size from the model tensor.
      if (inShape.length >= 3 && inShape[1] > 0) {
        _inputSize = inShape[1];
      }

      // For this export format, the model already encodes the best class id in the last
      // coordinate, so we just rely on the labels file for names.
      _modelClassCount = _labels.length;

      print('✅ Model loaded');
      print('   - input tensor: $inShape');
      print('   - input type: ${inTensor.type}');
      print('   - output tensor: $outShape');
      print('   - output type: ${outTensor.type}');
      print('   - inputSize: $_inputSize');
      print('   - classes: $_modelClassCount');
      print('   - labels: ${_labels.join(", ")}');
    } catch (e) {
      print('❌ Failed to load model: $e');
      rethrow;
    }
  }

  Future<List<DetectionResult>> detectDiseases(String imagePath) async {
    if (_interpreter == null) {
      await loadModel();
    }

    try {
      final decoded = img.decodeImage(File(imagePath).readAsBytesSync());
      final image = decoded == null ? null : img.bakeOrientation(decoded);
      if (image == null) throw Exception('Image decoding failed');

      // Preprocess with letterbox (for model input only)
      final resized = letterbox(image, _inputSize, _inputSize);
      final input = Float32List(_inputSize * _inputSize * 3);
      final pixels = resized.getBytes();
      for (
        int i = 0, j = 0;
        i < pixels.length && j < input.length;
        i += 4, j += 3
      ) {
        input[j] = pixels[i] / 255.0;
        input[j + 1] = pixels[i + 1] / 255.0;
        input[j + 2] = pixels[i + 2] / 255.0;
      }

      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;

      final output = List.filled(
        outputShape.reduce((a, b) => a * b),
        0.0,
      ).reshape(outputShape);

      _interpreter!.run(input.reshape(inputShape), output);

      final rows = output[0] as List<dynamic>;
      final detections = <DetectionResult>[];

      print('🔍 Detection Debug Info:');
      print('   - Image size: ${image.width}x${image.height}');
      print('   - Input size: ${_inputSize}x${_inputSize}');
      print('   - Labels loaded: ${_labels.length} (${_labels.join(", ")})');
      print('   - Confidence threshold: $_currentConfidenceThreshold');
      print('   - NMS threshold: $_currentNmsThreshold');

      int totalDetections = 0;
      int keptDetections = 0;

      // YOLOv8 TFLite TFLite export (Ultralytics) uses [x1, y1, x2, y2, score, class_id]
      // with coordinates normalized 0..1 in model input space.
      for (final row in rows) {
        totalDetections++;

        double x1 = (row[0] as num).toDouble();
        double y1 = (row[1] as num).toDouble();
        double x2 = (row[2] as num).toDouble();
        double y2 = (row[3] as num).toDouble();
        final score = (row[4] as num).toDouble();
        final clsIdRaw = (row[5] as num).toDouble();
        final clsIdx = clsIdRaw.round().clamp(0, _labels.length - 1);

        if (score < _currentConfidenceThreshold) continue;

        // Step 1: convert normalized corner coords into model-input pixel space.
        final yoloX1 = x1 * _inputSize;
        final yoloY1 = y1 * _inputSize;
        final yoloX2 = x2 * _inputSize;
        final yoloY2 = y2 * _inputSize;

        // Step 2: undo letterbox padding to project back to original image space.
        final scale = min(_inputSize / image.width, _inputSize / image.height);
        final newUnpaddedW = image.width * scale;
        final newUnpaddedH = image.height * scale;
        final padX = (_inputSize - newUnpaddedW) / 2;
        final padY = (_inputSize - newUnpaddedH) / 2;

        final originalX1 = (yoloX1 - padX) / scale;
        final originalY1 = (yoloY1 - padY) / scale;
        final originalX2 = (yoloX2 - padX) / scale;
        final originalY2 = (yoloY2 - padY) / scale;

        final left = originalX1;
        final top = originalY1;
        final right = originalX2;
        final bottom = originalY2;

        final box = Rect.fromLTRB(
          left.clamp(0.0, image.width.toDouble()),
          top.clamp(0.0, image.height.toDouble()),
          right.clamp(0.0, image.width.toDouble()),
          bottom.clamp(0.0, image.height.toDouble()),
        );

        // Reject boxes that cover almost the whole image and are not very confident
        final boxArea = box.width * box.height;
        final imageArea = image.width * image.height;
        final coverageRatio = imageArea > 0 ? boxArea / imageArea : 0.0;
        if (coverageRatio > 0.95 && score < 0.7) {
          continue;
        }

        detections.add(
          DetectionResult(
            label: _getDiseaseLabel(clsIdx),
            confidence: score,
            boundingBox: box,
          ),
        );
        keptDetections++;
      }

      // Sort by confidence and apply simple NMS
      detections.sort((a, b) => b.confidence.compareTo(a.confidence));
      final results = <DetectionResult>[];
      final remaining = List<DetectionResult>.from(detections);

      while (remaining.isNotEmpty) {
        final current = remaining.removeAt(0);
        results.add(current);

        remaining.removeWhere((other) {
          final intersection = current.boundingBox.intersect(other.boundingBox);
          final interArea = intersection.width * intersection.height;
          if (interArea <= 0) return false;

          final areaA = current.boundingBox.width * current.boundingBox.height;
          final areaB = other.boundingBox.width * other.boundingBox.height;
          final unionArea = areaA + areaB - interArea;
          if (unionArea <= 0) return false;

          final iou = interArea / unionArea;
          return iou > _currentNmsThreshold;
        });
      }

      print('📊 Detection Summary:');
      print('   - Total raw detections: $totalDetections');
      print('   - Detections kept after score filter: $keptDetections');
      print('   - Final detections after NMS: ${results.length}');

      for (var r in results) {
        print(
          '   - ${r.label}: ${(r.confidence * 100).toStringAsFixed(1)}% at ${r.boundingBox}',
        );
      }

      return results;
    } catch (e) {
      print('❌ Error during detection: $e');
      return [];
    }
  }

  String _getDiseaseLabel(int classId) {
    if (classId >= 0 && classId < _labels.length) {
      return _labels[classId];
    }
    return 'class_$classId';
  }

  // Method to adjust thresholds for better detection
  void setThresholds({double? confidence, double? nms}) {
    if (confidence != null) {
      _currentConfidenceThreshold = confidence;
      print('🔧 Confidence threshold set to: $confidence');
    }
    if (nms != null) {
      _currentNmsThreshold = nms;
      print('🔧 NMS threshold set to: $nms');
    }
  }

  // Method to reset to default thresholds
  void resetThresholds() {
    _currentConfidenceThreshold = confidenceThreshold;
    _currentNmsThreshold = nmsThreshold;
    print(
      '🔄 Thresholds reset to defaults: confidence=$confidenceThreshold, nms=$nmsThreshold',
    );
  }

  // Method to test different threshold combinations
  Future<List<DetectionResult>> detectWithThresholds(
    String imagePath, {
    double? confidence,
    double? nms,
  }) async {
    final originalConfidence = _currentConfidenceThreshold;
    final originalNms = _currentNmsThreshold;

    setThresholds(confidence: confidence, nms: nms);
    final results = await detectDiseases(imagePath);

    // Restore original thresholds
    _currentConfidenceThreshold = originalConfidence;
    _currentNmsThreshold = originalNms;

    return results;
  }

  void closeModel() {
    _interpreter?.close();
    _interpreter = null;
    print('✅ TFLite interpreter closed');
  }
}
