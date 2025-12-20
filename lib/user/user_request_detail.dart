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

class UserRequestDetail extends StatefulWidget {
  final Map<String, dynamic> request;
  const UserRequestDetail({Key? key, required this.request}) : super(key: key);

  @override
  _UserRequestDetailState createState() => _UserRequestDetailState();
}

class _UserRequestDetailState extends State<UserRequestDetail> {
  bool _showBoundingBoxes = true;

  String _translatePreventiveMeasure(String english) {
    // Map known expert defaults to localization keys
    final Map<String, String> map = {
      'Regular pruning': 'pm_regular_pruning',
      'Proper spacing between plants': 'pm_proper_spacing',
      'Adequate ventilation': 'pm_adequate_ventilation',
      'Regular watering': 'pm_regular_watering',
      'Proper fertilization': 'pm_proper_fertilization',
      'Pest monitoring': 'pm_pest_monitoring',
      'Soil testing': 'pm_soil_testing',
      'Crop rotation': 'pm_crop_rotation',
      'Remove infected leaves': 'pm_remove_infected_leaves',
      'Improve air circulation': 'pm_improve_air_circulation',
    };

    final key = map[english];
    if (key != null) {
      return tr(key);
    }
    // Fallback: return original text if we don't recognize it
    return english;
  }

  // Check if treatment plan has any content
  bool _hasTreatmentContent(Map<String, dynamic>? treatmentPlan) {
    if (treatmentPlan == null) return false;
    
    final recommendations = treatmentPlan['recommendations'] as List?;
    if (recommendations == null || recommendations.isEmpty) return false;
    
    // Check if any recommendation has actual content
    for (var rec in recommendations) {
      if (rec == null) continue;
      final treatment = rec['treatment']?.toString().trim() ?? '';
      final dosage = rec['dosage']?.toString().trim() ?? '';
      final frequency = rec['frequency']?.toString().trim() ?? '';
      final precautions = rec['precautions']?.toString().trim() ?? '';
      
      if (treatment.isNotEmpty || dosage.isNotEmpty || 
          frequency.isNotEmpty || precautions.isNotEmpty) {
        return true;
      }
    }
    
    return false;
  }

  // Check if preventive measures has any content
  bool _hasPreventiveMeasures(Map<String, dynamic>? treatmentPlan) {
    if (treatmentPlan == null) return false;
    
    final measures = treatmentPlan['preventiveMeasures'] as List?;
    if (measures == null || measures.isEmpty) return false;
    
    // Check if any measure has actual content
    for (var measure in measures) {
      if (measure?.toString().trim().isNotEmpty ?? false) {
        return true;
      }
    }
    
    return false;
  }

  @override
  void initState() {
    super.initState();
    _loadBoundingBoxPreference();
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
    final diseaseSummary = (widget.request['diseaseSummary'] as List?) ?? [];
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
                                          ? tr('pending_review')
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
                  final mergedSummary = _mergeDiseaseSummary(diseaseSummary);
                  final totalLeaves = mergedSummary.fold<int>(
                    0,
                    (sum, d) => sum + (d['count'] as int? ?? 0),
                  );
                  final sortedSummary = [...mergedSummary]..sort((a, b) {
                    final percA =
                        totalLeaves == 0
                            ? 0.0
                            : (a['count'] as int? ?? 0) / totalLeaves;
                    final percB =
                        totalLeaves == 0
                            ? 0.0
                            : (b['count'] as int? ?? 0) / totalLeaves;
                    return percB.compareTo(percA);
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
                      const SizedBox(height: 16),
                      ...sortedSummary.map<Widget>((disease) {
                        final diseaseName =
                            (disease['disease'] ?? disease['name'] ?? 'Unknown')
                                .toString();
                        final count = disease['count'] ?? 0;
                        final percentage =
                            totalLeaves == 0 ? 0.0 : count / totalLeaves;
                        final color = _getExpertDiseaseColor(diseaseName);
                        final isHealthy =
                            diseaseName.toLowerCase() == 'healthy';
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
                                        _formatExpertLabel(diseaseName),
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
                                        tr(
                                          'found_count',
                                          namedArgs: {'count': '$count'},
                                        ),
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
                                            tr('percentage_of_total_leaves'),
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
                                              value: percentage,
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
                                      '${(percentage * 100).toStringAsFixed(1)}%',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: color,
                                      ),
                                    ),
                                  ],
                                ),
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
                    Row(
                      children: [
                        const Icon(Icons.person, color: Colors.green, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          tr(
                            'reviewed_by',
                            namedArgs: {
                              'name':
                                  expertName.isNotEmpty ? expertName : 'Expert',
                            },
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr('expert_review'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Severity Assessment
                    if (expertReview['severityAssessment'] != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('severity_assessment'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.warning,
                                    color: _getSeverityColor(
                                      expertReview['severityAssessment']['level'] ??
                                          'low',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatSeverityLevel(
                                      (expertReview['severityAssessment']['level'] ??
                                              'low')
                                          .toString(),
                                    ),
                                    style: TextStyle(
                                      color: _getSeverityColor(
                                        expertReview['severityAssessment']['level'] ??
                                            'low',
                                      ),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    // Treatment Plan (only show if has content)
                    if (_hasTreatmentContent(expertReview['treatmentPlan']))
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('treatment_plan'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...((expertReview['treatmentPlan']['recommendations']
                                          as List?) ??
                                      [])
                                  .map<Widget>((treatment) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (treatment['treatment'] != null &&
                                            treatment['treatment']
                                                .toString()
                                                .trim()
                                                .isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 4,
                                            ),
                                            child: Text(
                                              '${tr('treatment')} ${treatment['treatment']}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        if (treatment['dosage'] != null &&
                                            treatment['dosage']
                                                .toString()
                                                .trim()
                                                .isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 4,
                                            ),
                                            child: Text(
                                              '${tr('dosage')} ${treatment['dosage']}',
                                            ),
                                          ),
                                        if (treatment['frequency'] != null &&
                                            treatment['frequency']
                                                .toString()
                                                .trim()
                                                .isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 4,
                                            ),
                                            child: Text(
                                              '${tr('frequency')} ${treatment['frequency']}',
                                            ),
                                          ),
                                        if (treatment['precautions'] != null &&
                                            treatment['precautions']
                                                .toString()
                                                .trim()
                                                .isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 4,
                                            ),
                                            child: Text(
                                              '${tr('precautions')} ${treatment['precautions']}',
                                            ),
                                          ),
                                        const SizedBox(height: 8),
                                      ],
                                    );
                                  })
                                  .toList(),
                            ],
                          ),
                        ),
                      ),
                    if (_hasTreatmentContent(expertReview['treatmentPlan']))
                      const SizedBox(height: 16),
                    // Preventive Measures (only show if has content)
                    if (_hasPreventiveMeasures(expertReview['treatmentPlan']))
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('preventive_measures'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children:
                                    ((expertReview['treatmentPlan']['preventiveMeasures']
                                                as List?) ??
                                            [])
                                        .map<Widget>((measure) {
                                          return Chip(
                                            label: Text(
                                              _translatePreventiveMeasure(
                                                measure.toString(),
                                              ),
                                            ),
                                            backgroundColor: Colors.green
                                                .withOpacity(0.1),
                                          );
                                        })
                                        .toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_hasPreventiveMeasures(expertReview['treatmentPlan']))
                      const SizedBox(height: 16),
                    // Info message if both treatment and preventive measures are empty
                    if (!_hasTreatmentContent(expertReview['treatmentPlan']) &&
                        !_hasPreventiveMeasures(expertReview['treatmentPlan']))
                      Card(
                        color: Colors.blue.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.blue.shade700,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  tr('no_treatment_details_note'),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!_hasTreatmentContent(expertReview['treatmentPlan']) &&
                        !_hasPreventiveMeasures(expertReview['treatmentPlan']))
                      const SizedBox(height: 16),
                    // Expert Comment
                    if (expertReview['comment'] != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('expert_comment'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                expertReview['comment'],
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Colors.black87,
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

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatSeverityLevel(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return tr('severity_high');
      case 'medium':
        return tr('severity_medium');
      case 'low':
        return tr('severity_low');
      default:
        return severity.toUpperCase();
    }
  }

  Color _getExpertDiseaseColor(String diseaseName) {
    return PigDiseaseUI.colorFor(diseaseName);
  }

  List<Map<String, dynamic>> _mergeDiseaseSummary(List<dynamic> summary) {
    final Map<String, Map<String, dynamic>> merged = {};
    for (final entry in summary) {
      final rawName = entry['disease'] ?? entry['name'] ?? 'Unknown';
      final disease =
          rawName.toString().toLowerCase().replaceAll('_', ' ').trim();
      final count = entry['count'] ?? 0;
      if (!merged.containsKey(disease)) {
        merged[disease] = {'disease': rawName, 'count': count};
      } else {
        merged[disease]!['count'] += count;
      }
    }
    return merged.values.toList();
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
