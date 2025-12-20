import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

import '../shared/pig_disease_ui.dart';
import 'expert_chat_thread_page.dart';

enum _InboxFilter { all, underDiscussion, resolved, myThreads }

class ExpertChatInboxPage extends StatefulWidget {
  const ExpertChatInboxPage({super.key});

  @override
  State<ExpertChatInboxPage> createState() => _ExpertChatInboxPageState();
}

class _ExpertChatInboxPageState extends State<ExpertChatInboxPage> {
  _InboxFilter _filter = _InboxFilter.all;
  final Map<String, String> _labelCache = {};

  Future<String> _currentName() async {
    try {
      final box = await Hive.openBox('userBox');
      final profile = box.get('userProfile');
      final name = (profile?['fullName'] ?? '').toString().trim();
      return name.isEmpty ? 'Expert' : name;
    } catch (_) {
      return 'Expert';
    }
  }

  Future<String> _fixedLabelFor({
    required String discussionId,
    required String requestId,
    required String storedLabel,
  }) async {
    final cached = _labelCache[discussionId];
    if (cached != null && cached.isNotEmpty) return cached;

    final storedKey = PigDiseaseUI.normalizeKey(storedLabel);
    final needsFix =
        storedKey.isEmpty || storedKey == 'unknown' || storedKey == 'healthy';
    if (!needsFix) {
      _labelCache[discussionId] = storedLabel;
      return storedLabel;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('scan_requests')
          .doc(requestId)
          .get();
      final req = snap.data() ?? <String, dynamic>{};
      final summary = (req['diseaseSummary'] as List?) ?? const [];
      final fixed = PigDiseaseUI.dominantLabelFromSummary(
        summary,
        preferNonHealthy: true,
      );
      final finalLabel = fixed.trim().isEmpty ? storedLabel : fixed;
      _labelCache[discussionId] = finalLabel;

      if (finalLabel.trim().isNotEmpty &&
          PigDiseaseUI.normalizeKey(finalLabel) != storedKey) {
        // Best-effort: update discussion doc so future loads are consistent.
        await FirebaseFirestore.instance
            .collection('expert_discussions')
            .doc(discussionId)
            .set({'diseaseLabel': finalLabel}, SetOptions(merge: true));
      }
      return finalLabel;
    } catch (_) {
      _labelCache[discussionId] = storedLabel;
      return storedLabel;
    }
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey[800],
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _filterDropdown() {
    String labelFor(_InboxFilter f) {
      switch (f) {
        case _InboxFilter.all:
          return 'All';
        case _InboxFilter.underDiscussion:
          return 'Under Discussion';
        case _InboxFilter.resolved:
          return 'Resolved';
        case _InboxFilter.myThreads:
          return 'My Threads';
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          Text(
            'Filter',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<_InboxFilter>(
              value: _filter,
              isExpanded: true,
              items: _InboxFilter.values
                  .map(
                    (f) => DropdownMenuItem<_InboxFilter>(
                      value: f,
                      child: Text(labelFor(f)),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _filter = v);
              },
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        title: const Text('Expert Chatbox'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance
                .collection('expert_discussions')
                .orderBy('lastMessageAt', descending: true)
                .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Failed to load discussions: ${snapshot.error}'),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? const [];
          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No discussions yet.',
                style: TextStyle(color: Colors.grey[700]),
              ),
            );
          }

          // Split into sections. Under Discussion always first.
          final under = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final resolved = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

          for (final d in docs) {
            final status = (d.data()['status'] ?? 'open').toString();
            final createdByUid = (d.data()['createdByUid'] ?? '').toString();
            if (_filter == _InboxFilter.myThreads &&
                myUid.isNotEmpty &&
                createdByUid != myUid) {
              continue;
            }
            if (status == 'closed') {
              resolved.add(d);
            } else {
              under.add(d);
            }
          }

          List<QueryDocumentSnapshot<Map<String, dynamic>>> shownUnder = under;
          List<QueryDocumentSnapshot<Map<String, dynamic>>> shownResolved = resolved;
          if (_filter == _InboxFilter.underDiscussion) {
            shownResolved = const [];
          } else if (_filter == _InboxFilter.resolved) {
            shownUnder = const [];
          }

          Widget buildTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
            final data = doc.data();
            final requestId = (data['requestId'] ?? doc.id).toString();
            final userName = (data['userName'] ?? 'Farmer').toString();
            final diseaseLabel = (data['diseaseLabel'] ?? 'unknown').toString();
            final lastText = (data['lastMessageText'] ?? '').toString();
            final status = (data['status'] ?? 'open').toString();
            final createdByName = (data['createdByName'] ?? 'Expert').toString();

            return FutureBuilder<String>(
              future: _fixedLabelFor(
                discussionId: doc.id,
                requestId: requestId,
                storedLabel: diseaseLabel,
              ),
              builder: (context, snap) {
                final label = (snap.data ?? diseaseLabel).toString();
                final diseaseName = PigDiseaseUI.displayName(label);
                final color = PigDiseaseUI.colorFor(label);

                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    final myName = await _currentName();
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExpertChatThreadPage(
                          discussionId: doc.id,
                          requestId: requestId,
                          myName: myName,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
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
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      diseaseName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
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
                                      border: Border.all(
                                        color: status == 'closed'
                                            ? Colors.grey.withOpacity(0.25)
                                            : Colors.orange.withOpacity(0.25),
                                      ),
                                    ),
                                    child: Text(
                                      status == 'closed' ? 'RESOLVED' : 'DISCUSSING',
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
                              const SizedBox(height: 4),
                              Text(
                                'Report: $userName',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Owner: $createdByName',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                lastText.isEmpty
                                    ? 'Tap to open discussion'
                                    : lastText,
                                style: TextStyle(
                                  color: Colors.grey[800],
                                  fontSize: 12,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right, color: Colors.grey[500]),
                      ],
                    ),
                  ),
                );
              },
            );
          }

          final children = <Widget>[
            _filterDropdown(),
            if (shownUnder.isNotEmpty) _sectionHeader('Under Discussion'),
            ...shownUnder.map((d) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: buildTile(d),
                )),
            if (shownResolved.isNotEmpty) _sectionHeader('Resolved'),
            ...shownResolved.map((d) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: buildTile(d),
                )),
            if (shownUnder.isEmpty && shownResolved.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    _filter == _InboxFilter.resolved
                        ? 'No resolved discussions yet.'
                        : _filter == _InboxFilter.underDiscussion
                            ? 'No discussions under review right now.'
                            : 'No discussions yet.',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ];

          return ListView(
            padding: EdgeInsets.zero,
            children: children,
          );
        },
      ),
    );
  }
}


