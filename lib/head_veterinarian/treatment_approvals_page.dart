import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import '../user/login_page.dart';
import '../shared/treatments_repository.dart';
import 'veterinarian_profile.dart';
import '../shared/disease_image.dart';

class TreatmentApprovalsPage extends StatefulWidget {
  const TreatmentApprovalsPage({super.key});

  @override
  State<TreatmentApprovalsPage> createState() => _TreatmentApprovalsPageState();
}

class _TreatmentApprovalsPageState extends State<TreatmentApprovalsPage> {
  final TreatmentsRepository _repo = TreatmentsRepository();

  Future<void> _logout() async {
    try {
      // Clear local login state
      final box = await Hive.openBox('userBox');
      await box.put('isLoggedIn', false);
      await box.delete('userProfile');
    } catch (_) {}

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _approve(String id, Map<String, dynamic> data) async {
    try {
      await _repo.approveProposal(proposalId: id, proposalData: data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Approved and published to farmers.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Approve failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _reject(String id) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject changes'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null) return;

    try {
      await _repo.rejectProposal(proposalId: id, reason: reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rejected.'), backgroundColor: Colors.orange),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reject failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        title: const Text('Veterinarian Approvals'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const VeterinarianProfilePage(),
                ),
              );
            },
            icon: const Icon(Icons.person),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'logout') {
                await _logout();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'logout',
                child: Text('Logout'),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder(
        stream: _repo.watchPendingProposals(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 10),
                    const Text(
                      'Cannot load proposals.',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      style: TextStyle(color: Colors.grey[700]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'If you see an index/permission error, fix it in Firestore Rules/Indexes.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          final docs = snapshot.data?.docs ?? const [];
          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No pending treatment updates.',
                style: TextStyle(color: Colors.grey[700]),
              ),
            );
          }

          // Client-side sort (newest first) without requiring Firestore composite indexes.
          docs.sort((a, b) {
            final ad = a.data();
            final bd = b.data();
            final at = ad['submittedAt'];
            final bt = bd['submittedAt'];
            final aDate = at is Timestamp ? at.toDate() : null;
            final bDate = bt is Timestamp ? bt.toDate() : null;
            if (aDate != null && bDate != null) return bDate.compareTo(aDate);
            if (aDate != null) return -1;
            if (bDate != null) return 1;
            return b.id.compareTo(a.id);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final diseaseId = (data['diseaseId'] ?? '').toString();
              final name = (data['name'] ?? '').toString();
              final treatments = (data['treatments'] as List? ?? [])
                  .map((e) => e.toString())
                  .toList();
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DiseaseImage(
                            diseaseId: diseaseId.isEmpty ? 'unknown' : diseaseId,
                            size: 52,
                            borderRadius: 10,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isEmpty ? 'Untitled' : name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${treatments.length} treatment item(s)',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'proposalId: ${doc.id}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
                      const SizedBox(height: 10),
                      if (treatments.isNotEmpty)
                        ...treatments.take(3).map(
                              (t) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '• $t',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _reject(doc.id),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('Reject'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _approve(doc.id, data),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Approve'),
                            ),
                          ),
                        ],
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


