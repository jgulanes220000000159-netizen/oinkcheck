import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import '../user/detection_painter.dart';
import '../user/tflite_detector.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../shared/pig_disease_ui.dart';
import '../shared/report_result_change_log.dart';

class ScanRequestDetail extends StatefulWidget {
  final Map<String, dynamic> request;

  const ScanRequestDetail({Key? key, required this.request}) : super(key: key);

  @override
  _ScanRequestDetailState createState() => _ScanRequestDetailState();
}

class _ScanRequestDetailState extends State<ScanRequestDetail> {
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;
  bool _showBoundingBoxes = true;
  Timer? _heartbeatTimer;

  // Expert-edited report result summary (does NOT change boxes).
  List<Map<String, dynamic>>? _editedDiseaseSummary;
  List<Map<String, dynamic>> _lastSavedSummaryForDiff = const [];

  // Disease information loaded from Firestore (kept for potential future use)
  // Map<String, Map<String, dynamic>> _diseaseInfo = {}; // removed (not used)

  @override
  void initState() {
    super.initState();
    _loadBoundingBoxPreference();
    _claimReportForReview();
    _loadDiseaseInfo();
    _initEditedSummaryFromRequest();
    _initBaselineSummaryForDiff();
  }

  void _initEditedSummaryFromRequest() {
    final existing = widget.request['expertDiseaseSummary'];
    if (existing is List && existing.isNotEmpty) {
      _editedDiseaseSummary =
          existing.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } else {
      _editedDiseaseSummary = null;
    }
  }

  void _initBaselineSummaryForDiff() {
    final base =
        (widget.request['expertDiseaseSummary'] as List?) ??
        (widget.request['diseaseSummary'] as List?) ??
        const [];
    _lastSavedSummaryForDiff = base.whereType<Map>().map((e) {
      return Map<String, dynamic>.from(e);
    }).toList();
  }

  List<Map<String, dynamic>> _normalizeAndMergeSummary(List<Map<String, dynamic>> input) {
    final Map<String, Map<String, dynamic>> agg = {};
    for (final row in input) {
      final labelRaw =
          (row['label'] ?? row['disease'] ?? row['name'] ?? 'unknown').toString();
      final label = PigDiseaseUI.normalizeKey(labelRaw);
      if (label.isEmpty) continue;
      final avg = (row['avgConfidence'] as num?)?.toDouble() ?? 0.0;
      final mx = (row['maxConfidence'] as num?)?.toDouble() ?? avg;
      final cnt = (row['count'] as num?)?.toInt() ?? 1;

      if (!agg.containsKey(label)) {
        agg[label] = {
          'label': label,
          'name': PigDiseaseUI.displayName(label),
          'avgConfidence': avg,
          'maxConfidence': mx,
          'count': cnt,
        };
      } else {
        final cur = agg[label]!;
        final curCnt = (cur['count'] as num?)?.toInt() ?? 1;
        final totalCnt = curCnt + cnt;
        final curAvg = (cur['avgConfidence'] as num?)?.toDouble() ?? 0.0;
        final newAvg =
            totalCnt == 0 ? 0.0 : ((curAvg * curCnt) + (avg * cnt)) / totalCnt;
        final curMax = (cur['maxConfidence'] as num?)?.toDouble() ?? curAvg;
        cur['avgConfidence'] = newAvg;
        cur['maxConfidence'] = math.max(curMax, mx);
        cur['count'] = totalCnt;
      }
    }

    final out = agg.values.toList();
    out.sort((a, b) {
      final aAvg = (a['avgConfidence'] as num?)?.toDouble() ?? 0.0;
      final bAvg = (b['avgConfidence'] as num?)?.toDouble() ?? 0.0;
      return bAvg.compareTo(aAvg);
    });
    return out;
  }

  String _getCurrentExpertName() {
    try {
      final userBox = Hive.box('userBox');
      final userProfile = userBox.get('userProfile');
      return (userProfile?['fullName'] ?? 'Expert').toString();
    } catch (_) {
      return 'Expert';
    }
  }

  bool _isOwnerExpert() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final review = widget.request['expertReview'];
    final ownerUid = (widget.request['expertUid'] ??
            (review is Map ? review['expertUid'] : null) ??
            widget.request['expertDiseaseSummaryByUid'] ??
            '')
        .toString();
    return ownerUid.isNotEmpty && ownerUid == user.uid;
  }

  Future<void> _saveEditedSummaryToFirestore(List<Map<String, dynamic>> edited) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final docId = widget.request['id'] ?? widget.request['requestId'];
    if (docId == null) return;

    final nowIso = DateTime.now().toIso8601String();
    final expertName = _getCurrentExpertName();
    final merged = _normalizeAndMergeSummary(edited);
    final changeLog = ReportResultChangeLog.build(
      before: _lastSavedSummaryForDiff,
      after: merged,
      byUid: user.uid,
      byName: expertName.toString(),
      source: 'edit_completed',
    );

    await FirebaseFirestore.instance.collection('scan_requests').doc(docId).update({
      'expertDiseaseSummary': merged,
      'expertDiseaseSummaryUpdatedAt': nowIso,
      'expertDiseaseSummaryByUid': user.uid,
      'expertDiseaseSummaryByName': expertName,
      'expertDiseaseSummaryChangeLog': changeLog,
    });
    // Update local snapshot so completed screens show the same remarks immediately.
    widget.request['expertDiseaseSummaryChangeLog'] = changeLog;
    _lastSavedSummaryForDiff = merged.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>?> _showEditSummarySheet(
    BuildContext context,
    List<Map<String, dynamic>> current,
  ) async {
    final List<Map<String, dynamic>> working =
        _normalizeAndMergeSummary(_editedDiseaseSummary ?? current)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    final options = PigDiseaseUI.diseaseColors.keys
        .where((k) => k != 'unknown')
        .toList(growable: false);

    return showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateSheet) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.70,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Edit Report Result',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Add disease',
                              onPressed: () async {
                                final used = working
                                    .map(
                                      (e) => PigDiseaseUI.normalizeKey(
                                        (e['label'] ?? e['disease'] ?? e['name'] ?? '')
                                            .toString(),
                                      ),
                                    )
                                    .where((k) => k.isNotEmpty)
                                    .toSet();
                                final available =
                                    options.where((k) => !used.contains(k)).toList();
                                if (available.isEmpty) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text('All diseases are already listed.'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                  return;
                                }

                                String picked = available.first;
                                final res = await showDialog<String>(
                                  context: ctx,
                                  builder: (dctx) {
                                    return AlertDialog(
                                      title: const Text('Add disease'),
                                      content: StatefulBuilder(
                                        builder: (dctx, setStateInner) {
                                          return DropdownButtonFormField<String>(
                                            value: picked,
                                            isExpanded: true,
                                            items: available
                                                .map(
                                                  (k) => DropdownMenuItem<String>(
                                                    value: k,
                                                    child: Text(PigDiseaseUI.displayName(k)),
                                                  ),
                                                )
                                                .toList(),
                                            onChanged: (v) => setStateInner(() {
                                              picked = v ?? picked;
                                            }),
                                          );
                                        },
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(dctx),
                                          child: const Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(dctx, picked),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: const Text('Add'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                                if (res == null) return;
                                setStateSheet(() {
                                  working.add({
                                    'label': res,
                                    'name': PigDiseaseUI.displayName(res),
                                    // Manual additions have no measured confidence; start at 0.
                                    'avgConfidence': 0.0,
                                    'maxConfidence': 0.0,
                                    'count': 1,
                                  });
                                });
                              },
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(ctx, _normalizeAndMergeSummary(working));
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Apply'),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: working.length,
                          itemBuilder: (ctx, i) {
                            final row = working[i];
                            final label = (row['label'] ?? 'unknown').toString();
                            final key = PigDiseaseUI.normalizeKey(label);
                            final avg = (row['avgConfidence'] as num?)?.toDouble() ?? 0.0;
                            final mx = (row['maxConfidence'] as num?)?.toDouble() ?? avg;
                            final usedOther = working
                                .asMap()
                                .entries
                                .where((e) => e.key != i)
                                .map(
                                  (e) => PigDiseaseUI.normalizeKey(
                                    (e.value['label'] ??
                                            e.value['disease'] ??
                                            e.value['name'] ??
                                            '')
                                        .toString(),
                                  ),
                                )
                                .where((k) => k.isNotEmpty)
                                .toSet();
                            final rowOptions = options
                                .where((k) => k == key || !usedOther.contains(k))
                                .toList(growable: false);
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            value: rowOptions.contains(key)
                                                ? key
                                                : rowOptions.first,
                                            isExpanded: true,
                                            items: rowOptions
                                                .map(
                                                  (k) => DropdownMenuItem<String>(
                                                    value: k,
                                                    child: Text(
                                                      PigDiseaseUI.displayName(k),
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                            onChanged: (v) {
                                              if (v == null) return;
                                              if (usedOther.contains(v)) {
                                                ScaffoldMessenger.of(ctx).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'That disease is already listed.',
                                                    ),
                                                    backgroundColor: Colors.orange,
                                                  ),
                                                );
                                                return;
                                              }
                                              setStateSheet(() {
                                                row['label'] = v;
                                                row['name'] = PigDiseaseUI.displayName(v);
                                              });
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          tooltip: 'Remove disease',
                                          onPressed: () {
                                            setStateSheet(() {
                                              working.removeAt(i);
                                            });
                                          },
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Avg ${(avg * 100).toStringAsFixed(1)}% • Max ${(mx * 100).toStringAsFixed(1)}%',
                                      style: TextStyle(
                                        color: Colors.grey[700],
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
  Future<void> _loadBoundingBoxPreference() async {
    final box = await Hive.openBox('userBox');
    final savedPreference = box.get('expertShowBoundingBoxes');
    if (savedPreference != null) {
      setState(() {
        _showBoundingBoxes = savedPreference as bool;
      });
    }
  }

  Future<void> _saveBoundingBoxPreference(bool value) async {
    final box = await Hive.openBox('userBox');
    await box.put('expertShowBoundingBoxes', value);
  }

  Future<void> _loadDiseaseInfo() async {
    // Removed: disease info load (expert now only agrees/disagrees; no treatment plan).
  }

  bool _isEditing = false;

  // Removed: preventive measures list (no longer used).

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    // Release claim synchronously (fire and forget)
    _releaseReportClaimSync();
    _commentController.dispose();
    super.dispose();
  }

  // Claim the report when expert opens it (only for pending reports)
  Future<void> _claimReportForReview() async {
    // Only claim if this is a pending report
    final status = widget.request['status'];
    if (status != 'pending' && status != 'pending_review') {
      return; // Don't claim completed reports
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userBox = Hive.box('userBox');
    final userProfile = userBox.get('userProfile');
    final expertName = userProfile?['fullName'] ?? 'Expert';

    final docId = widget.request['id'] ?? widget.request['requestId'];
    if (docId == null) return;

    try {
      final docRef = FirebaseFirestore.instance
          .collection('scan_requests')
          .doc(docId);

      // Use transaction to claim the report
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);

        if (!snapshot.exists) return;

        final currentData = snapshot.data()!;
        final currentStatus = currentData['status'];

        // Only claim if it's pending
        if (currentStatus != 'pending' && currentStatus != 'pending_review') {
          return;
        }

        // Check if already claimed by someone else
        final reviewingByUid = currentData['reviewingByUid'];
        final reviewingAt = currentData['reviewingAt'];

        if (reviewingByUid != null && reviewingByUid != user.uid) {
          // Check if the claim has expired (15 minutes)
          if (reviewingAt != null) {
            final claimTime = DateTime.parse(reviewingAt);
            final now = DateTime.now();
            final difference = now.difference(claimTime).inMinutes;

            if (difference < 15) {
              // Still claimed by someone else
              return;
            }
          }
        }

        // Claim the report
        transaction.update(docRef, {
          'reviewingBy': expertName,
          'reviewingByUid': user.uid,
          'reviewingAt': DateTime.now().toIso8601String(),
        });
      });

      // Start heartbeat to keep the claim alive
      _startHeartbeat();
    } catch (e) {
      print('Error claiming report: $e');
    }
  }

  // Release the claim when expert leaves (synchronous for dispose)
  void _releaseReportClaimSync() {
    // Only release if this was a pending report
    final status = widget.request['status'];
    if (status != 'pending' && status != 'pending_review') {
      return; // Don't try to release if it wasn't claimed
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final docId = widget.request['id'] ?? widget.request['requestId'];
    if (docId == null) return;

    // Use unawaited to ensure this fires even as page is closing
    FirebaseFirestore.instance
        .collection('scan_requests')
        .doc(docId)
        .update({
          'reviewingBy': FieldValue.delete(),
          'reviewingByUid': FieldValue.delete(),
          'reviewingAt': FieldValue.delete(),
        })
        .then((_) {
          print('✅ Released claim for report: $docId');
        })
        .catchError((error) {
          print('❌ Error releasing claim: $error');
        });
  }

  // Update heartbeat every 5 minutes to keep claim alive
  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        timer.cancel();
        return;
      }

      final docId = widget.request['id'] ?? widget.request['requestId'];
      if (docId == null) {
        timer.cancel();
        return;
      }

      FirebaseFirestore.instance
          .collection('scan_requests')
          .doc(docId)
          .update({'reviewingAt': DateTime.now().toIso8601String()})
          .catchError((error) {
            timer.cancel();
          });
    });
  }

  void _submitReview() async {
    setState(() {
      _isSubmitting = true;
    });

    // Get current expert's UID and name
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isSubmitting = false);
      return;
    }

    final userBox = Hive.box('userBox');
    final userProfile = userBox.get('userProfile');
    final expertName = userProfile?['fullName'] ?? 'Expert';

    final expertReview = {
      // New simplified expert review:
      // Expert only agrees/disagrees + optional comment.
      'comment': _commentController.text.trim(),
      'decision': _selectedDecision,
      'expertName': expertName,
      'expertUid': user.uid,
    };

    try {
      final docId = widget.request['id'] ?? widget.request['requestId'];

      // Cancel heartbeat timer before submitting
      _heartbeatTimer?.cancel();

      final isDisagree = _selectedDecision == 'disagree';

      // If DISAGREE: keep the report open for other experts and create a discussion thread.
      // If AGREE: complete normally.
      final nowIso = DateTime.now().toIso8601String();

      final requestUpdate = <String, dynamic>{
        'status': isDisagree ? 'pending_review' : 'completed',
        'expertReview': expertReview,
        'reviewedAt': nowIso,
        if (_editedDiseaseSummary != null)
          'expertDiseaseSummary': _normalizeAndMergeSummary(_editedDiseaseSummary!),
        if (_editedDiseaseSummary != null) 'expertDiseaseSummaryUpdatedAt': nowIso,
        if (_editedDiseaseSummary != null) 'expertDiseaseSummaryByUid': user.uid,
        if (_editedDiseaseSummary != null) 'expertDiseaseSummaryByName': expertName,
        if (_editedDiseaseSummary != null)
          'expertDiseaseSummaryChangeLog': ReportResultChangeLog.build(
            before: _lastSavedSummaryForDiff,
            after: _normalizeAndMergeSummary(_editedDiseaseSummary!),
            byUid: user.uid,
            byName: expertName.toString(),
            source: isDisagree ? 'expert_review_to_discussion' : 'expert_review',
          ),
        // Only set "final" expert fields on AGREE
        if (!isDisagree) 'expertName': expertName,
        if (!isDisagree) 'expertUid': user.uid,
        // If disagree: keep unassigned so other experts can pick it up + notifications show for everyone
        if (isDisagree) 'expertName': FieldValue.delete(),
        if (isDisagree) 'expertUid': FieldValue.delete(),
        'reviewingBy': FieldValue.delete(),
        'reviewingByUid': FieldValue.delete(),
        'reviewingAt': FieldValue.delete(),
      };

      await FirebaseFirestore.instance.collection('scan_requests').doc(docId).update(requestUpdate);

      if (isDisagree) {
        // Create / update expert discussion for this report
        final req = widget.request;
        final userName = (req['userName'] ?? 'Farmer').toString();
        final summary =
            (_editedDiseaseSummary ??
                (req['expertDiseaseSummary'] as List?) ??
                (req['diseaseSummary'] as List?) ??
                const [])
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
        // Keep title consistent across screens: prefer non-healthy if present.
        final diseaseLabel = PigDiseaseUI.dominantLabelFromSummary(
          summary,
          preferNonHealthy: true,
        );

        final discRef = FirebaseFirestore.instance.collection('expert_discussions').doc(docId);
        final batch = FirebaseFirestore.instance.batch();
        batch.set(discRef, {
          'requestId': docId,
          'createdAt': FieldValue.serverTimestamp(),
          'createdByUid': user.uid,
          'createdByName': expertName,
          'status': 'open',
          'userName': userName,
          'diseaseLabel': diseaseLabel,
          'lastMessageText': expertReview['comment'].toString().isEmpty
              ? 'Disagreed — needs expert discussion.'
              : expertReview['comment'],
          'lastMessageAt': FieldValue.serverTimestamp(),
          'decisions': {user.uid: 'disagree'},
          // Track participants so other experts can see who is involved.
          'participantUids': FieldValue.arrayUnion([user.uid]),
          'participants': {user.uid: expertName},
        }, SetOptions(merge: true));
        batch.set(discRef.collection('messages').doc(), {
          'text': expertReview['comment'].toString().isEmpty
              ? 'Disagreed — needs expert discussion.'
              : expertReview['comment'],
          'senderUid': user.uid,
          'senderName': expertName,
          'sentAt': FieldValue.serverTimestamp(),
          'type': 'system',
        });
        await batch.commit();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isDisagree
                  ? 'Disagreed — sent to Discussion (Chatbox) for collaboration.'
                  : 'Review submitted successfully.',
            ),
            backgroundColor: isDisagree ? Colors.orange : Colors.green,
          ),
        );
        Navigator.pop(context, {
          ...widget.request,
          'status': _selectedDecision == 'disagree' ? 'pending_review' : 'completed',
          'expertReview': expertReview,
          'reviewedAt': DateTime.now().toIso8601String(),
          if (_editedDiseaseSummary != null)
            'expertDiseaseSummary': _normalizeAndMergeSummary(_editedDiseaseSummary!),
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit review: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted)
        setState(() {
          _isSubmitting = false;
        });
    }
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      // Initialize form with existing review data
      final review = widget.request['expertReview'];
      if (review != null) {
        _selectedDecision = (review['decision'] ?? '').toString();
        _commentController.text = (review['comment'] ?? '').toString();
      }
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      // Reset form to original values
      final review = widget.request['expertReview'];
      if (review != null) {
        _selectedDecision = (review['decision'] ?? '').toString();
        _commentController.text = (review['comment'] ?? '').toString();
      }
    });
  }

  // Expert-only decision (agree/disagree)
  String _selectedDecision = 'agree';

  Widget _buildImageGrid() {
    final images = widget.request['images'] as List<dynamic>;
    return Column(
      children: [
        // Toggle button for bounding boxes
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text('Show Bounding Boxes'),
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
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: images.length,
          itemBuilder: (context, index) {
            final image = images[index];
            final imageUrl = image['imageUrl'];
            final imagePath = image['path'];
            final detections =
                (image['results'] as List<dynamic>?)
                    ?.where(
                      (d) =>
                          d != null &&
                          d['disease'] != null &&
                          d['confidence'] != null,
                    )
                    .toList() ??
                [];

            print('🔍 Raw results: ${image['results']}');
            print('✅ Filtered detections: $detections');
            print('📊 Total detections for image $index: ${detections.length}');
            print('🖼️ Image URL: $imageUrl, Image Path: $imagePath');

            return GestureDetector(
              onTap: () {
                _openImageViewer(index);
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildImageWidget(
                      imageUrl ?? imagePath,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (_showBoundingBoxes && detections.isNotEmpty)
                    Builder(
                      builder: (context) {
                        // Try to get stored image dimensions for fast loading
                        final storedImageWidth = image['imageWidth'] as num?;
                        final storedImageHeight = image['imageHeight'] as num?;

                        if (storedImageWidth != null &&
                            storedImageHeight != null) {
                          // Use stored dimensions for instant loading
                          final imageSize = Size(
                            storedImageWidth.toDouble(),
                            storedImageHeight.toDouble(),
                          );
                          print(
                            '🔍 Expert Grid Fast mode: Using stored dimensions ${imageSize.width}x${imageSize.height}',
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
                                      : widgetW / imgW; // Width constrained

                              final scaledW = imgW * scale;
                              final scaledH = imgH * scale;
                              final dx = (widgetW - scaledW) / 2;
                              final dy = (widgetH - scaledH) / 2;

                              return CustomPaint(
                                painter: DetectionPainter(
                                  results:
                                      detections
                                          .where(
                                            (d) => d['boundingBox'] != null,
                                          )
                                          .map(
                                            (d) => DetectionResult(
                                              label: d['disease'],
                                              confidence: d['confidence'],
                                              boundingBox: Rect.fromLTRB(
                                                d['boundingBox']['left'],
                                                d['boundingBox']['top'],
                                                d['boundingBox']['right'],
                                                d['boundingBox']['bottom'],
                                              ),
                                            ),
                                          )
                                          .toList(),
                                  originalImageSize: imageSize,
                                  displayedImageSize: Size(scaledW, scaledH),
                                  displayedImageOffset: Offset(dx, dy),
                                ),
                                size: Size(widgetW, widgetH),
                              );
                            },
                          );
                        } else {
                          // Fallback to slow method for old data
                          return FutureBuilder<Size>(
                            future: _getImageSize(
                              imageUrl != null && imageUrl.isNotEmpty
                                  ? NetworkImage(imageUrl)
                                  : FileImage(File(imagePath)),
                            ),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                print(
                                  '🔍 Expert Grid: No image size data, hiding bounding boxes',
                                );
                                return const SizedBox.shrink();
                              }
                              final imageSize = snapshot.data!;
                              print(
                                '🔍 Expert Grid Slow mode: Image size loaded from network ${imageSize.width}x${imageSize.height}',
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
                                          : widgetW / imgW; // Width constrained

                                  final scaledW = imgW * scale;
                                  final scaledH = imgH * scale;
                                  final dx = (widgetW - scaledW) / 2;
                                  final dy = (widgetH - scaledH) / 2;

                                  return CustomPaint(
                                    painter: DetectionPainter(
                                      results:
                                          detections
                                              .where(
                                                (d) => d['boundingBox'] != null,
                                              )
                                              .map(
                                                (d) => DetectionResult(
                                                  label: d['disease'],
                                                  confidence: d['confidence'],
                                                  boundingBox: Rect.fromLTRB(
                                                    d['boundingBox']['left'],
                                                    d['boundingBox']['top'],
                                                    d['boundingBox']['right'],
                                                    d['boundingBox']['bottom'],
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                      originalImageSize: imageSize,
                                      displayedImageSize: Size(
                                        scaledW,
                                        scaledH,
                                      ),
                                      displayedImageOffset: Offset(dx, dy),
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
                        // No count UI for experts (requested).
                        '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
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
    );
  }

  void _openImageViewer(int initialIndex) {
    final images = widget.request['images'] as List<dynamic>;
    int currentIndex = initialIndex;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final image = images[currentIndex];
            final imageUrl = image['imageUrl'];
            final imagePath = image['path'];
            final detections =
                (image['results'] as List<dynamic>?)
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
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // Image
                      _buildImageWidget(
                        imageUrl ?? imagePath,
                        fit: BoxFit.contain,
                      ),
                      // Bounding boxes overlay
                      if (_showBoundingBoxes && detections.isNotEmpty)
                        Builder(
                          builder: (context) {
                            final storedImageWidth =
                                image['imageWidth'] as num?;
                            final storedImageHeight =
                                image['imageHeight'] as num?;

                            final widgetW = constraints.maxWidth;
                            final widgetH = constraints.maxHeight;

                            if (storedImageWidth != null &&
                                storedImageHeight != null) {
                              final originalSize = Size(
                                storedImageWidth.toDouble(),
                                storedImageHeight.toDouble(),
                              );
                              // BoxFit.contain scale
                              final scale = math.min(
                                widgetW / originalSize.width,
                                widgetH / originalSize.height,
                              );
                              final scaledW = originalSize.width * scale;
                              final scaledH = originalSize.height * scale;
                              final dx = (widgetW - scaledW) / 2;
                              final dy = (widgetH - scaledH) / 2;

                              return CustomPaint(
                                painter: DetectionPainter(
                                  results:
                                      detections
                                          .where((d) => d['boundingBox'] != null)
                                          .map(
                                            (d) => DetectionResult(
                                              label: d['disease'],
                                              confidence: d['confidence'],
                                              boundingBox: Rect.fromLTRB(
                                                d['boundingBox']['left'],
                                                d['boundingBox']['top'],
                                                d['boundingBox']['right'],
                                                d['boundingBox']['bottom'],
                                              ),
                                            ),
                                          )
                                          .toList(),
                                  originalImageSize: originalSize,
                                  displayedImageSize: Size(scaledW, scaledH),
                                  displayedImageOffset: Offset(dx, dy),
                                ),
                                size: Size(widgetW, widgetH),
                              );
                            } else {
                              return FutureBuilder<Size>(
                                future: _getImageSize(
                                  imageUrl != null && imageUrl.isNotEmpty
                                      ? NetworkImage(imageUrl)
                                      : FileImage(File(imagePath)),
                                ),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData) {
                                    return const SizedBox.shrink();
                                  }
                                  final originalSize = snapshot.data!;
                                  // BoxFit.contain scale
                                  final scale = math.min(
                                    widgetW / originalSize.width,
                                    widgetH / originalSize.height,
                                  );
                                  final scaledW = originalSize.width * scale;
                                  final scaledH = originalSize.height * scale;
                                  final dx = (widgetW - scaledW) / 2;
                                  final dy = (widgetH - scaledH) / 2;

                                  return CustomPaint(
                                    painter: DetectionPainter(
                                      results:
                                          detections
                                              .where((d) => d['boundingBox'] != null)
                                              .map(
                                                (d) => DetectionResult(
                                                  label: d['disease'],
                                                  confidence: d['confidence'],
                                                  boundingBox: Rect.fromLTRB(
                                                    d['boundingBox']['left'],
                                                    d['boundingBox']['top'],
                                                    d['boundingBox']['right'],
                                                    d['boundingBox']['bottom'],
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                      originalImageSize: originalSize,
                                      displayedImageSize: Size(
                                        scaledW,
                                        scaledH,
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
                      // Close button
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      // Previous button
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
                      // Next button
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
                      // Index indicator
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

  Widget _buildImageWidget(dynamic path, {BoxFit fit = BoxFit.cover}) {
    if (path is String && path.isNotEmpty) {
      if (path.startsWith('http')) {
        // Supabase public URL
        return CachedNetworkImage(
          imageUrl: path,
          fit: fit,
          placeholder:
              (context, url) =>
                  const Center(child: CircularProgressIndicator()),
          errorWidget: (context, url, error) {
            return Container(
              color: Colors.grey[200],
              child: const Icon(Icons.image_not_supported),
            );
          },
        );
      } else if (path.startsWith('/') || path.contains(':')) {
        // File path
        return Image.file(
          File(path),
          fit: fit,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[200],
              child: const Icon(Icons.image_not_supported),
            );
          },
        );
      } else {
        // Asset path
        return Image.asset(
          path,
          fit: fit,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[200],
              child: const Icon(Icons.image_not_supported),
            );
          },
        );
      }
    } else {
      // Null or not a string
      return Container(
        color: Colors.grey[200],
        child: const Icon(Icons.image_not_supported),
      );
    }
  }

  /// Returns per-disease avg/max confidence for this report.
  /// Prefers request.expertDiseaseSummary when present, else request.diseaseSummary;
  /// falls back to image detections.
  List<Map<String, dynamic>> _getDiseaseConfidenceSummary() {
    final rawSummary =
        (widget.request['expertDiseaseSummary'] as List<dynamic>?) ??
        (widget.request['diseaseSummary'] as List<dynamic>?) ??
        const [];

    final fromSummary = <Map<String, dynamic>>[];
    for (final e in rawSummary) {
      if (e is! Map) continue;
      final avg = (e['avgConfidence'] as num?)?.toDouble();
      if (avg == null) continue;
      final mx = (e['maxConfidence'] as num?)?.toDouble() ?? avg;
      final label = (e['label'] ?? e['disease'] ?? e['name'] ?? 'unknown').toString();
      fromSummary.add({'label': label, 'avgConfidence': avg, 'maxConfidence': mx});
    }
    if (fromSummary.isNotEmpty) return fromSummary;

    final images = widget.request['images'] as List<dynamic>? ?? const [];
    final Map<String, double> sum = {};
    final Map<String, int> n = {};
    final Map<String, double> max = {};
    for (final img in images) {
      if (img is! Map) continue;
      final results = img['results'] as List<dynamic>? ?? const [];
      for (final r in results) {
        if (r is! Map) continue;
        final rawLabel = (r['disease'] ?? r['label'] ?? 'unknown').toString();
        final conf = (r['confidence'] as num?)?.toDouble();
        if (conf == null) continue;
        final key = PigDiseaseUI.normalizeKey(rawLabel);
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
      out.add({'label': key, 'avgConfidence': avg, 'maxConfidence': max[key] ?? avg});
    }
    return out;
  }

  Widget _buildDiseaseSummary() {
    final stats = _getDiseaseConfidenceSummary();
    final status = (widget.request['status'] ?? '').toString();
    final isCompleted = status == 'reviewed' || status == 'completed';
    final canEditAfterCompletion = _isOwnerExpert();
    final sortedDiseases = stats.toList()
      ..sort((a, b) {
        final aAvg = (a['avgConfidence'] as num?)?.toDouble() ?? 0.0;
        final bAvg = (b['avgConfidence'] as num?)?.toDouble() ?? 0.0;
        return bAvg.compareTo(aAvg);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Report Results',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            if (!isCompleted || canEditAfterCompletion)
              OutlinedButton.icon(
                onPressed: () async {
                  final edited = await _showEditSummarySheet(context, stats);
                  if (edited == null) return;
                  setState(() {
                    _editedDiseaseSummary = edited;
                    widget.request['expertDiseaseSummary'] = edited;
                  });

                  // If already completed, save immediately (owner expert only).
                  if (isCompleted) {
                    try {
                      await _saveEditedSummaryToFirestore(edited);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Results updated successfully'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to update results: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Edit'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          isCompleted
              ? (canEditAfterCompletion
                  ? 'Editing results updates what the farmer sees. It does not change AI bounding boxes.'
                  : 'Only the reviewing expert can edit results for completed reports.')
              : 'Editing results changes what the farmer will see after you submit. It does not change AI bounding boxes.',
          style: TextStyle(color: Colors.grey[700], fontSize: 12),
        ),
        if (isCompleted && widget.request['expertDiseaseSummaryChangeLog'] != null) ...[
          const SizedBox(height: 10),
          Builder(
            builder: (context) {
              final log = widget.request['expertDiseaseSummaryChangeLog'];
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
        ],
        const SizedBox(height: 16),
        // Compact table view (avg confidence only; no counts)
        Card(
          child: Column(
            children: [
              // Table header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Disease',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        'Avg %',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        'Max %',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              // Table rows
              ...sortedDiseases.map((disease) {
                final rawLabel = (disease['label'] ?? 'unknown').toString();
                final isUnknown = _isUnknownDetection(rawLabel);
                final diseaseName = isUnknown ? 'Unknown' : _formatExpertLabel(rawLabel);
                final color = _getDiseaseColor(rawLabel);
                final avg = (disease['avgConfidence'] as num?)?.toDouble();
                final mx = (disease['maxConfidence'] as num?)?.toDouble();
                final avgPct = (avg ?? 0.0) * 100;
                final maxPct = (mx ?? avg ?? 0.0) * 100;

                return Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[200]!),
                    ),
                  ),
                  child: InkWell(
                    onTap: null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    diseaseName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              '${avgPct.toStringAsFixed(1)}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              '${maxPct.toStringAsFixed(1)}%',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
        ),
        // Removed: count-based summary stats for experts (requested)
      ],
    );
  }

  // Removed: _showHealthyStatus (expert flow no longer reviews "healthy" stats)

  // Removed: _showDetectionDetails (expert flow no longer drills into counts)

  // Removed: _buildDetectionStatCard (no longer used in simplified expert flow)

  Widget _buildReviewForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Expert Review', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        // Decision + optional comment only
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Decision',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting
                            ? null
                            : () => setState(() => _selectedDecision = 'agree'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _selectedDecision == 'agree' ? Colors.green : Colors.grey[200],
                          foregroundColor:
                              _selectedDecision == 'agree' ? Colors.white : Colors.black87,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Agree'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting
                            ? null
                            : () => setState(() => _selectedDecision = 'disagree'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _selectedDecision == 'disagree' ? Colors.red : Colors.grey[200],
                          foregroundColor:
                              _selectedDecision == 'disagree' ? Colors.white : Colors.black87,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Disagree'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Comment (optional)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Add a short note for the farmer (optional)...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Submit Button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submitReview,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child:
                _isSubmitting
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                    : const Text(
                      'Submit Decision',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedReview() {
    final review = widget.request['expertReview'];
    if (review == null) {
      return const Center(child: Text('No review data available'));
    }

    if (_isEditing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Edit Expert Review',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: _cancelEditing,
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildReviewForm(),
        ],
      );
    }

    final decision = (review['decision'] ?? '').toString();
    final comment = (review['comment'] ?? '').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Expert Review',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: _startEditing,
              icon: const Icon(Icons.edit),
              label: const Text('Edit Review'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Decision',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      decision == 'disagree' ? Icons.cancel_outlined : Icons.check_circle_outline,
                      color: decision == 'disagree' ? Colors.red : Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      decision == 'disagree' ? 'Disagree' : 'Agree',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: decision == 'disagree' ? Colors.red : Colors.green,
                      ),
                    ),
                  ],
                ),
                if (comment.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Comment',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    comment,
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool _isUnknownDetection(String diseaseName) {
    final lowerName = diseaseName.toLowerCase();
    return lowerName == 'tip_burn' ||
        lowerName == 'tip burn' ||
        lowerName == 'unknown' ||
        lowerName.contains('unknown') ||
        lowerName.contains('tip_burn') ||
        lowerName.contains('tip burn');
  }

  Color _getDiseaseColor(String diseaseName) => PigDiseaseUI.colorFor(diseaseName);

  // Removed: _getSeverityColor (no severity in simplified expert flow)

  // Removed: _buildStatCard (count UI not needed for experts)

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

  @override
  Widget build(BuildContext context) {
    final userName = widget.request['userName']?.toString() ?? 'Asif';
    final submittedAt = widget.request['submittedAt']?.toString() ?? '';
    final reviewedAt = widget.request['reviewedAt']?.toString() ?? '';

    // Format dates for better readability
    final formattedSubmittedDate =
        submittedAt.isNotEmpty && DateTime.tryParse(submittedAt) != null
            ? DateFormat(
              'MMM d, yyyy – h:mma',
            ).format(DateTime.parse(submittedAt))
            : submittedAt;
    final formattedReviewedDate =
        reviewedAt.isNotEmpty && DateTime.tryParse(reviewedAt) != null
            ? DateFormat(
              'MMM d, yyyy – h:mma',
            ).format(DateTime.parse(reviewedAt))
            : reviewedAt;

    final isCompleted =
        widget.request['status']?.toString() == 'reviewed' ||
        widget.request['status']?.toString() == 'completed';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: const Text(
          'Analysis Review',
          style: TextStyle(color: Colors.white),
        ),
        elevation: 0,
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
                              userName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.green,
                              ),
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
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
                          const Text(
                            'Submitted:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            formattedSubmittedDate.isNotEmpty
                                ? formattedSubmittedDate
                                : '-',
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
                            const Text(
                              'Reviewed:',
                              style: TextStyle(
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
            // Analyzed Images
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Analyzed Images',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildImageGrid(),
                ],
              ),
            ),
            // Disease Summary
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildDiseaseSummary(),
            ),
            // Review Section
            Padding(
              padding: const EdgeInsets.all(16),
              child:
                  widget.request['status']?.toString() == 'pending'
                      ? _buildReviewForm()
                      : _buildCompletedReview(),
            ),
          ],
        ),
      ),
    );
  }

  String _formatExpertLabel(String label) => PigDiseaseUI.displayName(label);
}
