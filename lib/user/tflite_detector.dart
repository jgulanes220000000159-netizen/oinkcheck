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
  static const double confidenceThreshold = 0.25;
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
      _interpreter = await Interpreter.fromAsset('assets/vv6.tflite');

      final inTensor = _interpreter!.getInputTensor(0);
      final outTensor = _interpreter!.getOutputTensor(0);
      final inShape = inTensor.shape; // e.g. [1, 640, 640, 3]
      final outShape = outTensor.shape; // e.g. [1, 13, 2100]

      // Set expected input size from the model tensor.
      if (inShape.length >= 3 && inShape[1] > 0) {
        _inputSize = inShape[1];
      }

      // Typical Ultralytics YOLO export: [1, 5 + classes, numBoxes]
      if (outShape.length >= 2 && outShape[1] >= 6) {
        _modelClassCount = outShape[1] - 5;
      } else {
        _modelClassCount = _labels.length;
      }

      // Auto-align labels to model class count (prevents indexing issues).
      if (_labels.length != _modelClassCount) {
        print(
          '⚠️  Labels/model class mismatch: labels=${_labels.length}, model=$_modelClassCount. Auto-aligning labels.',
        );
        if (_labels.length > _modelClassCount) {
          _labels = _labels.take(_modelClassCount).toList();
        } else {
          for (var i = _labels.length; i < _modelClassCount; i++) {
            _labels.add('class_$i');
          }
        }
      }

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

      final results = <DetectionResult>[];
      final outputData = output[0];

      print('🔍 Detection Debug Info:');
      print('   - Image size: ${image.width}x${image.height}');
      print('   - Input size: ${_inputSize}x${_inputSize}');
      print('   - Labels loaded: ${_labels.length} (${_labels.join(", ")})');
      print('   - Confidence threshold: $_currentConfidenceThreshold');
      print('   - NMS threshold: $_currentNmsThreshold');

      final detections = <DetectionResult>[];
      int totalDetections = 0;
      int validDetections = 0;
      double bestConf = 0.0;
      String bestLabel = 'none';
      double bestObj = 0.0;
      double bestCls = 0.0;
      int bestIdx = -1;

      // Inspect output ranges to decide whether to apply sigmoid.
      double objMin = double.infinity;
      double objMax = -double.infinity;
      double clsMin = double.infinity;
      double clsMax = -double.infinity;
      for (var i = 0; i < outputData[0].length; i++) {
        final o = outputData[4][i];
        if (o < objMin) objMin = o;
        if (o > objMax) objMax = o;
        for (var c = 5; c < outputData.length; c++) {
          final v = outputData[c][i];
          if (v < clsMin) clsMin = v;
          if (v > clsMax) clsMax = v;
        }
      }
      final applySigmoid = _shouldApplySigmoid(
        objMin: objMin,
        objMax: objMax,
        clsMin: clsMin,
        clsMax: clsMax,
      );
      // Some exports produce extremely tiny obj values (e.g., 1e-5) which effectively behaves like "no object".
      // Treat obj as usable only if it has meaningful magnitude.
      final bool useObjectness = objMax.abs() > 1e-3 || objMin.abs() > 1e-3;
      print(
        '   - Output ranges: obj[min=${objMin.toStringAsFixed(4)} max=${objMax.toStringAsFixed(4)}] '
        'cls[min=${clsMin.toStringAsFixed(4)} max=${clsMax.toStringAsFixed(4)}] '
        'applySigmoid=$applySigmoid useObjectness=$useObjectness',
      );

      // Track best class-only candidate (useful for "healthy" where objectness may be near-zero).
      double bestClsOnly = 0.0;
      String bestClsOnlyLabel = 'none';

      for (var i = 0; i < outputData[0].length; i++) {
        totalDetections++;
        var maxConf = 0.0;
        var maxClass = 0;

        // outputData layout: [x, y, w, h, obj, cls0, cls1, ...]
        for (var c = 5; c < outputData.length; c++) {
          final raw = outputData[c][i];
          final conf = applySigmoid ? _sigmoid(raw) : raw;
          if (conf > maxConf) {
            maxConf = conf;
            maxClass = c - 5;
          }
        }

        if (maxConf > bestClsOnly) {
          bestClsOnly = maxConf;
          bestClsOnlyLabel = _getDiseaseLabel(maxClass);
        }

        final double obj;
        if (!useObjectness) {
          // Some exports already fold objectness into class probabilities or omit it.
          obj = 1.0;
        } else {
          final rawObj = outputData[4][i];
          obj = applySigmoid ? _sigmoid(rawObj) : rawObj;
        }

        // If objectness is not present/usable, confidence == class score.
        final finalConf = useObjectness ? (obj * maxConf) : maxConf;
        if (finalConf > bestConf) {
          bestConf = finalConf;
          bestLabel = _getDiseaseLabel(maxClass);
          bestObj = obj;
          bestCls = maxConf;
          bestIdx = i;
        }

        if (finalConf > _currentConfidenceThreshold) {
          validDetections++;
          // YOLO outputs normalized coordinates (0-1) for center point and dimensions
          final centerX = outputData[0][i];
          final centerY = outputData[1][i];
          final width = outputData[2][i];
          final height = outputData[3][i];

          // Calculate letterboxing parameters - fixed logic
          final scale = min(
            _inputSize / image.width,
            _inputSize / image.height,
          );
          final newUnpaddedW = image.width * scale;
          final newUnpaddedH = image.height * scale;
          final padX = (_inputSize - newUnpaddedW) / 2;
          final padY = (_inputSize - newUnpaddedH) / 2;

          // Convert from YOLO normalized coordinates to original image coordinates
          // First convert center point and dimensions to absolute coordinates in YOLO space
          final yoloCenterX = centerX * _inputSize;
          final yoloCenterY = centerY * _inputSize;
          final yoloWidth = width * _inputSize;
          final yoloHeight = height * _inputSize;

          // Remove padding and scale back to original image space
          final originalCenterX = (yoloCenterX - padX) / scale;
          final originalCenterY = (yoloCenterY - padY) / scale;
          final originalWidth = yoloWidth / scale;
          final originalHeight = yoloHeight / scale;

          // Convert center point and dimensions to LTRB format
          final left = originalCenterX - (originalWidth / 2);
          final top = originalCenterY - (originalHeight / 2);
          final right = originalCenterX + (originalWidth / 2);
          final bottom = originalCenterY + (originalHeight / 2);

          detections.add(
            DetectionResult(
              label: _getDiseaseLabel(maxClass),
              confidence: finalConf,
              boundingBox: Rect.fromLTRB(left, top, right, bottom),
            ),
          );
        }
      }

      detections.sort((a, b) => b.confidence.compareTo(a.confidence));

      while (detections.isNotEmpty) {
        final detection = detections.removeAt(0);
        results.add(detection);
        detections.removeWhere((other) {
          final intersection = detection.boundingBox.intersect(
            other.boundingBox,
          );
          final intersectionArea = intersection.width * intersection.height;
          final otherArea = other.boundingBox.width * other.boundingBox.height;
          final iou = intersectionArea / otherArea;
          return iou > _currentNmsThreshold;
        });
      }

      print('📊 Detection Summary:');
      print('   - Total raw detections: $totalDetections');
      print('   - Valid detections (above threshold): $validDetections');
      print('   - Final detections after NMS: ${results.length}');
      print(
        '   - Best candidate (pre-threshold): $bestLabel ${(bestConf * 100).toStringAsFixed(6)}%',
      );
      print(
        '     ↳ bestObj=${bestObj.toStringAsFixed(6)} bestCls=${bestCls.toStringAsFixed(6)} idx=$bestIdx',
      );
      print(
        '   - Best class-only: $bestClsOnlyLabel ${(bestClsOnly * 100).toStringAsFixed(2)}%',
      );

      if (results.isNotEmpty) {
        print('🎯 Detected objects:');
        for (var result in results) {
          print(
            '   - ${result.label}: ${(result.confidence * 100).toStringAsFixed(1)}% at ${result.boundingBox}',
          );
        }
      } else {
        print('⚠️  No objects detected! Consider:');
        print(
          '   - Lowering confidence threshold (currently $_currentConfidenceThreshold)',
        );
        print('   - Checking if model is appropriate for your images');
        print('   - Verifying image quality and lighting');

        // Fallback: if objectness is effectively absent (or tiny), treat as image-level classification.
        // This makes "healthy" produce a meaningful confidence instead of ~0%.
        if (!useObjectness && bestClsOnlyLabel != 'none') {
          return [
            DetectionResult(
              label: bestClsOnlyLabel,
              confidence: bestClsOnly,
              boundingBox: Rect.fromLTRB(
                0,
                0,
                image.width.toDouble(),
                image.height.toDouble(),
              ),
            ),
          ];
        }
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
