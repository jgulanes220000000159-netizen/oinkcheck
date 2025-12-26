import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'tflite_detector.dart';
import 'detection_painter.dart';
import '../shared/pig_disease_ui.dart';
import '../shared/treatments_repository.dart';

class UserRequestDetail extends StatefulWidget {
  final Map<String, dynamic> request;
  const UserRequestDetail({Key? key, required this.request}) : super(key: key);

  @override
  _UserRequestDetailState createState() => _UserRequestDetailState();
}

class _UserRequestDetailState extends State<UserRequestDetail> {
  bool _showBoundingBoxes = true;
  static const double _recommendationAvgThreshold = 0.70;

  @override
  void initState() {
    super.initState();
    _loadBoundingBoxPreference();
  }

  /// Returns per-disease avg/max confidence.
  /// Prefers request.expertDiseaseSummary when present; else request.diseaseSummary;
  /// falls back to image detections.
  List<Map<String, dynamic>> _getDiseaseConfidenceSummary() {
    final summary =
        (widget.request['expertDiseaseSummary'] as List?) ??
        (widget.request['diseaseSummary'] as List?) ??
        const [];

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
    if (fromSummary.isNotEmpty) return fromSummary;

    // Fallback: compute from detections stored under images[].results[]
    final images = (widget.request['images'] as List?) ?? const [];
    final Map<String, double> sum = {};
    final Map<String, int> n = {};
    final Map<String, double> max = {};
    for (final img in images) {
      if (img is! Map) continue;
      final results = (img['results'] as List?) ?? const [];
      for (final d in results) {
        if (d is! Map) continue;
        final raw = (d['disease'] ?? d['label'] ?? 'unknown').toString();
        final conf = (d['confidence'] as num?)?.toDouble();
        if (conf == null) continue;
        final key = PigDiseaseUI.normalizeKey(raw);
        sum[key] = (sum[key] ?? 0) + conf;
        n[key] = (n[key] ?? 0) + 1;
        final prev = max[key] ?? 0.0;
        if (conf > prev) max[key] = conf;
      }
    }
    final out = <Map<String, dynamic>>[];
    for (final entry in n.entries) {
      final key = entry.key;
      final cnt = entry.value;
      if (cnt <= 0) continue;
      final avg = (sum[key] ?? 0.0) / cnt;
      out.add({
        'label': key,
        'avgConfidence': avg,
        'maxConfidence': max[key] ?? avg,
      });
    }
    return out;
  }

  void _showDiseaseRecommendations(BuildContext context, String label) {
    final repo = TreatmentsRepository();
    final diseaseId = PigDiseaseUI.treatmentIdForLabel(label);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(PigDiseaseUI.displayName(label)),
          content: FutureBuilder(
            future: repo.getPublicDoc(diseaseId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Text('Failed to load recommendation: ${snapshot.error}');
              }
              final doc = snapshot.data;
              if (doc == null || !doc.exists) {
                return const Text('No approved treatments yet.');
              }
              final data = doc.data() ?? <String, dynamic>{};
              final treatments = (data['treatments'] as List? ?? [])
                  .map((e) => e.toString())
                  .where((e) => e.trim().isNotEmpty)
                  .toList();
              if (treatments.isEmpty) {
                return const Text('No approved treatments yet.');
              }
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recommended Treatments',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    ...treatments.map(
                      (t) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('• $t'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _openImageViewer(int initialIndex) {
    final images = (widget.request['images'] as List?) ?? [];
    if (images.isEmpty) return;
    int currentIndex = initialIndex;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final img = images[currentIndex] as Map<String, dynamic>;
            final imageUrl = (img['imageUrl'] ?? '').toString();
            final imagePath =
                (img['path'] ?? img['imagePath'] ?? '').toString();
            final displayPath = imageUrl.isNotEmpty ? imageUrl : imagePath;
            final detections =
                (img['results'] as List?)
                    ?.where(
                      (d) =>
                          d != null &&
                          d['disease'] != null &&
                          d['confidence'] != null,
                    )
                    .toList() ??
                [];

            return Dialog(
              backgroundColor: Colors.black,
              insetPadding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final widgetW = constraints.maxWidth;
                  final widgetH = constraints.maxHeight;

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildImageWidget(displayPath, fit: BoxFit.contain),
                      if (_showBoundingBoxes && detections.isNotEmpty)
                        Builder(
                          builder: (context) {
                            final storedImageWidth = img['imageWidth'] as num?;
                            final storedImageHeight =
                                img['imageHeight'] as num?;

                            if (storedImageWidth != null &&
                                storedImageHeight != null) {
                              final imgSize = Size(
                                storedImageWidth.toDouble(),
                                storedImageHeight.toDouble(),
                              );
                              final imgW = imgSize.width;
                              final imgH = imgSize.height;
                              final widgetAspect = widgetW / widgetH;
                              final imageAspect = imgW / imgH;
                              double displayW, displayH, dx = 0, dy = 0;
                              if (widgetAspect > imageAspect) {
                                displayH = widgetH;
                                displayW = widgetH * imageAspect;
                                dx = (widgetW - displayW) / 2;
                              } else {
                                displayW = widgetW;
                                displayH = widgetW / imageAspect;
                                dy = (widgetH - displayH) / 2;
                              }

                              return CustomPaint(
                                painter: DetectionPainter(
                                  results:
                                      detections
                                          .where(
                                            (d) => d['boundingBox'] != null,
                                          )
                                          .map((d) {
                                            final left =
                                                (d['boundingBox']['left']
                                                        as num)
                                                    .toDouble();
                                            final top =
                                                (d['boundingBox']['top'] as num)
                                                    .toDouble();
                                            final right =
                                                (d['boundingBox']['right']
                                                        as num)
                                                    .toDouble();
                                            final bottom =
                                                (d['boundingBox']['bottom']
                                                        as num)
                                                    .toDouble();
                                            return DetectionResult(
                                              label: d['disease'],
                                              confidence: d['confidence'],
                                              boundingBox: Rect.fromLTRB(
                                                left,
                                                top,
                                                right,
                                                bottom,
                                              ),
                                            );
                                          })
                                          .toList(),
                                  originalImageSize: imgSize,
                                  displayedImageSize: Size(displayW, displayH),
                                  displayedImageOffset: Offset(dx, dy),
                                ),
                                size: Size(widgetW, widgetH),
                              );
                            } else {
                              return FutureBuilder<Size>(
                                future: _getImageSize(
                                  displayPath.startsWith('http') &&
                                          displayPath.isNotEmpty
                                      ? NetworkImage(displayPath)
                                      : FileImage(File(displayPath)),
                                ),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData) {
                                    return const SizedBox.shrink();
                                  }
                                  final imgSize = snapshot.data!;
                                  final imgW = imgSize.width;
                                  final imgH = imgSize.height;
                                  final widgetAspect = widgetW / widgetH;
                                  final imageAspect = imgW / imgH;
                                  double displayW, displayH, dx = 0, dy = 0;
                                  if (widgetAspect > imageAspect) {
                                    displayH = widgetH;
                                    displayW = widgetH * imageAspect;
                                    dx = (widgetW - displayW) / 2;
                                  } else {
                                    displayW = widgetW;
                                    displayH = widgetW / imageAspect;
                                    dy = (widgetH - displayH) / 2;
                                  }

                                  return CustomPaint(
                                    painter: DetectionPainter(
                                      results:
                                          detections
                                              .where(
                                                (d) => d['boundingBox'] != null,
                                              )
                                              .map((d) {
                                                final left =
                                                    (d['boundingBox']['left']
                                                            as num)
                                                        .toDouble();
                                                final top =
                                                    (d['boundingBox']['top']
                                                            as num)
                                                        .toDouble();
                                                final right =
                                                    (d['boundingBox']['right']
                                                            as num)
                                                        .toDouble();
                                                final bottom =
                                                    (d['boundingBox']['bottom']
                                                            as num)
                                                        .toDouble();
                                                return DetectionResult(
                                                  label: d['disease'],
                                                  confidence: d['confidence'],
                                                  boundingBox: Rect.fromLTRB(
                                                    left,
                                                    top,
                                                    right,
                                                    bottom,
                                                  ),
                                                );
                                              })
                                              .toList(),
                                      originalImageSize: imgSize,
                                      displayedImageSize: Size(
                                        displayW,
                                        displayH,
                                      ),
                                      displayedImageOffset: Offset(dx, dy),
                                    ),
                                    size: Size(widgetW, widgetH),
                                  );
                                },
                              );
                            }
                          },
                        ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: IconButton(
                            iconSize: 36,
                            color: Colors.white,
                            icon: const Icon(Icons.chevron_left),
                            onPressed:
                                currentIndex > 0
                                    ? () {
                                      setStateDialog(() {
                                        currentIndex -= 1;
                                      });
                                    }
                                    : null,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: IconButton(
                            iconSize: 36,
                            color: Colors.white,
                            icon: const Icon(Icons.chevron_right),
                            onPressed:
                                currentIndex < images.length - 1
                                    ? () {
                                      setStateDialog(() {
                                        currentIndex += 1;
                                      });
                                    }
                                    : null,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${currentIndex + 1} / ${images.length}',
                              style: const TextStyle(color: Colors.white),
                            ),
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
      },
    );
  }

  Future<void> _loadBoundingBoxPreference() async {
    final box = await Hive.openBox('userBox');
    final savedPreference = box.get('showBoundingBoxes');
    if (savedPreference != null) {
      setState(() {
        _showBoundingBoxes = savedPreference as bool;
      });
    }
  }

  Future<void> _saveBoundingBoxPreference(bool value) async {
    final box = await Hive.openBox('userBox');
    await box.put('showBoundingBoxes', value);
  }

  Widget build(BuildContext context) {
    // Removed unused mainDisease variable
    final status = widget.request['status'] ?? '';
    final submittedAt = widget.request['submittedAt'] ?? '';
    // Format date
    final formattedDate =
        submittedAt.isNotEmpty && DateTime.tryParse(submittedAt) != null
            ? DateFormat(
              'MMM d, yyyy – h:mma',
            ).format(DateTime.parse(submittedAt))
            : submittedAt;
    final reviewedAt = widget.request['reviewedAt'] ?? '';
    // Format reviewed date
    final formattedReviewedDate =
        reviewedAt.isNotEmpty && DateTime.tryParse(reviewedAt) != null
            ? DateFormat(
              'MMM d, yyyy – h:mma',
            ).format(DateTime.parse(reviewedAt))
            : reviewedAt;
    final expertReview = widget.request['expertReview'];
    final expertName = widget.request['expertName'] ?? '';
    final isCompleted = status == 'completed';
    final images = (widget.request['images'] as List?) ?? [];

    // Debug: Print the entire request structure
    print('🔍 Request Debug:');
    print('🔍 Status: $status');
    print('🔍 Images count: ${images.length}');
    for (var i = 0; i < images.length; i++) {
      final img = images[i];
      print('🔍 Image $i:');
      print('🔍   - imageUrl: ${img['imageUrl']}');
      print('🔍   - imagePath: ${img['imagePath']}');
      print('🔍   - path: ${img['path']}');
      print('🔍   - imageWidth: ${img['imageWidth']}');
      print('🔍   - imageHeight: ${img['imageHeight']}');
      print('🔍   - results: ${img['results']}');
      if (img['results'] != null) {
        final results = img['results'] as List;
        print('🔍   - results count: ${results.length}');
        for (var j = 0; j < results.length; j++) {
          final result = results[j];
          print(
            '🔍   - Result $j: ${result['disease']} (${result['confidence']})',
          );
          print('🔍   - Bounding box: ${result['boundingBox']}');
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: Text(
          tr('request_details'),
          style: const TextStyle(color: Colors.white),
        ),
        elevation: 0,
        actions: [],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User and timestamp info
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Card(
                color: Colors.grey[50],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.person,
                            size: 18,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              tr('your_request'),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.green,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  isCompleted
                                      ? Colors.green.withOpacity(0.1)
                                      : Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                    isCompleted
                                        ? Colors.green.withOpacity(0.3)
                                        : Colors.orange.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              isCompleted
                                  ? tr('completed')
                                  : (status == 'tracking'
                                      ? tr('tracking')
                                      : (status == 'pending_review'
                                          ? tr('pending')
                                          : tr('pending'))),
                              style: TextStyle(
                                color:
                                    isCompleted ? Colors.green : Colors.orange,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            tr('submitted'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            formattedDate,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      if (isCompleted && reviewedAt.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              size: 16,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              tr('reviewed'),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formattedReviewedDate,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (isCompleted && expertReview != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.person,
                              size: 16,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'Reviewed by',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                (expertName.toString().trim().isNotEmpty)
                                    ? expertName.toString().trim()
                                    : 'Expert',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.green,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Images Grid
            if (images.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('submitted_images'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Toggle button for bounding boxes
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(tr('show_bounding_boxes')),
                        Switch(
                          value: _showBoundingBoxes,
                          onChanged: (value) async {
                            setState(() {
                              _showBoundingBoxes = value;
                            });
                            await _saveBoundingBoxPreference(value);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: images.length,
                      itemBuilder: (context, idx) {
                        final img = images[idx];
                        final imageUrl = img['imageUrl'] ?? '';
                        final detections = (img['results'] as List?) ?? [];
                        final int detectionCount =
                            detections
                                .where(
                                  (d) => d is Map && d['boundingBox'] != null,
                                )
                                .length;

                        // Debug: Print image path information
                        print('🖼️ Image $idx debug:');
                        print('🖼️   - imageUrl: $imageUrl');
                        print('🖼️   - detections count: ${detections.length}');

                        return GestureDetector(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder:
                                  (context) => Dialog(
                                    backgroundColor: Colors.transparent,
                                    insetPadding: const EdgeInsets.all(16),
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final imageWidth = constraints.maxWidth;
                                        final imageHeight =
                                            constraints.maxHeight;
                                        return Stack(
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: _buildImageWidget(
                                                imageUrl,
                                                width: imageWidth,
                                                height: imageHeight,
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                            if (_showBoundingBoxes &&
                                                detections.isNotEmpty)
                                              Builder(
                                                builder: (context) {
                                                  // Try to get stored image dimensions for fast loading
                                                  final storedImageWidth =
                                                      img['imageWidth'] as num?;
                                                  final storedImageHeight =
                                                      img['imageHeight']
                                                          as num?;

                                                  if (storedImageWidth !=
                                                          null &&
                                                      storedImageHeight !=
                                                          null) {
                                                    // Use stored dimensions for instant loading
                                                    final imageSize = Size(
                                                      storedImageWidth
                                                          .toDouble(),
                                                      storedImageHeight
                                                          .toDouble(),
                                                    );
                                                    print(
                                                      '🔍 Dialog Fast mode: Using stored dimensions ${imageSize.width}x${imageSize.height}',
                                                    );

                                                    return LayoutBuilder(
                                                      builder: (
                                                        context,
                                                        constraints,
                                                      ) {
                                                        // Calculate the actual displayed image size for BoxFit.contain
                                                        final imgW =
                                                            imageSize.width;
                                                        final imgH =
                                                            imageSize.height;
                                                        final widgetW =
                                                            constraints
                                                                .maxWidth;
                                                        final widgetH =
                                                            constraints
                                                                .maxHeight;

                                                        // Calculate scale and offset for BoxFit.contain (not cover)
                                                        final widgetAspect =
                                                            widgetW / widgetH;
                                                        final imageAspect =
                                                            imgW / imgH;
                                                        double displayW,
                                                            displayH,
                                                            dx = 0,
                                                            dy = 0;

                                                        if (widgetAspect >
                                                            imageAspect) {
                                                          // Widget is wider than image - height constrained
                                                          displayH = widgetH;
                                                          displayW =
                                                              widgetH *
                                                              imageAspect;
                                                          dx =
                                                              (widgetW -
                                                                  displayW) /
                                                              2;
                                                        } else {
                                                          // Widget is taller than image - width constrained
                                                          displayW = widgetW;
                                                          displayH =
                                                              widgetW /
                                                              imageAspect;
                                                          dy =
                                                              (widgetH -
                                                                  displayH) /
                                                              2;
                                                        }

                                                        print(
                                                          '🔍 Dialog: Widget dimensions: ${widgetW}x${widgetH}',
                                                        );
                                                        print(
                                                          '🔍 Dialog: Image dimensions: ${imgW}x${imgH}',
                                                        );
                                                        print(
                                                          '🔍 Dialog: Displayed dimensions: ${displayW}x${displayH}',
                                                        );
                                                        print(
                                                          '🔍 Dialog: Offset: ($dx, $dy)',
                                                        );

                                                        return CustomPaint(
                                                          painter: DetectionPainter(
                                                            results:
                                                                detections
                                                                    .where(
                                                                      (d) =>
                                                                          d['boundingBox'] !=
                                                                          null,
                                                                    )
                                                                    .map((d) {
                                                                      final left =
                                                                          (d['boundingBox']['left']
                                                                                  as num)
                                                                              .toDouble();
                                                                      final top =
                                                                          (d['boundingBox']['top']
                                                                                  as num)
                                                                              .toDouble();
                                                                      final right =
                                                                          (d['boundingBox']['right']
                                                                                  as num)
                                                                              .toDouble();
                                                                      final bottom =
                                                                          (d['boundingBox']['bottom']
                                                                                  as num)
                                                                              .toDouble();

                                                                      return DetectionResult(
                                                                        label:
                                                                            d['disease'],
                                                                        confidence:
                                                                            d['confidence'],
                                                                        boundingBox: Rect.fromLTRB(
                                                                          left,
                                                                          top,
                                                                          right,
                                                                          bottom,
                                                                        ),
                                                                      );
                                                                    })
                                                                    .toList(),
                                                            originalImageSize:
                                                                imageSize,
                                                            displayedImageSize:
                                                                Size(
                                                                  displayW,
                                                                  displayH,
                                                                ),
                                                            displayedImageOffset:
                                                                Offset(dx, dy),
                                                          ),
                                                          size: Size(
                                                            widgetW,
                                                            widgetH,
                                                          ),
                                                        );
                                                      },
                                                    );
                                                  } else {
                                                    // Fallback to slow method for old data
                                                    return FutureBuilder<Size>(
                                                      future: _getImageSize(
                                                        imageUrl.isNotEmpty
                                                            ? NetworkImage(
                                                              imageUrl,
                                                            )
                                                            : FileImage(
                                                              File(imageUrl),
                                                            ),
                                                      ),
                                                      builder: (
                                                        context,
                                                        snapshot,
                                                      ) {
                                                        // Only show bounding boxes if we have image size data (online mode)
                                                        if (!snapshot.hasData) {
                                                          print(
                                                            '🔍 Dialog: Offline mode - No image size data, hiding bounding boxes',
                                                          );
                                                          return const SizedBox.shrink();
                                                        }

                                                        final imageSize =
                                                            snapshot.data!;
                                                        print(
                                                          '🔍 Dialog Slow mode: Image size loaded from network ${imageSize.width}x${imageSize.height}',
                                                        );

                                                        return LayoutBuilder(
                                                          builder: (
                                                            context,
                                                            constraints,
                                                          ) {
                                                            // Calculate the actual displayed image size for BoxFit.contain
                                                            final imgW =
                                                                imageSize.width;
                                                            final imgH =
                                                                imageSize
                                                                    .height;
                                                            final widgetW =
                                                                constraints
                                                                    .maxWidth;
                                                            final widgetH =
                                                                constraints
                                                                    .maxHeight;

                                                            // Calculate scale and offset for BoxFit.contain (not cover)
                                                            final widgetAspect =
                                                                widgetW /
                                                                widgetH;
                                                            final imageAspect =
                                                                imgW / imgH;
                                                            double displayW,
                                                                displayH,
                                                                dx = 0,
                                                                dy = 0;

                                                            if (widgetAspect >
                                                                imageAspect) {
                                                              // Widget is wider than image - height constrained
                                                              displayH =
                                                                  widgetH;
                                                              displayW =
                                                                  widgetH *
                                                                  imageAspect;
                                                              dx =
                                                                  (widgetW -
                                                                      displayW) /
                                                                  2;
                                                            } else {
                                                              // Widget is taller than image - width constrained
                                                              displayW =
                                                                  widgetW;
                                                              displayH =
                                                                  widgetW /
                                                                  imageAspect;
                                                              dy =
                                                                  (widgetH -
                                                                      displayH) /
                                                                  2;
                                                            }

                                                            print(
                                                              '🔍 Dialog: Widget dimensions: ${widgetW}x${widgetH}',
                                                            );
                                                            print(
                                                              '🔍 Dialog: Image dimensions: ${imgW}x${imgH}',
                                                            );
                                                            print(
                                                              '🔍 Dialog: Displayed dimensions: ${displayW}x${displayH}',
                                                            );
                                                            print(
                                                              '🔍 Dialog: Offset: ($dx, $dy)',
                                                            );

                                                            return CustomPaint(
                                                              painter: DetectionPainter(
                                                                results:
                                                                    detections
                                                                        .where(
                                                                          (d) =>
                                                                              d['boundingBox'] !=
                                                                              null,
                                                                        )
                                                                        .map((
                                                                          d,
                                                                        ) {
                                                                          final left =
                                                                              (d['boundingBox']['left']
                                                                                      as num)
                                                                                  .toDouble();
                                                                          final top =
                                                                              (d['boundingBox']['top']
                                                                                      as num)
                                                                                  .toDouble();
                                                                          final right =
                                                                              (d['boundingBox']['right']
                                                                                      as num)
                                                                                  .toDouble();
                                                                          final bottom =
                                                                              (d['boundingBox']['bottom']
                                                                                      as num)
                                                                                  .toDouble();

                                                                          return DetectionResult(
                                                                            label:
                                                                                d['disease'],
                                                                            confidence:
                                                                                d['confidence'],
                                                                            boundingBox: Rect.fromLTRB(
                                                                              left,
                                                                              top,
                                                                              right,
                                                                              bottom,
                                                                            ),
                                                                          );
                                                                        })
                                                                        .toList(),
                                                                originalImageSize:
                                                                    imageSize,
                                                                displayedImageSize:
                                                                    Size(
                                                                      displayW,
                                                                      displayH,
                                                                    ),
                                                                displayedImageOffset:
                                                                    Offset(
                                                                      dx,
                                                                      dy,
                                                                    ),
                                                              ),
                                                              size: Size(
                                                                widgetW,
                                                                widgetH,
                                                              ),
                                                            );
                                                          },
                                                        );
                                                      },
                                                    );
                                                  }
                                                },
                                              ),
                                            Positioned(
                                              top: 8,
                                              right: 8,
                                              child: IconButton(
                                                icon: const Icon(
                                                  Icons.close,
                                                  color: Colors.white,
                                                ),
                                                onPressed:
                                                    () =>
                                                        Navigator.pop(context),
                                              ),
                                            ),
                                            // Navigation: Previous
                                            Positioned(
                                              left: 0,
                                              top: 0,
                                              bottom: 0,
                                              child: Center(
                                                child: IconButton(
                                                  iconSize: 36,
                                                  color: Colors.white,
                                                  icon: const Icon(
                                                    Icons.chevron_left,
                                                  ),
                                                  onPressed:
                                                      idx > 0
                                                          ? () {
                                                            Navigator.pop(
                                                              context,
                                                            );
                                                            Future.microtask(
                                                              () =>
                                                                  _openImageViewer(
                                                                    idx - 1,
                                                                  ),
                                                            );
                                                          }
                                                          : null,
                                                ),
                                              ),
                                            ),
                                            // Navigation: Next
                                            Positioned(
                                              right: 0,
                                              top: 0,
                                              bottom: 0,
                                              child: Center(
                                                child: IconButton(
                                                  iconSize: 36,
                                                  color: Colors.white,
                                                  icon: const Icon(
                                                    Icons.chevron_right,
                                                  ),
                                                  onPressed:
                                                      idx < images.length - 1
                                                          ? () {
                                                            Navigator.pop(
                                                              context,
                                                            );
                                                            Future.microtask(
                                                              () =>
                                                                  _openImageViewer(
                                                                    idx + 1,
                                                                  ),
                                                            );
                                                          }
                                                          : null,
                                                ),
                                              ),
                                            ),
                                            // Index indicator
                                            Positioned(
                                              bottom: 8,
                                              left: 0,
                                              right: 0,
                                              child: Center(
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 6,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black
                                                        .withOpacity(0.6),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '${idx + 1} / ${images.length}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                            );
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _buildImageWidget(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              if (_showBoundingBoxes && detections.isNotEmpty)
                                Builder(
                                  builder: (context) {
                                    // Try to get stored image dimensions for fast loading
                                    final storedImageWidth =
                                        img['imageWidth'] as num?;
                                    final storedImageHeight =
                                        img['imageHeight'] as num?;

                                    if (storedImageWidth != null &&
                                        storedImageHeight != null) {
                                      // Use stored dimensions for instant loading
                                      final imageSize = Size(
                                        storedImageWidth.toDouble(),
                                        storedImageHeight.toDouble(),
                                      );
                                      print(
                                        '🔍 Fast mode: Using stored dimensions ${imageSize.width}x${imageSize.height}',
                                      );

                                      return LayoutBuilder(
                                        builder: (context, constraints) {
                                          // Calculate the actual displayed image size
                                          final imgW = imageSize.width;
                                          final imgH = imageSize.height;
                                          final widgetW = constraints.maxWidth;
                                          final widgetH = constraints.maxHeight;

                                          // Calculate scale and offset for BoxFit.cover
                                          final scale =
                                              imgW / imgH > widgetW / widgetH
                                                  ? widgetH /
                                                      imgH // Height constrained
                                                  : widgetW /
                                                      imgW; // Width constrained

                                          final scaledW = imgW * scale;
                                          final scaledH = imgH * scale;
                                          final dx = (widgetW - scaledW) / 2;
                                          final dy = (widgetH - scaledH) / 2;

                                          return CustomPaint(
                                            painter: DetectionPainter(
                                              results:
                                                  detections
                                                      .map((d) {
                                                        if (d == null ||
                                                            d['disease'] ==
                                                                null ||
                                                            d['confidence'] ==
                                                                null ||
                                                            d['boundingBox'] ==
                                                                null ||
                                                            d['boundingBox']['left'] ==
                                                                null ||
                                                            d['boundingBox']['top'] ==
                                                                null ||
                                                            d['boundingBox']['right'] ==
                                                                null ||
                                                            d['boundingBox']['bottom'] ==
                                                                null) {
                                                          print(
                                                            '❌ Invalid detection data: $d',
                                                          );
                                                          return null;
                                                        }

                                                        final left =
                                                            (d['boundingBox']['left']
                                                                    as num)
                                                                .toDouble();
                                                        final top =
                                                            (d['boundingBox']['top']
                                                                    as num)
                                                                .toDouble();
                                                        final right =
                                                            (d['boundingBox']['right']
                                                                    as num)
                                                                .toDouble();
                                                        final bottom =
                                                            (d['boundingBox']['bottom']
                                                                    as num)
                                                                .toDouble();

                                                        return DetectionResult(
                                                          label:
                                                              d['disease']
                                                                  .toString(),
                                                          confidence:
                                                              (d['confidence']
                                                                      as num)
                                                                  .toDouble(),
                                                          boundingBox:
                                                              Rect.fromLTRB(
                                                                left,
                                                                top,
                                                                right,
                                                                bottom,
                                                              ),
                                                        );
                                                      })
                                                      .whereType<
                                                        DetectionResult
                                                      >()
                                                      .toList(),
                                              originalImageSize: imageSize,
                                              displayedImageSize: Size(
                                                scaledW,
                                                scaledH,
                                              ),
                                              displayedImageOffset: Offset(
                                                dx,
                                                dy,
                                              ),
                                            ),
                                            size: Size(widgetW, widgetH),
                                          );
                                        },
                                      );
                                    } else {
                                      // Fallback to slow method for old data
                                      return FutureBuilder<Size>(
                                        future: _getImageSize(
                                          imageUrl.isNotEmpty
                                              ? NetworkImage(imageUrl)
                                              : FileImage(File(imageUrl)),
                                        ),
                                        builder: (context, snapshot) {
                                          if (!snapshot.hasData) {
                                            print(
                                              '🔍 Offline mode: No image size data, hiding bounding boxes',
                                            );
                                            return const SizedBox.shrink();
                                          }

                                          final imageSize = snapshot.data!;
                                          print(
                                            '🔍 Slow mode: Image size loaded from network ${imageSize.width}x${imageSize.height}',
                                          );

                                          return LayoutBuilder(
                                            builder: (context, constraints) {
                                              // Calculate the actual displayed image size
                                              final imgW = imageSize.width;
                                              final imgH = imageSize.height;
                                              final widgetW =
                                                  constraints.maxWidth;
                                              final widgetH =
                                                  constraints.maxHeight;

                                              // Calculate scale and offset for BoxFit.cover
                                              final scale =
                                                  imgW / imgH >
                                                          widgetW / widgetH
                                                      ? widgetH /
                                                          imgH // Height constrained
                                                      : widgetW /
                                                          imgW; // Width constrained

                                              final scaledW = imgW * scale;
                                              final scaledH = imgH * scale;
                                              final dx =
                                                  (widgetW - scaledW) / 2;
                                              final dy =
                                                  (widgetH - scaledH) / 2;

                                              return CustomPaint(
                                                painter: DetectionPainter(
                                                  results:
                                                      detections
                                                          .map((d) {
                                                            if (d == null ||
                                                                d['disease'] ==
                                                                    null ||
                                                                d['confidence'] ==
                                                                    null ||
                                                                d['boundingBox'] ==
                                                                    null ||
                                                                d['boundingBox']['left'] ==
                                                                    null ||
                                                                d['boundingBox']['top'] ==
                                                                    null ||
                                                                d['boundingBox']['right'] ==
                                                                    null ||
                                                                d['boundingBox']['bottom'] ==
                                                                    null) {
                                                              print(
                                                                '❌ Invalid detection data: $d',
                                                              );
                                                              return null;
                                                            }

                                                            final left =
                                                                (d['boundingBox']['left']
                                                                        as num)
                                                                    .toDouble();
                                                            final top =
                                                                (d['boundingBox']['top']
                                                                        as num)
                                                                    .toDouble();
                                                            final right =
                                                                (d['boundingBox']['right']
                                                                        as num)
                                                                    .toDouble();
                                                            final bottom =
                                                                (d['boundingBox']['bottom']
                                                                        as num)
                                                                    .toDouble();

                                                            return DetectionResult(
                                                              label:
                                                                  d['disease']
                                                                      .toString(),
                                                              confidence:
                                                                  (d['confidence']
                                                                          as num)
                                                                      .toDouble(),
                                                              boundingBox:
                                                                  Rect.fromLTRB(
                                                                    left,
                                                                    top,
                                                                    right,
                                                                    bottom,
                                                                  ),
                                                            );
                                                          })
                                                          .whereType<
                                                            DetectionResult
                                                          >()
                                                          .toList(),
                                                  originalImageSize: imageSize,
                                                  displayedImageSize: Size(
                                                    scaledW,
                                                    scaledH,
                                                  ),
                                                  displayedImageOffset: Offset(
                                                    dx,
                                                    dy,
                                                  ),
                                                ),
                                                size: Size(widgetW, widgetH),
                                              );
                                            },
                                          );
                                        },
                                      );
                                    }
                                  },
                                ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    detectionCount > 0
                                        ? (detectionCount == 1
                                            ? tr(
                                              'detections_one',
                                              namedArgs: {'count': '1'},
                                            )
                                            : tr(
                                              'detections_other',
                                              namedArgs: {
                                                'count': '$detectionCount',
                                              },
                                            ))
                                        : tr('no_detections'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            // Disease Summary
            Padding(
              padding: const EdgeInsets.all(16),
              child: Builder(
                builder: (context) {
                  final stats = _getDiseaseConfidenceSummary();
                  final sortedSummary = [...stats]..sort((a, b) {
                    final aAvg = (a['avgConfidence'] as double?) ?? 0.0;
                    final bAvg = (b['avgConfidence'] as double?) ?? 0.0;
                    return bAvg.compareTo(aAvg);
                  });
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('disease_summary'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (isCompleted &&
                          widget.request['expertDiseaseSummaryChangeLog'] != null)
                        Builder(
                          builder: (context) {
                            final log =
                                widget.request['expertDiseaseSummaryChangeLog'];
                            if (log is! Map) return const SizedBox.shrink();
                            final msg = (log['message'] ?? '').toString().trim();
                            if (msg.isEmpty) return const SizedBox.shrink();
                            return Card(
                              color: Colors.blue.shade50,
                              elevation: 0,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.blue.shade700,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        msg,
                                        style: TextStyle(
                                          color: Colors.blue.shade900,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          height: 1.25,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 16),
                      ...sortedSummary.map<Widget>((d) {
                        final label = (d['label'] ?? 'unknown').toString();
                        final avg = (d['avgConfidence'] as num?)?.toDouble() ?? 0.0;
                        final mx = (d['maxConfidence'] as num?)?.toDouble() ?? avg;
                        final color = _getExpertDiseaseColor(label);
                        final isHealthy = PigDiseaseUI.normalizeKey(label) == 'healthy';
                        final isUnknown = PigDiseaseUI.normalizeKey(label) == 'unknown';
                        // If this report is completed, it was expert-validated already,
                        // so always allow recommendations (except for healthy/unknown).
                        // Otherwise, show recommendations if ANY detection (maxConfidence) is >= 70%
                        final canShowRecommendation = !isHealthy &&
                            !isUnknown &&
                            (isCompleted || mx >= _recommendationAvgThreshold);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Center(
                                        child: Icon(
                                          isHealthy
                                              ? Icons.check_circle
                                              : Icons.local_florist,
                                          size: 16,
                                          color: color,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _formatExpertLabel(label),
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'Avg ${(avg * 100).toStringAsFixed(1)}%',
                                        style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Average confidence',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child: LinearProgressIndicator(
                                              value: avg.clamp(0.0, 1.0),
                                              backgroundColor: color
                                                  .withOpacity(0.1),
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    color,
                                                  ),
                                              minHeight: 8,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '${(avg * 100).toStringAsFixed(1)}%',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: color,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Max confidence: ${(mx * 100).toStringAsFixed(1)}%',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                ),
                                if (canShowRecommendation) ...[
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _showDiseaseRecommendations(context, label),
                                      icon: Icon(
                                        Icons.medical_services_outlined,
                                        color: color,
                                        size: 18,
                                      ),
                                      label: Text(
                                        'See recommendation',
                                        style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(color: color.withOpacity(0.6)),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  );
                },
              ),
            ),
            // Expert Review Section
            if (isCompleted && expertReview != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('expert_comment'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if ((expertReview['comment'] ?? '').toString().trim().isNotEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            (expertReview['comment'] ?? '').toString().trim(),
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      )
                    else
                      Card(
                        color: Colors.blue.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.blue.shade700,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'No comment was provided by the expert for this report.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.blue.shade900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              )
            else if (!isCompleted)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    tr('awaiting_expert_review'),
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getExpertDiseaseColor(String diseaseName) {
    return PigDiseaseUI.colorFor(diseaseName);
  }

  Future<Size> _getImageSize(ImageProvider provider) async {
    final Completer<Size> completer = Completer();
    final ImageStreamListener listener = ImageStreamListener((
      ImageInfo info,
      bool _,
    ) {
      final myImage = info.image;
      completer.complete(
        Size(myImage.width.toDouble(), myImage.height.toDouble()),
      );
    });
    provider.resolve(const ImageConfiguration()).addListener(listener);
    final size = await completer.future;
    return size;
  }

  Widget _buildImageWidget(
    String path, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    print('🖼️ _buildImageWidget called with path: $path');

    if (path.isEmpty) {
      print('🖼️ Path is empty, showing placeholder');
      return Container(
        width: width,
        height: height,
        color: Colors.grey[200],
        child: const Icon(Icons.broken_image, size: 40, color: Colors.grey),
      );
    }
    if (path.startsWith('http')) {
      print('🖼️ Loading network image: $path');
      return CachedNetworkImage(
        imageUrl: path,
        width: width,
        height: height,
        fit: fit,
        placeholder:
            (context, url) => const Center(child: CircularProgressIndicator()),
        errorWidget: (context, url, error) {
          print('🖼️ Network image error: $error');
          return const Icon(Icons.broken_image, size: 40, color: Colors.grey);
        },
      );
    } else if (_isFilePath(path)) {
      print('🖼️ Loading file image: $path');
      final file = File(path);
      if (!file.existsSync()) {
        print('🖼️ File does not exist: $path');
        return Container(
          width: width,
          height: height,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, size: 40, color: Colors.grey),
        );
      }
      return Image.file(
        file,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          print('🖼️ File image error: $error');
          return const Icon(Icons.broken_image, size: 40, color: Colors.grey);
        },
      );
    } else {
      print('🖼️ Loading asset image: $path');
      return Image.asset(
        path,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          print('🖼️ Asset image error: $error');
          return const Icon(Icons.broken_image, size: 40, color: Colors.grey);
        },
      );
    }
  }

  bool _isFilePath(String path) {
    // Heuristic: treat as file path if it is absolute or starts with /data/ or C:/ or similar
    return path.startsWith('/') || path.contains(':');
  }

  String _formatExpertLabel(String label) {
    return PigDiseaseUI.displayName(label);
  }
}
