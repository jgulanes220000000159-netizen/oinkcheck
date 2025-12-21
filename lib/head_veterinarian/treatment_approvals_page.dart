import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import '../user/login_page.dart';
import '../shared/treatments_repository.dart';
import 'veterinarian_profile.dart';
import '../shared/disease_image.dart';

class TreatmentApprovalsPage extends StatefulWidget {
  const TreatmentApprovalsPage({super.key, this.embedded = false});

  /// When true, this page is shown inside the expert-style veterinarian dashboard,
  /// so we hide the AppBar and rely on the parent header/profile.
  final bool embedded;

  @override
  State<TreatmentApprovalsPage> createState() => _TreatmentApprovalsPageState();
}

class _TreatmentApprovalsPageState extends State<TreatmentApprovalsPage> {
  final TreatmentsRepository _repo = TreatmentsRepository();
  final Map<String, String> _expertNameCache = {};

  Future<String> _resolveExpertName(Map<String, dynamic> proposalData) async {
    final fromDoc = (proposalData['submittedByName'] ?? '').toString().trim();
    if (fromDoc.isNotEmpty) return fromDoc;

    final uid = (proposalData['submittedBy'] ?? '').toString().trim();
    if (uid.isEmpty) return 'Unknown Expert';
    final cached = _expertNameCache[uid];
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      final name = (data?['fullName'] ?? data?['expertName'] ?? '').toString();
      final finalName = name.trim().isEmpty ? 'Unknown Expert' : name.trim();
      _expertNameCache[uid] = finalName;
      return finalName;
    } catch (_) {
      return 'Unknown Expert';
    }
  }

  Future<void> _cancelProposal(String id) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel proposal'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Remarks (optional)',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancel proposal'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null) return;

    try {
      // Keep record for audit; do NOT delete.
      await _repo.rejectProposal(proposalId: id, reason: reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Canceled.'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cancel failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

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

  // Removed: delete behavior. Head vet now "cancels" with optional remarks.

  @override
  Widget build(BuildContext context) {
    final list = StreamBuilder(
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
              return FutureBuilder<String>(
                future: _resolveExpertName(data),
                builder: (context, nameSnap) {
                  final expertName =
                      nameSnap.data ?? (data['submittedByName'] ?? '').toString();
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
                                const SizedBox(height: 6),
                                Text(
                                  'Submitted by: ${expertName.trim().isEmpty ? 'Unknown Expert' : expertName}',
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                              onPressed: () => _cancelProposal(doc.id),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                minimumSize: const Size(0, 40),
                              ),
                              child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Cancel',
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _approve(doc.id, data),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                minimumSize: const Size(0, 40),
                              ),
                              child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Approve',
                                  maxLines: 1,
                                ),
                              ),
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
          );
        },
      );

    if (widget.embedded) {
      return Container(
        color: Colors.grey[50],
        child: list,
      );
    }

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
      body: list,
    );
  }
}


