import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'user_request_detail.dart';
import '../shared/pig_disease_ui.dart';

class UserRequestList extends StatefulWidget {
  final List<Map<String, dynamic>> requests;
  const UserRequestList({Key? key, required this.requests}) : super(key: key);

  @override
  State<UserRequestList> createState() => _UserRequestListState();
}

class _UserRequestListState extends State<UserRequestList> {
  // Remove the bounding box preference for list view - we don't want bounding boxes in the list
  // bool _showBoundingBoxes = true;

  // Track which completed requests were already seen (to hide the "New" badge)
  Set<String> _seenCompletedIds = <String>{};

  @override
  void initState() {
    super.initState();
    // Remove bounding box preference loading for list view
    // _loadBoundingBoxPreference();
    _loadSeenCompleted();
    _seedBaselineIfNeeded();
  }

  Future<void> _loadSeenCompleted() async {
    try {
      final box = await Hive.openBox('userRequestsSeenBox');
      final saved = box.get('seenCompletedIds', defaultValue: []);
      if (saved is List) {
        setState(() {
          _seenCompletedIds = saved.map((e) => e.toString()).toSet();
        });
      }
    } catch (_) {}
  }

  // Mark all current completed IDs as seen on first run so old items don't show as New
  Future<void> _seedBaselineIfNeeded() async {
    try {
      final box = await Hive.openBox('userRequestsSeenBox');
      final bool baselineSet =
          box.get('completedBaselineSet', defaultValue: false) as bool;
      final savedList = box.get('seenCompletedIds', defaultValue: []);
      final bool noSaved = savedList is List ? savedList.isEmpty : true;
      if (baselineSet || !noSaved) return;
      final completedIds = <String>{};
      for (final req in widget.requests) {
        final status = (req['status'] ?? '').toString();
        if (status == 'completed' || status == 'reviewed') {
          final id = (req['id'] ?? req['requestId'] ?? '').toString();
          if (id.isNotEmpty) completedIds.add(id);
        }
      }
      await box.put('seenCompletedIds', completedIds.toList());
      await box.put('completedBaselineSet', true);
      setState(() {
        _seenCompletedIds = completedIds;
      });
    } catch (_) {}
  }

  Future<void> _markCompletedSeen(String id) async {
    if (id.isEmpty) return;
    if (_seenCompletedIds.contains(id)) return;
    setState(() {
      _seenCompletedIds.add(id);
    });
    try {
      final box = await Hive.openBox('userRequestsSeenBox');
      await box.put('seenCompletedIds', _seenCompletedIds.toList());
    } catch (_) {}
  }

  // Remove these methods as they're not needed for list view
  // Future<void> _loadBoundingBoxPreference() async {
  //   final box = await Hive.openBox('userBox');
  //   final savedPreference = box.get('showBoundingBoxes');
  //   if (savedPreference != null) {
  //     setState(() {
  //       _showBoundingBoxes = savedPreference as bool;
  //     });
  //   }
  // }

  // Future<void> _saveBoundingBoxPreference(bool value) async {
  //   final box = await Hive.openBox('userBox');
  //   await box.put('showBoundingBoxes', value);
  // }

  Widget _buildImageWidgetWithBoundingBoxes(
    String path,
    List detections, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    // For list view, always show images without bounding boxes
    return _buildImageWidget(path, width: width, height: height, fit: fit);

    // Comment out the bounding box logic for list view
    // if (!_showBoundingBoxes || detections.isEmpty) {
    //   return _buildImageWidget(path, width: width, height: height, fit: fit);
    // }

    // return FutureBuilder<Size>(
    //   future: _getImageSize(
    //     path.startsWith('http') ? NetworkImage(path) : FileImage(File(path)),
    //   ),
    //   builder: (context, snapshot) {
    //     if (!snapshot.hasData) {
    //       return _buildImageWidget(
    //         path,
    //         width: width,
    //         height: height,
    //         fit: fit,
    //       );
    //     }

    //     final imageSize = snapshot.data!;
    //     final widgetSize = Size(width ?? 80, height ?? 80);

    //     // Calculate scaling for BoxFit.cover
    //     final scaleX = widgetSize.width / imageSize.width;
    //     final scaleY = widgetSize.height / imageSize.height;
    //     final scale = scaleX > scaleY ? scaleX : scaleY;

    //     final scaledW = imageSize.width * scale;
    //     final scaledH = imageSize.height * scale;
    //     final dx = (widgetSize.width - scaledW) / 2;
    //     final dy = (widgetSize.height - scaledH) / 2;

    //     return Stack(
    //       children: [
    //         _buildImageWidget(path, width: width, height: height, fit: fit),
    //         CustomPaint(
    //           painter: DetectionPainter(
    //             results:
    //                 detections
    //                     .map((d) {
    //                       if (d == null ||
    //                           d['disease'] == null ||
    //                           d['boundingBox'] == null) {
    //                         return null;
    //                       }
    //                       return DetectionResult(
    //                         label: d['disease'].toString(),
    //                         confidence:
    //                             (d['confidence'] as num?)?.toDouble() ?? 0.0,
    //                         boundingBox: Rect.fromLTRB(
    //                           (d['boundingBox']['left'] as num).toDouble(),
    //                           (d['boundingBox']['top'] as num).toDouble(),
    //                           (d['boundingBox']['right'] as num).toDouble(),
    //                           (d['boundingBox']['bottom'] as num).toDouble(),
    //                         ),
    //                       );
    //                     })
    //                     .whereType<DetectionResult>()
    //                     .toList(),
    //             originalImageSize: imageSize,
    //             displayedImageSize: Size(scaledW, scaledH),
    //             displayedImageOffset: Offset(dx, dy),
    //           ),
    //           size: widgetSize,
    //         ),
    //       ],
    //     );
    //   },
    // );
  }

  @override
  Widget build(BuildContext context) {
    // Sort: for completed/reviewed use reviewedAt; otherwise use submittedAt (latest first)
    final sortedRequests = [...widget.requests];
    DateTime? _prefDate(Map<String, dynamic> m) {
      final status = (m['status'] ?? '').toString();
      if ((status == 'completed' || status == 'reviewed') &&
          m['reviewedAt'] != null &&
          m['reviewedAt'].toString().isNotEmpty) {
        return DateTime.tryParse(m['reviewedAt'].toString());
      }
      if (m['submittedAt'] != null && m['submittedAt'].toString().isNotEmpty) {
        return DateTime.tryParse(m['submittedAt'].toString());
      }
      return null;
    }

    sortedRequests.sort((a, b) {
      final dateA = _prefDate(a);
      final dateB = _prefDate(b);
      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return 1;
      if (dateB == null) return -1;
      return dateB.compareTo(dateA); // Descending (latest on top)
    });
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedRequests.length,
      itemBuilder: (context, index) {
        final request = sortedRequests[index];
        return _buildRequestCard(request);
      },
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    // Prefer avgConfidence from diseaseSummary; fallback to computing from detections.
    final dominant = _getDominantDiseaseByAvgConfidence(request);
    final dominantLabel = dominant['label'] as String;
    final dominantAvg = dominant['avgConfidence'] as double;
    final dominantName = PigDiseaseUI.displayName(dominantLabel);
    final dominantColor = PigDiseaseUI.colorFor(dominantLabel);
    final status = request['status']?.toString() ?? 'pending';
    final submittedAt = request['submittedAt']?.toString() ?? '';
    // Format date
    final formattedDate =
        submittedAt.isNotEmpty && DateTime.tryParse(submittedAt) != null
            ? DateFormat(
              'MMM d, yyyy – h:mma',
            ).format(DateTime.parse(submittedAt))
            : submittedAt;
    final isCompleted = status == 'completed' || status == 'reviewed';
    final images = (request['images'] as List?) ?? [];
    final totalImages = images.length;
    // Use imageUrl if present and not empty, else imagePath, else path
    final imageUrl = images.isNotEmpty ? (images[0]['imageUrl'] ?? '') : '';
    final imagePath =
        images.isNotEmpty
            ? (images[0]['imagePath'] ?? images[0]['path'] ?? '')
            : '';
    final displayPath = (imageUrl.isNotEmpty) ? imageUrl : imagePath;

    final String requestId =
        (request['id'] ?? request['requestId'] ?? '').toString();
    final bool isNewCompleted =
        isCompleted &&
        requestId.isNotEmpty &&
        !_seenCompletedIds.contains(requestId);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        onTap: () async {
          if (isNewCompleted) {
            await _markCompletedSeen(requestId);
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UserRequestDetail(request: request),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _buildImageWidgetWithBoundingBoxes(
                      displayPath,
                      images.isNotEmpty
                          ? (images[0]['results'] as List?) ?? []
                          : [],
                      width: 80,
                      height: 80,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dominantName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: dominantColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Avg ${(dominantAvg * 100).toStringAsFixed(1)}%',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          formattedDate,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    isCompleted
                                        ? Colors.green.withOpacity(0.1)
                                        : Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _formatStatusLabel(status),
                                style: TextStyle(
                                  color:
                                      isCompleted
                                          ? Colors.green
                                          : Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (isNewCompleted) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.red.withOpacity(0.3),
                                  ),
                                ),
                                child: const Text(
                                  'New',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (status == 'pending' || status == 'pending_review')
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                      tooltip: tr('delete'),
                      onPressed: () async {
                        debugPrint(
                          '[UserRequestList] delete tapped id=' +
                              ((request['id'] ?? request['requestId'] ?? '')
                                  .toString()) +
                              ' status=' +
                              status,
                        );
                        final docId =
                            (request['_docId'] ??
                                    request['id'] ??
                                    request['requestId'] ??
                                    '')
                                .toString();
                        if (docId.isEmpty) {
                          debugPrint(
                            '[UserRequestList] Cannot delete: missing docId',
                          );
                          await showDialog<void>(
                            context: context,
                            builder:
                                (ctx) => Dialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.shade50,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.warning_amber_rounded,
                                            size: 48,
                                            color: Colors.orange.shade700,
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        Text(
                                          tr('cannot_delete'),
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          tr('cannot_delete_missing_id'),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.orange.shade700,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 14,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              elevation: 0,
                                            ),
                                            child: const Text(
                                              'OK',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                          );
                          return;
                        }

                        debugPrint(
                          '[UserRequestList] showing confirm for docId=' +
                              docId,
                        );
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder:
                              (ctx) => Dialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.delete_outline_rounded,
                                          size: 48,
                                          color: Colors.red.shade700,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      Text(
                                        tr('delete_report_title'),
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        tr('delete_report_confirm'),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed:
                                                  () =>
                                                      Navigator.pop(ctx, false),
                                              style: OutlinedButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 14,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                side: BorderSide(
                                                  color: Colors.grey.shade300,
                                                ),
                                              ),
                                              child: Text(
                                                tr('cancel'),
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: ElevatedButton(
                                              onPressed:
                                                  () =>
                                                      Navigator.pop(ctx, true),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.red.shade700,
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 14,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                elevation: 0,
                                              ),
                                              child: Text(
                                                tr('delete'),
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                        );
                        debugPrint(
                          '[UserRequestList] confirm=' + confirm.toString(),
                        );
                        if (confirm != true) return;

                        // Capture a root-level navigator context BEFORE any delete triggers rebuild
                        final rootNavigator = Navigator.of(
                          context,
                          rootNavigator: true,
                        );
                        final rootContext = rootNavigator.context;
                        debugPrint(
                          '[UserRequestList] captured rootContext for dialogs',
                        );

                        final images = (request['images'] as List?) ?? [];
                        bool imageDeleteError = false;
                        for (final img in images) {
                          try {
                            final storagePath = img['storagePath'] as String?;
                            final imageUrl = img['imageUrl'] as String?;

                            if (storagePath != null && storagePath.isNotEmpty) {
                              debugPrint(
                                '[UserRequestList] deleting Firebase Storage path=' +
                                    storagePath,
                              );
                              await FirebaseStorage.instance
                                  .ref()
                                  .child(storagePath)
                                  .delete();
                            } else if (imageUrl != null &&
                                imageUrl.isNotEmpty) {
                              debugPrint(
                                '[UserRequestList] deleting by imageUrl=' +
                                    imageUrl,
                              );
                              if (imageUrl.startsWith('gs://') ||
                                  imageUrl.startsWith(
                                    'https://firebasestorage.googleapis.com',
                                  )) {
                                await FirebaseStorage.instance
                                    .refFromURL(imageUrl)
                                    .delete();
                              } else {
                                // Legacy Supabase cleanup (best-effort) - network errors are non-critical
                                try {
                                  final uri = Uri.parse(imageUrl);
                                  final segments = uri.pathSegments;
                                  final bucketIndex = segments.indexOf(
                                    'mangosense',
                                  );
                                  if (bucketIndex != -1 &&
                                      bucketIndex + 1 < segments.length) {
                                    final supabase = Supabase.instance.client;
                                    final supabasePath = segments
                                        .sublist(bucketIndex + 1)
                                        .join('/');
                                    await supabase.storage
                                        .from('mangosense')
                                        .remove([supabasePath]);
                                  }
                                } catch (supabaseError) {
                                  // Supabase/network errors for legacy images are non-critical
                                  // Don't flag as error since Firestore deletion is the main operation
                                  debugPrint(
                                    '[UserRequestList] Supabase cleanup failed (non-critical): ' +
                                        supabaseError.toString(),
                                  );
                                }
                              }
                            }
                          } catch (e) {
                            // Only flag as error for Firebase Storage failures, not network issues
                            final errorMsg = e.toString().toLowerCase();
                            final isNetworkError =
                                errorMsg.contains('socket') ||
                                errorMsg.contains('network') ||
                                errorMsg.contains('host lookup') ||
                                errorMsg.contains('failed to resolve');

                            if (!isNetworkError) {
                              debugPrint(
                                '[UserRequestList] image delete error: ' +
                                    e.toString(),
                              );
                              imageDeleteError = true;
                            } else {
                              debugPrint(
                                '[UserRequestList] image delete network error (non-critical): ' +
                                    e.toString(),
                              );
                            }
                          }
                        }
                        try {
                          debugPrint(
                            '[UserRequestList] deleting Firestore docId=' +
                                docId,
                          );
                          await FirebaseFirestore.instance
                              .collection('scan_requests')
                              .doc(docId)
                              .delete();

                          debugPrint(
                            '[UserRequestList] Firestore delete completed; showing success dialog',
                          );

                          // Show dialog using captured rootContext even if this widget unmounted
                          await showDialog<void>(
                            context: rootContext,
                            barrierDismissible: false,
                            builder:
                                (ctx) => Dialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color:
                                                imageDeleteError
                                                    ? Colors.orange.shade50
                                                    : Colors.green.shade50,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            imageDeleteError
                                                ? Icons.warning_amber_rounded
                                                : Icons
                                                    .check_circle_outline_rounded,
                                            size: 48,
                                            color:
                                                imageDeleteError
                                                    ? Colors.orange.shade700
                                                    : Colors.green.shade700,
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        Text(
                                          imageDeleteError
                                              ? tr('session_deleted_with_errors')
                                              : tr('session_deleted'),
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          imageDeleteError
                                              ? tr('session_deleted_with_errors')
                                              : tr('request_deleted_permanently'),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton(
                                            onPressed: () {
                                              debugPrint(
                                                '[UserRequestList] success dialog OK pressed',
                                              );
                                              Navigator.pop(ctx);
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  imageDeleteError
                                                      ? Colors.orange.shade700
                                                      : Colors.green.shade700,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 14,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              elevation: 0,
                                            ),
                                            child: const Text(
                                              'OK',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                          );
                        } catch (e) {
                          debugPrint(
                            '[UserRequestList] Firestore delete error: ' +
                                e.toString(),
                          );
                          // Show error dialog using captured rootContext
                          await showDialog<void>(
                            context: rootContext,
                            builder:
                                (ctx) => Dialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade50,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.error_outline_rounded,
                                            size: 48,
                                            color: Colors.red.shade700,
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        Text(
                                          tr('failed_to_delete_session')
                                              .split(':')
                                              .first,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          tr(
                                            'failed_to_delete_session',
                                            namedArgs: {'error': '$e'},
                                          ),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.red.shade700,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 14,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              elevation: 0,
                                            ),
                                            child: const Text(
                                              'OK',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                          );
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      tr('images'),
                      totalImages.toString(),
                      Icons.image,
                    ),
                  ),
                  Container(width: 1, height: 40, color: Colors.grey[300]),
                  Expanded(
                    child: _buildStatItem(
                      'Avg confidence',
                      '${(dominantAvg * 100).toStringAsFixed(1)}%',
                      Icons.insights,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatStatusLabel(String status) {
    switch (status) {
      case 'pending_review':
        // Farmer-side UX: still show as Pending even if experts are discussing.
        return tr('pending');
      case 'completed':
        return tr('completed');
      default:
        return tr('pending');
    }
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Icon(icon, color: Colors.grey[600], size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        ],
      ),
    );
  }

  /// Returns {'label': <model label>, 'avgConfidence': <0..1> }.
  /// Uses request.diseaseSummary.avgConfidence when present, else computes from detections.
  Map<String, Object> _getDominantDiseaseByAvgConfidence(
    Map<String, dynamic> request,
  ) {
    final diseaseSummary =
        (request['expertDiseaseSummary'] as List?) ??
        (request['diseaseSummary'] as List?) ??
        [];
    if (diseaseSummary.isNotEmpty) {
      double best = -1;
      String bestLabel = 'unknown';
      for (final e in diseaseSummary) {
        if (e is! Map) continue;
        final avg = (e['avgConfidence'] as num?)?.toDouble();
        if (avg == null) continue;
        final label =
            (e['label'] ?? e['disease'] ?? e['name'] ?? 'unknown').toString();
        if (avg > best) {
          best = avg;
          bestLabel = label;
        }
      }
      if (best >= 0) {
        return {'label': bestLabel, 'avgConfidence': best};
      }
    }

    // Fallback: compute from detections stored under images[].results[]
    final images = (request['images'] as List?) ?? [];
    final Map<String, double> sum = {};
    final Map<String, int> n = {};
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
      }
    }
    double best = -1;
    String bestLabel = 'unknown';
    sum.forEach((k, v) {
      final cnt = n[k] ?? 0;
      if (cnt <= 0) return;
      final avg = v / cnt;
      if (avg > best) {
        best = avg;
        bestLabel = k;
      }
    });
    return {'label': bestLabel, 'avgConfidence': best < 0 ? 0.0 : best};
  }
}

Widget _buildImageWidget(
  String path, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) {
  if (path.isEmpty) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: const Icon(Icons.broken_image, size: 40, color: Colors.grey),
    );
  }
  if (path.startsWith('http')) {
    return CachedNetworkImage(
      imageUrl: path,
      width: width,
      height: height,
      fit: fit,
      placeholder:
          (context, url) => const Center(child: CircularProgressIndicator()),
      errorWidget:
          (context, url, error) =>
              const Icon(Icons.broken_image, size: 40, color: Colors.grey),
    );
  } else if (_isFilePath(path)) {
    return Image.file(
      File(path),
      width: width,
      height: height,
      fit: fit,
      errorBuilder:
          (context, error, stackTrace) =>
              const Icon(Icons.broken_image, size: 40, color: Colors.grey),
    );
  } else {
    return Image.asset(
      path,
      width: width,
      height: height,
      fit: fit,
      errorBuilder:
          (context, error, stackTrace) =>
              const Icon(Icons.broken_image, size: 40, color: Colors.grey),
    );
  }
}

bool _isFilePath(String path) {
  // Heuristic: treat as file path if it is absolute or starts with /data/ or C:/ or similar
  return path.startsWith('/') || path.contains(':');
}
