import 'dart:io';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';

import '../shared/pig_disease_ui.dart';
import '../user/detection_painter.dart';
import '../user/tflite_detector.dart';

class MLExpertScanResultPage extends StatefulWidget {
  const MLExpertScanResultPage({
    super.key,
    required this.allResults,
    required this.imagePaths,
  });

  final Map<int, List<DetectionResult>> allResults;
  final List<String> imagePaths;

  @override
  State<MLExpertScanResultPage> createState() => _MLExpertScanResultPageState();
}

class _MLExpertScanResultPageState extends State<MLExpertScanResultPage> {
  bool _showBoxes = true;
  int _rating = 0;
  final _commentCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final box = await Hive.openBox('userBox');
      final pref = box.get('showBoundingBoxes');
      if (pref is bool && mounted) setState(() => _showBoxes = pref);
    });
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveBoxPref(bool v) async {
    final box = await Hive.openBox('userBox');
    await box.put('showBoundingBoxes', v);
  }

  List<Map<String, dynamic>> _summary() {
    final Map<String, double> sum = {};
    final Map<String, int> n = {};
    final Map<String, double> max = {};
    for (final entry in widget.allResults.entries) {
      for (final r in entry.value) {
        final key = PigDiseaseUI.normalizeKey(r.label);
        if (key.isEmpty) continue;
        sum[key] = (sum[key] ?? 0) + r.confidence;
        n[key] = (n[key] ?? 0) + 1;
        final prev = max[key] ?? 0.0;
        if (r.confidence > prev) max[key] = r.confidence;
      }
    }
    final out = <Map<String, dynamic>>[];
    for (final e in n.entries) {
      final k = e.key;
      final cnt = e.value;
      final avg = cnt == 0 ? 0.0 : (sum[k] ?? 0.0) / cnt;
      out.add({
        'label': k,
        'avgConfidence': avg,
        'maxConfidence': max[k] ?? avg,
        'count': cnt,
      });
    }
    out.sort((a, b) {
      final aAvg = (a['avgConfidence'] as num?)?.toDouble() ?? 0.0;
      final bAvg = (b['avgConfidence'] as num?)?.toDouble() ?? 0.0;
      return bAvg.compareTo(aAvg);
    });
    return out;
  }

  Future<File> _compressIfOver30Mb(File original) async {
    const maxBytes = 30 * 1024 * 1024;
    final len = await original.length();
    if (len <= maxBytes) return original;

    Future<File> compressWithQuality(int quality) async {
      final bytes = await original.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return original;
      final jpg = img.encodeJpg(decoded, quality: quality);
      final tmp = File('${original.path}.q$quality.jpg');
      return tmp.writeAsBytes(jpg, flush: true);
    }

    for (final q in [85, 75, 65]) {
      final candidate = await compressWithQuality(q);
      if (await candidate.length() <= maxBytes) return candidate;
    }
    return await compressWithQuality(55);
  }

  Future<void> _submitEvaluation() async {
    if (_rating <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a rating (1–5 stars).'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final profile = Hive.box('userBox').get('userProfile');
      final name = (profile is Map ? profile['fullName'] : null)?.toString() ?? 'ML Expert';

      // Upload images to Firebase Storage so history/admin can access later.
      final List<Map<String, String>> uploaded = [];
      for (int i = 0; i < widget.imagePaths.length; i++) {
        final originalFile = File(widget.imagePaths[i]);
        final file = await _compressIfOver30Mb(originalFile);
        final fileName = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        // Use the same top-level folder as farmer uploads to match existing Storage rules.
        // (Most projects only allow writes under `diseases/**`.)
        final storagePath = 'diseases/ml_evaluations/$fileName';
        final ref = FirebaseStorage.instance.ref().child(storagePath);
        final mime = lookupMimeType(file.path) ?? 'image/jpeg';
        try {
          await ref.putFile(file, SettableMetadata(contentType: mime));
        } on FirebaseException catch (e) {
          throw Exception('Storage upload failed (${e.code}): ${e.message ?? e.toString()}');
        }
        final String url;
        try {
          url = await ref.getDownloadURL();
        } on FirebaseException catch (e) {
          throw Exception('Storage getDownloadURL failed (${e.code}): ${e.message ?? e.toString()}');
        }
        uploaded.add({'url': url, 'path': storagePath});
      }

      final images = <Map<String, dynamic>>[];
      for (int i = 0; i < widget.imagePaths.length; i++) {
        final results = widget.allResults[i] ?? const <DetectionResult>[];
        final imageFile = File(widget.imagePaths[i]);
        final bytes = await imageFile.readAsBytes();
        final decoded = img.decodeImage(bytes);
        final w = decoded?.width.toDouble() ?? 0.0;
        final h = decoded?.height.toDouble() ?? 0.0;
        images.add({
          'localPath': widget.imagePaths[i],
          'imageUrl': uploaded[i]['url'],
          'storagePath': uploaded[i]['path'],
          'imageWidth': w,
          'imageHeight': h,
          'results': results
              .map(
                (r) => {
                  'label': PigDiseaseUI.normalizeKey(r.label),
                  'confidence': r.confidence,
                  'bbox': {
                    'left': r.boundingBox.left,
                    'top': r.boundingBox.top,
                    'right': r.boundingBox.right,
                    'bottom': r.boundingBox.bottom,
                  },
                },
              )
              .toList(),
        });
      }

      try {
        await FirebaseFirestore.instance.collection('ml_expert_evaluations').add({
          'type': 'ml_scan',
          'createdAt': FieldValue.serverTimestamp(),
          'evaluatorUid': user.uid,
          'evaluatorName': name,
          'rating': _rating,
          'comment': _commentCtrl.text.trim(),
          'imageCount': widget.imagePaths.length,
          'summary': _summary(),
          'images': images,
        });
      } on FirebaseException catch (e) {
        throw Exception('Firestore write failed (${e.code}): ${e.message ?? e.toString()}');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved evaluation.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save evaluation: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        title: const Text('Scan Result'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Bounding Boxes',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
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
            ...List.generate(widget.imagePaths.length, (i) {
              final path = widget.imagePaths[i];
              final results = widget.allResults[i] ?? const <DetectionResult>[];
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
                  child: FutureBuilder<ImageInfo>(
                    future: _getImageInfo(path),
                    builder: (context, snap) {
                      final info = snap.data;
                      final original =
                          info != null
                              ? Size(
                                info.image.width.toDouble(),
                                info.image.height.toDouble(),
                              )
                              : const Size(1, 1);

                      // Keep the image aspect ratio to avoid cropping (critical for box positioning).
                      return AspectRatio(
                        aspectRatio:
                            original.height == 0
                                ? 1
                                : (original.width / original.height),
                        child: LayoutBuilder(
                          builder: (context, c) {
                            // BoxFit.contain math (image is centered, not cropped).
                            final scale = (original.width == 0 || original.height == 0)
                                ? 1.0
                                : (c.maxWidth / original.width)
                                    .clamp(0.0, double.infinity)
                                    .toDouble();
                            final scaleH = (original.width == 0 || original.height == 0)
                                ? 1.0
                                : (c.maxHeight / original.height)
                                    .clamp(0.0, double.infinity)
                                    .toDouble();
                            final s = scale < scaleH ? scale : scaleH;
                            final displayed = Size(original.width * s, original.height * s);
                            final offset = Offset(
                              (c.maxWidth - displayed.width) / 2,
                              (c.maxHeight - displayed.height) / 2,
                            );

                            return Stack(
                              children: [
                                Positioned.fill(
                                  // IMPORTANT: don't wrap in Center; Center gives loose constraints and
                                  // tiny input images won't scale up, causing box/image mismatch.
                                  child: Image.file(
                                    File(path),
                                    fit: BoxFit.contain,
                                    width: double.infinity,
                                    height: double.infinity,
                                  ),
                                ),
                                if (_showBoxes && results.isNotEmpty)
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
                  ),
                ),
              );
            }),

            const SizedBox(height: 12),
            const Text(
              'Detected Summary',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (summary.isEmpty)
              Text('No detections.', style: TextStyle(color: Colors.grey[700]))
            else
              ...summary.map((d) {
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
                          style: const TextStyle(fontWeight: FontWeight.w700),
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

            const SizedBox(height: 18),
            const Text(
              'Rate this scan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Row(
              children: List.generate(5, (idx) {
                final v = idx + 1;
                final filled = v <= _rating;
                return IconButton(
                  onPressed: () => setState(() => _rating = v),
                  icon: Icon(
                    filled ? Icons.star : Icons.star_border,
                    color: filled ? Colors.amber[700] : Colors.grey[500],
                  ),
                );
              }),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _commentCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Comment (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: _saving ? null : _submitEvaluation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Save Evaluation'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<ImageInfo> _getImageInfo(String path) async {
    final provider = FileImage(File(path));
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


