import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../shared/pig_disease_ui.dart';
import 'ml_expert_completed_report_detail_page.dart';

class MLExpertCompletedReportsPage extends StatelessWidget {
  const MLExpertCompletedReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('scan_requests')
            .where('status', whereIn: ['completed', 'reviewed'])
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error loading completed reports:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final requests = snapshot.data!.docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            return {...data, '_docId': d.id};
          }).toList();

          requests.sort((a, b) {
            final aT = a['submittedAt'];
            final bT = b['submittedAt'];
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

          if (requests.isEmpty) {
            return Center(
              child: Text(
                'No completed reports yet.',
                style: TextStyle(color: Colors.grey[700]),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final r = requests[index];
              final farmer = (r['userName'] ?? r['fullName'] ?? 'Farmer').toString();
              final status = (r['status'] ?? '').toString();
              final summary = (r['expertDiseaseSummary'] ?? r['diseaseSummary']) as List?;
              final dominant = PigDiseaseUI.dominantLabelFromSummary(
                (summary ?? const [])
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList(),
              );
              final color = PigDiseaseUI.colorFor(dominant);
              final title = PigDiseaseUI.displayName(dominant);
              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          MLExpertCompletedReportDetailPage(request: r),
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
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.assignment_turned_in, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              farmer,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              title,
                              style: TextStyle(color: Colors.grey[700]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: status == 'completed' ? Colors.green.withOpacity(0.15) : Colors.blue.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status == 'completed' ? 'Completed' : 'Reviewed',
                          style: TextStyle(
                            color: status == 'completed' ? Colors.green[800] : Colors.blue[800],
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
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
}


