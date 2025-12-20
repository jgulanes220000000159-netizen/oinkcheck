import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';

import '../shared/pig_disease_ui.dart';
import '../user/detection_painter.dart';
import '../user/tflite_detector.dart';

class ExpertChatThreadPage extends StatefulWidget {
  const ExpertChatThreadPage({
    super.key,
    required this.discussionId,
    required this.requestId,
    required this.myName,
  });

  final String discussionId;
  final String requestId;
  final String myName;

  @override
  State<ExpertChatThreadPage> createState() => _ExpertChatThreadPageState();
}

class _ExpertChatThreadPageState extends State<ExpertChatThreadPage> {
  final _messageCtrl = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  bool _sending = false;

  bool _showBoxes = true;

  DocumentReference<Map<String, dynamic>> get _discRef =>
      FirebaseFirestore.instance.collection('expert_discussions').doc(
            widget.discussionId,
          );

  CollectionReference<Map<String, dynamic>> get _msgRef =>
      _discRef.collection('messages');

  DocumentReference<Map<String, dynamic>> get _reqRef =>
      FirebaseFirestore.instance.collection('scan_requests').doc(widget.requestId);

  @override
  void initState() {
    super.initState();
    _maybeFixDiscussionDiseaseLabel();
    _ensureParticipantPresence();
  }

  Future<void> _ensureParticipantPresence() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      await _discRef.set({
        'participantUids': FieldValue.arrayUnion([uid]),
        'participants.$uid': widget.myName,
        'lastSeenAt.$uid': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Best-effort; ignore.
    }
  }

  Future<void> _maybeFixDiscussionDiseaseLabel() async {
    try {
      final discSnap = await _discRef.get();
      final disc = discSnap.data() ?? <String, dynamic>{};
      final stored = (disc['diseaseLabel'] ?? '').toString();
      final storedKey = PigDiseaseUI.normalizeKey(stored);
      final needsFix = storedKey.isEmpty || storedKey == 'unknown' || storedKey == 'healthy';
      if (!needsFix) return;

      final reqSnap = await _reqRef.get();
      final req = reqSnap.data() ?? <String, dynamic>{};
      final summary = (req['diseaseSummary'] as List?) ?? const [];
      final fixed = PigDiseaseUI.dominantLabelFromSummary(
        summary,
        preferNonHealthy: true,
      );
      if (fixed.trim().isEmpty) return;
      if (PigDiseaseUI.normalizeKey(fixed) == storedKey && stored.isNotEmpty) return;

      await _discRef.set({'diseaseLabel': fixed}, SetOptions(merge: true));
    } catch (_) {
      // Best-effort; ignore.
    }
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  bool _isFilePath(String path) => path.startsWith('/') || path.contains(':');

  Widget _buildImageWidget(String path, {BoxFit fit = BoxFit.cover}) {
    if (path.isEmpty) {
      return Container(
        color: Colors.grey[200],
        child: const Icon(Icons.broken_image, color: Colors.grey),
      );
    }
    if (path.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: path,
        fit: fit,
        placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
        errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
      );
    }
    if (_isFilePath(path)) {
      final file = File(path);
      if (!file.existsSync()) {
        return const Icon(Icons.broken_image, color: Colors.grey);
      }
      return Image.file(file, fit: fit);
    }
    return Image.asset(path, fit: fit);
  }

  Widget _buildImageTile(Map<String, dynamic> image, int index) {
    final imageUrl = (image['imageUrl'] ?? '').toString();
    final imagePath = (image['path'] ?? image['imagePath'] ?? '').toString();
    final displayPath = imageUrl.isNotEmpty ? imageUrl : imagePath;

    final detections =
        (image['results'] as List?)
            ?.where(
              (d) =>
                  d != null &&
                  d['disease'] != null &&
                  d['confidence'] != null &&
                  d['boundingBox'] != null,
            )
            .toList() ??
        const [];

    return GestureDetector(
      onTap: () {
        _openImageViewer(index);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildImageWidget(displayPath, fit: BoxFit.cover),
            if (_showBoxes && detections.isNotEmpty)
              LayoutBuilder(
                builder: (context, constraints) {
                  final storedW = image['imageWidth'] as num?;
                  final storedH = image['imageHeight'] as num?;
                  if (storedW == null || storedH == null) {
                    return const SizedBox.shrink();
                  }
                  final imageSize = Size(storedW.toDouble(), storedH.toDouble());
                  final imgW = imageSize.width;
                  final imgH = imageSize.height;
                  final widgetW = constraints.maxWidth;
                  final widgetH = constraints.maxHeight;

                  // BoxFit.cover mapping
                  final scale =
                      imgW / imgH > widgetW / widgetH ? widgetH / imgH : widgetW / imgW;
                  final scaledW = imgW * scale;
                  final scaledH = imgH * scale;
                  final dx = (widgetW - scaledW) / 2;
                  final dy = (widgetH - scaledH) / 2;

                  return CustomPaint(
                    painter: DetectionPainter(
                      results:
                          detections
                              .map((d) {
                                final bb = d['boundingBox'];
                                return DetectionResult(
                                  label: d['disease'],
                                  confidence: d['confidence'],
                                  boundingBox: Rect.fromLTRB(
                                    (bb['left'] as num).toDouble(),
                                    (bb['top'] as num).toDouble(),
                                    (bb['right'] as num).toDouble(),
                                    (bb['bottom'] as num).toDouble(),
                                  ),
                                );
                              })
                              .toList(),
                      originalImageSize: imageSize,
                      displayedImageSize: Size(scaledW, scaledH),
                      displayedImageOffset: Offset(dx, dy),
                    ),
                    size: Size(widgetW, widgetH),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _openImageViewer(int initialIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (context) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _reqRef.snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data() ?? <String, dynamic>{};
            final images = (data['images'] as List?) ?? const [];
            if (images.isEmpty) {
              return const Dialog(child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No images found.'),
              ));
            }
            int currentIndex = initialIndex.clamp(0, images.length - 1);
            return StatefulBuilder(
              builder: (context, setStateDialog) {
                final imgMap = images[currentIndex] as Map;
                final img = Map<String, dynamic>.from(imgMap);
                final imageUrl = (img['imageUrl'] ?? '').toString();
                final imagePath = (img['path'] ?? img['imagePath'] ?? '').toString();
                final displayPath = imageUrl.isNotEmpty ? imageUrl : imagePath;

                return Dialog(
                  backgroundColor: Colors.black,
                  insetPadding: const EdgeInsets.all(12),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: InteractiveViewer(
                          child: _buildImageWidget(displayPath, fit: BoxFit.contain),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ),
                      Positioned(
                        bottom: 10,
                        left: 10,
                        right: 10,
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: currentIndex <= 0
                                  ? null
                                  : () => setStateDialog(() => currentIndex--),
                              icon: const Icon(Icons.chevron_left, color: Colors.white),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  'Image ${currentIndex + 1} / ${images.length}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: currentIndex >= images.length - 1
                                  ? null
                                  : () => setStateDialog(() => currentIndex++),
                              icon: const Icon(Icons.chevron_right, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  List<Map<String, dynamic>> _getDiseaseStats(Map<String, dynamic> req) {
    final summary = (req['diseaseSummary'] as List?) ?? const [];
    final out = <Map<String, dynamic>>[];
    for (final e in summary) {
      if (e is! Map) continue;
      final avg = (e['avgConfidence'] as num?)?.toDouble();
      if (avg == null) continue;
      final mx = (e['maxConfidence'] as num?)?.toDouble() ?? avg;
      final label = (e['label'] ?? e['disease'] ?? e['name'] ?? 'unknown').toString();
      out.add({'label': label, 'avg': avg, 'max': mx});
    }
    out.sort((a, b) => (b['avg'] as double).compareTo(a['avg'] as double));
    return out;
  }

  Future<void> _sendMessage() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _sending = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final msgDoc = _msgRef.doc();
      batch.set(msgDoc, {
        'text': text,
        'senderUid': uid,
        'senderName': widget.myName,
        'sentAt': FieldValue.serverTimestamp(),
        'type': 'comment',
      });
      batch.set(_discRef, {
        'lastMessageText': text,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'participantUids': FieldValue.arrayUnion([uid]),
        'participants.$uid': widget.myName,
        'lastSeenAt.$uid': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
      _messageCtrl.clear();
      // Best-effort: scroll to bottom after sending
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_chatScrollController.hasClients) return;
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _resolveDiscussion({
    required String decision,
    required String createdByUid,
    String comment = '',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (uid != createdByUid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the expert who started this discussion can resolve it.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final batch = FirebaseFirestore.instance.batch();

    final reqRef = FirebaseFirestore.instance
        .collection('scan_requests')
        .doc(widget.requestId);

    // Treat "agree" as a normal completion, and "disagree" as a reviewed (resolved) report.
    final nextStatus = decision == 'agree' ? 'completed' : 'reviewed';
    final nowIso = DateTime.now().toIso8601String();

    batch.update(reqRef, {
      'status': nextStatus,
      'reviewedAt': nowIso,
      'expertName': widget.myName,
      'expertUid': uid,
      'expertReview': {
        'decision': decision,
        'comment': comment.trim(),
        'expertName': widget.myName,
        'expertUid': uid,
        'resolvedFromDiscussion': true,
        'discussionId': widget.discussionId,
      },
      'reviewingBy': FieldValue.delete(),
      'reviewingByUid': FieldValue.delete(),
      'reviewingAt': FieldValue.delete(),
    });

    batch.set(_discRef, {
      'status': 'closed',
      'resolvedDecision': decision,
      'resolvedComment': comment.trim(),
      'closedAt': FieldValue.serverTimestamp(),
      'closedByUid': uid,
      'closedByName': widget.myName,
      'lastMessageText': decision == 'agree'
          ? 'Resolved by ${widget.myName}: AGREED (report completed).'
          : 'Resolved by ${widget.myName}: DISAGREED (report reviewed).',
      'lastMessageAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(_msgRef.doc(), {
      'text': decision == 'agree'
          ? '✅ Resolved by ${widget.myName}: AGREED (report completed).'
          : '✅ Resolved by ${widget.myName}: DISAGREED (report reviewed).',
      'senderUid': uid,
      'senderName': widget.myName,
      'sentAt': FieldValue.serverTimestamp(),
      'type': 'system',
    });

    await batch.commit();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          decision == 'agree'
              ? 'Resolved: agreed and marked as completed.'
              : 'Resolved: disagreed and marked as reviewed.',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _showResolveDialog({
    required String createdByUid,
    required String createdByName,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid != createdByUid) return;

    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Resolve report'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Only $createdByName can resolve this report.',
                style: TextStyle(color: Colors.grey[700], fontSize: 12),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Optional resolution comment',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'disagree'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Resolve as Disagree'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, 'agree'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Resolve as Agree'),
            ),
          ],
        );
      },
    );
    final comment = ctrl.text.trim();
    ctrl.dispose();
    if (res == null) return;

    await _resolveDiscussion(
      decision: res,
      createdByUid: createdByUid,
      comment: comment,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return Scaffold(
      backgroundColor: Colors.grey[50],
      // Let Scaffold handle keyboard insets; avoid double-padding (prevents RenderFlex overflow)
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        title: const Text('Discussion'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _msgRef.orderBy('sentAt').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? const [];

                // Auto-scroll to bottom when new messages arrive
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!_chatScrollController.hasClients) return;
                  if (!_chatScrollController.position.hasContentDimensions) return;
                  _chatScrollController.jumpTo(
                    _chatScrollController.position.maxScrollExtent,
                  );
                });

                return CustomScrollView(
                  controller: _chatScrollController,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverToBoxAdapter(
                      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: _discRef.snapshots(),
                        builder: (context, snap) {
                          final data = snap.data?.data() ?? <String, dynamic>{};
                          final diseaseLabel =
                              (data['diseaseLabel'] ?? 'unknown').toString();
                          final diseaseName = PigDiseaseUI.displayName(diseaseLabel);
                          final userName = (data['userName'] ?? 'Farmer').toString();
                          final status = (data['status'] ?? 'open').toString();
                          final color = PigDiseaseUI.colorFor(diseaseLabel);
                          final requestIdShort = widget.requestId.length > 10
                              ? widget.requestId.substring(0, 10)
                              : widget.requestId;

                          final createdByUid = (data['createdByUid'] ?? '').toString();
                          final createdByName =
                              (data['createdByName'] ?? 'Expert').toString();
                          final meUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                          final isOwner = createdByUid.isNotEmpty && meUid == createdByUid;

                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.forum, color: color),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            diseaseName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Discussing report: $userName • ID $requestIdShort…',
                                            style: TextStyle(
                                              color: Colors.grey[700],
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: status == 'closed'
                                            ? Colors.grey.withOpacity(0.12)
                                            : Colors.orange.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        status == 'closed' ? 'CLOSED' : 'OPEN',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: status == 'closed'
                                              ? Colors.grey[700]
                                              : Colors.orange[800],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                // Participants UI removed (per request)
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Owner: $createdByName',
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (status != 'closed' && isOwner)
                                      ElevatedButton.icon(
                                        onPressed: () => _showResolveDialog(
                                          createdByUid: createdByUid,
                                          createdByName: createdByName,
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                        ),
                                        icon: const Icon(Icons.check_circle_outline),
                                        label: const Text('Resolve'),
                                      ),
                                  ],
                                ),

                                if (status != 'closed' && !isOwner) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.blueGrey.withOpacity(0.20),
                                      ),
                                    ),
                                    child: Text(
                                      'This is a discussion thread. Share your input in chat — only $createdByName can resolve the report.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blueGrey[800],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    // Report details (what Expert #2 needs to see)
                    SliverToBoxAdapter(
                      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: _reqRef.snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (snapshot.hasError) {
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text('Failed to load report: ${snapshot.error}'),
                            );
                          }
                          final req = snapshot.data?.data();
                          if (req == null) return const SizedBox.shrink();

                          final images = (req['images'] as List?) ?? const [];
                          final stats = _getDiseaseStats(req);

                          void openDetailsSheet() {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              shape: const RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.vertical(top: Radius.circular(18)),
                              ),
                              builder: (ctx) {
                                return DraggableScrollableSheet(
                                  initialChildSize: 0.85,
                                  minChildSize: 0.6,
                                  maxChildSize: 0.95,
                                  expand: false,
                                  builder: (ctx, controller) {
                                    return SingleChildScrollView(
                                      controller: controller,
                                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Expanded(
                                                child: Text(
                                                  'Report Details',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: () => Navigator.pop(ctx),
                                                icon: const Icon(Icons.close),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              const Text(
                                                'Boxes',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Switch(
                                                value: _showBoxes,
                                                onChanged: (v) =>
                                                    setState(() => _showBoxes = v),
                                                activeColor: Colors.green,
                                              ),
                                            ],
                                          ),
                                          if (images.isNotEmpty) ...[
                                            SizedBox(
                                              height: 120,
                                              child: ListView.separated(
                                                scrollDirection: Axis.horizontal,
                                                itemCount: images.length,
                                                separatorBuilder: (_, __) =>
                                                    const SizedBox(width: 10),
                                                itemBuilder: (context, i) {
                                                  final img = Map<String, dynamic>.from(
                                                    images[i] as Map,
                                                  );
                                                  return SizedBox(
                                                    width: 140,
                                                    child: _buildImageTile(img, i),
                                                  );
                                                },
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                          ],
                                          const Text(
                                            'Results (Avg / Max)',
                                            style:
                                                TextStyle(fontWeight: FontWeight.w800),
                                          ),
                                          const SizedBox(height: 8),
                                          if (stats.isEmpty)
                                            Text(
                                              'No results found.',
                                              style: TextStyle(color: Colors.grey[700]),
                                            )
                                          else ...[
                                            ...stats.map((e) {
                                              final label =
                                                  (e['label'] ?? 'unknown').toString();
                                              final avg = (e['avg'] as double?) ?? 0.0;
                                              final mx = (e['max'] as double?) ?? avg;
                                              final name =
                                                  PigDiseaseUI.displayName(label);
                                              final color =
                                                  PigDiseaseUI.colorFor(label);
                                              return Padding(
                                                padding: const EdgeInsets.only(bottom: 8),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      width: 10,
                                                      height: 10,
                                                      decoration: BoxDecoration(
                                                        color: color,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        name,
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.w600,
                                                          fontSize: 13,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    Text(
                                                      '${(avg * 100).toStringAsFixed(1)}%',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w800,
                                                        color: color,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Text(
                                                      '${(mx * 100).toStringAsFixed(1)}%',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w700,
                                                        color: Colors.grey[700],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          }

                          // When keyboard is open, collapse the heavy "Report Details" UI.
                          if (keyboardOpen) {
                            return Container(
                              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.article_outlined, color: Colors.green),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Report Details • ${images.length} image(s)',
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  OutlinedButton(
                                    onPressed: openDetailsSheet,
                                    child: const Text('Open'),
                                  ),
                                ],
                              ),
                            );
                          }

                          return Container(
                            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: ExpansionTile(
                              initiallyExpanded: true,
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                              title: const Text(
                                'Report Details',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                              ),
                              subtitle: Text(
                                'Tap to expand/collapse • ${images.length} image(s)',
                                style: TextStyle(color: Colors.grey[700], fontSize: 12),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Boxes',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Switch(
                                    value: _showBoxes,
                                    onChanged: (v) => setState(() => _showBoxes = v),
                                    activeColor: Colors.green,
                                  ),
                                ],
                              ),
                              children: [
                                if (images.isNotEmpty) ...[
                                  SizedBox(
                                    height: 120,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: images.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: 10),
                                      itemBuilder: (context, i) {
                                        final img = Map<String, dynamic>.from(
                                          images[i] as Map,
                                        );
                                        return SizedBox(
                                          width: 140,
                                          child: _buildImageTile(img, i),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                const Text(
                                  'Results (Avg / Max)',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                if (stats.isEmpty)
                                  Text(
                                    'No results found.',
                                    style: TextStyle(color: Colors.grey[700]),
                                  )
                                else ...[
                                  ...stats.take(5).map((e) {
                                    final label = (e['label'] ?? 'unknown').toString();
                                    final avg = (e['avg'] as double?) ?? 0.0;
                                    final mx = (e['max'] as double?) ?? avg;
                                    final name = PigDiseaseUI.displayName(label);
                                    final color = PigDiseaseUI.colorFor(label);
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              color: color,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            '${(avg * 100).toStringAsFixed(1)}%',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: color,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            '${(mx * 100).toStringAsFixed(1)}%',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  if (stats.length > 5)
                                    Text(
                                      '+ ${stats.length - 5} more...',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    // Clear "Group Chat" section label so experts know what they are discussing.
                    SliverToBoxAdapter(
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.withOpacity(0.18)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.forum, color: Colors.green, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Group Chat Discussion',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (docs.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text(
                            'No messages yet. Start the discussion below.',
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final m = docs[i].data();
                              final text = (m['text'] ?? '').toString();
                              final sender = (m['senderName'] ?? 'Expert').toString();
                              final senderUid = (m['senderUid'] ?? '').toString();
                              final isMe = senderUid ==
                                  (FirebaseAuth.instance.currentUser?.uid ?? '');
                              return Align(
                                alignment:
                                    isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  constraints: const BoxConstraints(maxWidth: 320),
                                  decoration: BoxDecoration(
                                    color: isMe ? Colors.green : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: isMe
                                        ? null
                                        : Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (!isMe)
                                        Text(
                                          sender,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      if (!isMe) const SizedBox(height: 4),
                                      Text(
                                        text,
                                        style: TextStyle(
                                          color: isMe ? Colors.white : Colors.black87,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            childCount: docs.length,
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageCtrl,
                      textInputAction: TextInputAction.send,
                      maxLines: 1,
                      onSubmitted: (_) => _sending ? null : _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Write a message...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _sending ? null : _sendMessage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Send'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}



