import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../shared/pig_disease_ui.dart';
import 'ml_expert_my_evaluation_detail_page.dart';

class MLExpertMyEvaluationsPage extends StatelessWidget {
  const MLExpertMyEvaluationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        body: Center(
          child: Text(
            'Please login again.',
            style: TextStyle(color: Colors.grey[700]),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('ml_expert_evaluations')
            .where('evaluatorUid', isEqualTo: user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error loading history:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No scan history yet.\nYour saved ratings will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700]),
              ),
            );
          }

          final items = docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            return {...data, '_docId': d.id};
          }).toList();
          // Sort client-side to avoid composite index requirements.
          items.sort((a, b) {
            final aT = a['createdAt'];
            final bT = b['createdAt'];
            DateTime? da;
            DateTime? db;
            if (aT is Timestamp) da = aT.toDate();
            if (bT is Timestamp) db = bT.toDate();
            if (aT is String) da = DateTime.tryParse(aT);
            if (bT is String) db = DateTime.tryParse(bT);
            if (da == null && db == null) return 0;
            if (da == null) return 1;
            if (db == null) return -1;
            return db.compareTo(da);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final e = items[index];
              final rating = (e['rating'] as num?)?.toInt() ?? 0;
              final comment = (e['comment'] ?? '').toString().trim();
              final createdAt = e['createdAt'];
              DateTime? dt;
              if (createdAt is Timestamp) dt = createdAt.toDate();
              final when = dt != null
                  ? '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
                      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
                  : '—';

              final summary = (e['summary'] as List?) ?? const [];
              final label = _dominantFromSummary(summary);
              final color = PigDiseaseUI.colorFor(label);
              final title = PigDiseaseUI.displayName(label);

              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MLExpertMyEvaluationDetailPage(evaluation: e),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.star_rate, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _Stars(rating: rating),
                            const SizedBox(height: 6),
                            Text(
                              when,
                              style: TextStyle(color: Colors.grey[700], fontSize: 12),
                            ),
                            if (comment.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                comment,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.grey[800]),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right, color: Colors.grey[400]),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _dominantFromSummary(List summary) {
    // summary is stored as list of maps {label, avgConfidence, maxConfidence, ...}
    final List<Map<String, dynamic>> cleaned = [];
    for (final e in summary) {
      if (e is Map) cleaned.add(Map<String, dynamic>.from(e));
    }
    return PigDiseaseUI.dominantLabelFromSummary(cleaned);
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating});
  final int rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (i) {
        final filled = (i + 1) <= rating;
        return Icon(
          filled ? Icons.star : Icons.star_border,
          size: 16,
          color: filled ? Colors.amber[700] : Colors.grey[400],
        );
      }),
    );
  }
}


