import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../shared/pig_disease_ui.dart';
import '../user/detection_painter.dart';
import '../user/tflite_detector.dart';

class MLExpertMyEvaluationDetailPage extends StatelessWidget {
  const MLExpertMyEvaluationDetailPage({super.key, required this.evaluation});

  final Map<String, dynamic> evaluation;

  @override
  Widget build(BuildContext context) {
    final rating = (evaluation['rating'] as num?)?.toInt() ?? 0;
    final comment = (evaluation['comment'] ?? '').toString().trim();
    final summary = (evaluation['summary'] as List?) ?? const [];
    final images = (evaluation['images'] as List?) ?? const [];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        title: const Text('My Scan Evaluation'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rating',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: List.generate(5, (i) {
                      final filled = (i + 1) <= rating;
                      return Icon(
                        filled ? Icons.star : Icons.star_border,
                        color: filled ? Colors.amber[700] : Colors.grey[400],
                      );
                    }),
                  ),
                  if (comment.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Comment',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(comment, style: TextStyle(color: Colors.grey[800], height: 1.25)),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Text(
              'Detected Summary',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ..._buildSummary(summary),

            const SizedBox(height: 16),
            const Text(
              'Images',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (images.isEmpty)
              Text('No images saved.', style: TextStyle(color: Colors.grey[700]))
            else
              ...images.map((img) {
                final m = img is Map ? img : <String, dynamic>{};
                final imageUrl = (m['imageUrl'] ?? '').toString();
                final localPath = (m['localPath'] ?? '').toString();
                final w = (m['imageWidth'] as num?)?.toDouble();
                final h = (m['imageHeight'] as num?)?.toDouble();
                final originalSize =
                    (w != null && h != null && w > 0 && h > 0) ? Size(w, h) : null;
                final rawResults = (m['results'] as List?) ?? const [];
                final results = _toDetectionResults(rawResults);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _EvaluationImageWithBoxes(
                      imageUrl: imageUrl,
                      localPath: localPath,
                      results: results,
                      originalImageSize: originalSize,
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSummary(List raw) {
    final List<Map<String, dynamic>> items = [];
    for (final e in raw) {
      if (e is Map) items.add(Map<String, dynamic>.from(e));
    }
    if (items.isEmpty) {
      return [Text('No detections.', style: TextStyle(color: Colors.grey[700]))];
    }
    items.sort((a, b) {
      final aAvg = (a['avgConfidence'] as num?)?.toDouble() ?? 0.0;
      final bAvg = (b['avgConfidence'] as num?)?.toDouble() ?? 0.0;
      return bAvg.compareTo(aAvg);
    });
    return items.map((d) {
      final label = (d['label'] ?? 'unknown').toString();
      final avg = (d['avgConfidence'] as num?)?.toDouble() ?? 0.0;
      final mx = (d['maxConfidence'] as num?)?.toDouble() ?? avg;
      final color = PigDiseaseUI.colorFor(label);
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                PigDiseaseUI.displayName(label),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              'Avg ${(avg * 100).toStringAsFixed(1)}% • Max ${(mx * 100).toStringAsFixed(1)}%',
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
          ],
        ),
      );
    }).toList();
  }

  List<DetectionResult> _toDetectionResults(List raw) {
    final out = <DetectionResult>[];
    for (final d in raw) {
      if (d is! Map) continue;
      final label = (d['label'] ?? d['disease'] ?? 'unknown').toString();
      final conf = (d['confidence'] as num?)?.toDouble() ?? 0.0;
      final bb = (d['bbox'] as Map?) ?? (d['boundingBox'] as Map?);
      if (bb is! Map) continue;
      final left = (bb['left'] as num?)?.toDouble();
      final top = (bb['top'] as num?)?.toDouble();
      final right = (bb['right'] as num?)?.toDouble();
      final bottom = (bb['bottom'] as num?)?.toDouble();
      if (left == null || top == null || right == null || bottom == null) continue;
      out.add(
        DetectionResult(
          label: label,
          confidence: conf,
          boundingBox: Rect.fromLTRB(left, top, right, bottom),
        ),
      );
    }
    return out;
  }
}

class _EvaluationImageWithBoxes extends StatelessWidget {
  const _EvaluationImageWithBoxes({
    required this.imageUrl,
    required this.localPath,
    required this.results,
    this.originalImageSize,
  });

  final String imageUrl;
  final String localPath;
  final List<DetectionResult> results;
  final Size? originalImageSize;

  @override
  Widget build(BuildContext context) {
    final isNetwork = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    final hasLocal = localPath.trim().isNotEmpty && File(localPath).existsSync();
    final ImageProvider<Object>? provider = isNetwork
        ? NetworkImage(imageUrl)
        : (hasLocal ? FileImage(File(localPath)) : null);

    if (provider == null) {
      return _placeholder(
        'Image not available.\n(Still saved in Firebase if uploaded.)',
      );
    }

    final hasSize = originalImageSize != null &&
        originalImageSize!.width > 0 &&
        originalImageSize!.height > 0;

    Future<Size> sizeFuture() async {
      if (hasSize) return originalImageSize!;
      final info = await _getImageInfo(provider);
      return Size(info.image.width.toDouble(), info.image.height.toDouble());
    }

    return FutureBuilder<Size>(
      future: sizeFuture(),
      builder: (context, snap) {
        final original = snap.data ?? const Size(1, 1);
        return AspectRatio(
          aspectRatio: original.height == 0 ? 1 : (original.width / original.height),
          child: LayoutBuilder(
            builder: (context, c) {
              final s = [
                c.maxWidth / (original.width == 0 ? 1 : original.width),
                c.maxHeight / (original.height == 0 ? 1 : original.height),
              ].reduce((a, b) => a < b ? a : b);
              final displayed = Size(original.width * s, original.height * s);
              final offset = Offset(
                (c.maxWidth - displayed.width) / 2,
                (c.maxHeight - displayed.height) / 2,
              );

              return Stack(
                children: [
                  Positioned.fill(
                    child: Image(
                      image: provider,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (context, _, __) =>
                          _placeholder('Failed to load image.'),
                    ),
                  ),
                  if (results.isNotEmpty)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: DetectionPainter(
                          results: results,
                          originalImageSize: original,
                          displayedImageSize: displayed,
                          displayedImageOffset: offset,
                          debugMode: true,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _placeholder(String text) {
    return Container(
      height: 220,
      color: Colors.grey[200],
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700])),
    );
  }

  Future<ImageInfo> _getImageInfo(ImageProvider provider) async {
    final completer = Completer<ImageInfo>();
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      completer.complete(info);
      stream.removeListener(listener);
    });
    stream.addListener(listener);
    return completer.future;
  }
}


