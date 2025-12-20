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

  Future<void> _editPendingProposal(String proposalId, Map<String, dynamic> data) async {
    final nameCtrl = TextEditingController(text: (data['name'] ?? '').toString());
    final sciCtrl = TextEditingController(
      text: (data['scientificName'] ?? '').toString(),
    );
    final list = (data['treatments'] as List? ?? []).map((e) => e.toString()).toList();
    final treatmentCtrls = <TextEditingController>[
      for (final t in (list.isEmpty ? <String>[''] : list))
        TextEditingController(text: t),
    ];

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.6,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Edit Pending Proposal',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
                      ),
                      children: [
                        TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Disease Name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: sciCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Scientific Name (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Treatments',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                treatmentCtrls.add(TextEditingController());
                                // Rebuild bottom sheet
                                (context as Element).markNeedsBuild();
                              },
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...List.generate(treatmentCtrls.length, (i) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: treatmentCtrls[i],
                                    decoration: InputDecoration(
                                      labelText: 'Treatment ${i + 1}',
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Remove',
                                  onPressed: treatmentCtrls.length <= 1
                                      ? null
                                      : () {
                                          treatmentCtrls[i].dispose();
                                          treatmentCtrls.removeAt(i);
                                          (context as Element).markNeedsBuild();
                                        },
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Save'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
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

    if (saved != true) {
      nameCtrl.dispose();
      sciCtrl.dispose();
      for (final c in treatmentCtrls) {
        c.dispose();
      }
      return;
    }

    final newName = nameCtrl.text.trim();
    final newSci = sciCtrl.text.trim();
    final newTreatments = treatmentCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    nameCtrl.dispose();
    sciCtrl.dispose();
    for (final c in treatmentCtrls) {
      c.dispose();
    }

    if (newName.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Disease name is required.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await _repo.vetEditPendingProposal(
        proposalId: proposalId,
        name: newName,
        scientificName: newSci,
        treatments: newTreatments,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Updated. Proposal is still pending for approval.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Edit failed: $e'), backgroundColor: Colors.red),
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
                              onPressed: () => _editPendingProposal(doc.id, data),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blueGrey[700],
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
                                  'Edit',
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _reject(doc.id),
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
                                  'Reject',
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
      ),
    );
  }
}


