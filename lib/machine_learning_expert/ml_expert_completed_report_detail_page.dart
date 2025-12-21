import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../shared/pig_disease_ui.dart';
import '../user/detection_painter.dart';
import '../user/tflite_detector.dart';

/// ML Expert view of a completed report:
/// - Shows only results (images + boxes + disease summary confidence)
/// - No recommendations/treatments UI
class MLExpertCompletedReportDetailPage extends StatefulWidget {
  const MLExpertCompletedReportDetailPage({super.key, required this.request});

  final Map<String, dynamic> request;

  @override
  State<MLExpertCompletedReportDetailPage> createState() =>
      _MLExpertCompletedReportDetailPageState();
}

class _MLExpertCompletedReportDetailPageState
    extends State<MLExpertCompletedReportDetailPage> {
  bool _showBoxes = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final box = await Hive.openBox('userBox');
      final pref = box.get('showBoundingBoxes');
      if (pref is bool && mounted) setState(() => _showBoxes = pref);
    });
  }

  Future<void> _saveBoxPref(bool v) async {
    final box = await Hive.openBox('userBox');
    await box.put('showBoundingBoxes', v);
  }

  List<Map<String, dynamic>> _getDiseaseConfidenceSummary() {
    // ML Expert should see the *raw model* summary only (no expert overrides).
    final summary = (widget.request['diseaseSummary'] as List?) ?? const [];

    final List<Map<String, dynamic>> fromSummary = [];
    for (final e in summary) {
      if (e is! Map) continue;
      final avg = (e['avgConfidence'] as num?)?.toDouble();
      final mx = (e['maxConfidence'] as num?)?.toDouble();
      if (avg == null) continue;
      final label =
          (e['label'] ?? e['disease'] ?? e['name'] ?? 'unknown').toString();
      fromSummary.add({
        'label': label,
        'avgConfidence': avg,
        'maxConfidence': mx ?? avg,
      });
    }
    fromSummary.sort((a, b) {
      final aAvg = (a['avgConfidence'] as num?)?.toDouble() ?? 0.0;
      final bAvg = (b['avgConfidence'] as num?)?.toDouble() ?? 0.0;
      return bAvg.compareTo(aAvg);
    });
    return fromSummary;
  }

  List<DetectionResult> _toDetectionResults(List raw) {
    final out = <DetectionResult>[];
    for (final d in raw) {
      if (d is! Map) continue;
      final label = (d['label'] ?? d['disease'] ?? 'unknown').toString();
      final conf = (d['confidence'] as num?)?.toDouble() ?? 0.0;

      // Support both shapes:
      // - bbox: {left, top, right, bottom}
      // - boundingBox: {left, top, right, bottom}
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

  @override
  Widget build(BuildContext context) {
    final status = (widget.request['status'] ?? '').toString();
    final farmer = (widget.request['userName'] ??
            widget.request['fullName'] ??
            'Farmer')
        .toString();
    final images = (widget.request['images'] as List?) ?? const [];
    final diseaseSummary = _getDiseaseConfidenceSummary();

    final expertName =
        (widget.request['expertName'] ?? widget.request['reviewedByName'] ?? '')
            .toString()
            .trim();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        title: const Text('Completed Report (Results)'),
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
                  Row(
                    children: [
                      const Icon(Icons.person, color: Colors.green, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          farmer,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status == 'completed' ? 'Completed' : 'Reviewed',
                          style: TextStyle(
                            color: Colors.green[800],
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (expertName.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.verified, color: Colors.green, size: 16),
                        const SizedBox(width: 6),
                        const Text(
                          'Reviewed by:',
                          style: TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            expertName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Images',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                Text('Boxes', style: TextStyle(color: Colors.grey[700])),
                Switch(
                  value: _showBoxes,
                  activeColor: Colors.green,
                  onChanged: (v) async {
                    setState(() => _showBoxes = v);
                    await _saveBoxPref(v);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (images.isEmpty)
              Text('No images.', style: TextStyle(color: Colors.grey[700]))
            else
              ...images.map((img) {
                final m = img is Map ? img : <String, dynamic>{};
                final imageUrl = (m['imageUrl'] ?? '').toString();
                final w = (m['imageWidth'] as num?)?.toDouble();
                final h = (m['imageHeight'] as num?)?.toDouble();
                final originalSize =
                    (w != null && h != null && w > 0 && h > 0)
                        ? Size(w, h)
                        : null;
                // ML Expert should see the *raw model* detections only (no expert overrides).
                final rawDetections = (m['results'] as List?) ?? const [];
                final detections = _toDetectionResults(rawDetections);

                // For ML expert: show only local file path images if present in storage.
                // If imageUrl is remote, still show it, but without box scaling guarantees
                // unless we know the original image size. We'll support file:// path too.

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
                    child: _ReportImageWithBoxes(
                      imageUrl: imageUrl,
                      results: detections,
                      showBoxes: _showBoxes,
                      originalImageSize: originalSize,
                    ),
                  ),
                );
              }),

            const SizedBox(height: 16),
            const Text(
              'Disease Summary (Results only)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (diseaseSummary.isEmpty)
              Text('No summary available.', style: TextStyle(color: Colors.grey[700]))
            else
              ...diseaseSummary.map((d) {
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
              }),
          ],
        ),
      ),
    );
  }
}

class _ReportImageWithBoxes extends StatelessWidget {
  const _ReportImageWithBoxes({
    required this.imageUrl,
    required this.results,
    required this.showBoxes,
    this.originalImageSize,
  });

  final String imageUrl;
  final List<DetectionResult> results;
  final bool showBoxes;
  final Size? originalImageSize;

  @override
  Widget build(BuildContext context) {
    final isNetwork = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    final isFileUrl = imageUrl.startsWith('file://');
    final localPath = isFileUrl ? imageUrl.replaceFirst('file://', '') : imageUrl;
    final localExists = !isNetwork && File(localPath).existsSync();

    final ImageProvider provider =
        isNetwork ? NetworkImage(imageUrl) : FileImage(File(localPath));

    // Prefer size stored in Firestore (imageWidth/imageHeight) so remote URLs can still render boxes.
    final hasSize = originalImageSize != null &&
        originalImageSize!.width > 0 &&
        originalImageSize!.height > 0;

    Future<Size> sizeFuture() async {
      if (hasSize) return originalImageSize!;
      final info = await _getImageInfo(provider);
      return Size(info.image.width.toDouble(), info.image.height.toDouble());
    }

    if (!isNetwork && !localExists) {
      return Container(
        height: 220,
        color: Colors.grey[200],
        alignment: Alignment.center,
        child: Text(
          'Image not available.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[700]),
        ),
      );
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
                      errorBuilder: (context, _, __) => Container(
                        color: Colors.grey[200],
                        alignment: Alignment.center,
                        child: Text(
                          'Failed to load image.',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ),
                    ),
                  ),
                  if (showBoxes && results.isNotEmpty)
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


