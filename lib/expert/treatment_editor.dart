import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../shared/treatments_repository.dart';
import '../shared/disease_image.dart';

class TreatmentEditorPage extends StatefulWidget {
  const TreatmentEditorPage({
    super.key,
    this.directPublish = false,
    this.showPending = true,
  });

  /// If true, saves directly to `treatments_public` (for head veterinarian).
  /// If false, submits proposals for approval (for experts).
  final bool directPublish;

  /// If false, hides the pending-proposals UI (useful for head vet manage tab).
  final bool showPending;

  @override
  State<TreatmentEditorPage> createState() => _TreatmentEditorPageState();
}

class _TreatmentEditorPageState extends State<TreatmentEditorPage> {
  final TreatmentsRepository _repo = TreatmentsRepository();

  // fallback list (used if Firestore public collection is empty)
  static const List<Map<String, String>> _defaultDiseases = [
    {'id': 'swine_pox', 'name': 'Swine Pox'},
    {'id': 'erysipelas', 'name': 'Erysipelas'},
    {'id': 'greasy_pig_disease', 'name': 'Greasy Pig Disease'},
    {'id': 'ringworm', 'name': 'Ringworm'},
    {'id': 'mange', 'name': 'Mange'},
    {'id': 'foot_and_mouth', 'name': 'Foot and Mouth Disease'},
    {'id': 'sunburn', 'name': 'Sunburn'},
  ];

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: StreamBuilder(
        stream: _repo.watchApprovedTreatments(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Failed to load approved treatments: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final approvedDocs = snapshot.data?.docs ?? const [];
          final approvedByDiseaseId = <String, Map<String, dynamic>>{};
          for (final d in approvedDocs) {
            final data = d.data();
            final diseaseId = (data['diseaseId'] ?? d.id).toString();
            approvedByDiseaseId[diseaseId] = data;
          }

          if (uid == null) {
            return const Center(child: Text('Not signed in.'));
          }

          // Head vet "direct publish" mode does not need proposal tracking UI.
          if (!widget.showPending) {
            // ALWAYS show the 7 diseases. Overlay approved info if present.
            final items = _defaultDiseases
                .map((d) {
                  final id = d['id']!;
                  final base = <String, dynamic>{
                    'diseaseId': id,
                    'name': d['name']!,
                    'scientificName': '',
                    'treatments': <String>[],
                  };
                  final approved = approvedByDiseaseId[id];
                  final merged = <String, dynamic>{
                    ...base,
                    if (approved != null) ...approved,
                  };
                  return {
                    'id': id,
                    'name': (merged['name'] ?? d['name']!).toString(),
                    'data': merged,
                  };
                })
                .toList();

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final id = item['id'] as String;
                final name = item['name'] as String;
                final data = item['data'] as Map<String, dynamic>;
                final treatments = (data['treatments'] as List? ?? [])
                    .map((e) => e.toString())
                    .toList();
                final hasApproved = treatments.isNotEmpty;

                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading:
                        DiseaseImage(diseaseId: id, size: 52, borderRadius: 10),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (hasApproved)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.green.withOpacity(0.25),
                              ),
                            ),
                            child: const Text(
                              'PUBLISHED',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      '${treatments.length} treatment item(s)',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    trailing: const Icon(Icons.edit, color: Colors.green),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TreatmentEditScreen(
                            diseaseId: id,
                            initial: data,
                            directPublish: widget.directPublish,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          }

          return StreamBuilder(
            stream: _repo.watchProposalsBySubmitter(uid),
            builder: (context, proposalSnap) {
              if (proposalSnap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Failed to load your proposals: ${proposalSnap.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final proposalDocs = proposalSnap.data?.docs ?? const [];
              final pendingByDiseaseId = <String, List<Map<String, dynamic>>>{};
              for (final p in proposalDocs) {
                final data = p.data();
                if ((data['status'] ?? '').toString() != 'pending') continue;
                final diseaseId = (data['diseaseId'] ?? '').toString();
                if (diseaseId.isEmpty) continue;
                pendingByDiseaseId.putIfAbsent(diseaseId, () => []).add({
                  ...data,
                  'id': p.id,
                });
              }
              for (final entry in pendingByDiseaseId.entries) {
                entry.value.sort((a, b) {
                  final at = a['submittedAt'];
                  final bt = b['submittedAt'];
                  final aDate = at is Timestamp ? at.toDate() : null;
                  final bDate = bt is Timestamp ? bt.toDate() : null;
                  if (aDate != null && bDate != null) return bDate.compareTo(aDate);
                  // fallback to local timestamp if server timestamp isn't there yet
                  final al = (a['resubmittedAtLocal'] ?? a['submittedAtLocal'] ?? '').toString();
                  final bl = (b['resubmittedAtLocal'] ?? b['submittedAtLocal'] ?? '').toString();
                  return bl.compareTo(al);
                });
              }

              // ALWAYS show the 7 diseases. Overlay approved info if present.
              final items = _defaultDiseases
                  .map((d) {
                    final id = d['id']!;
                    final base = <String, dynamic>{
                      'diseaseId': id,
                      'name': d['name']!,
                      'scientificName': '',
                      'treatments': <String>[],
                    };
                    final approved = approvedByDiseaseId[id];
                    final merged = <String, dynamic>{...base, if (approved != null) ...approved};
                    return {
                      'id': id,
                      'name': (merged['name'] ?? d['name']!).toString(),
                      'data': merged,
                      'pendingCount': (pendingByDiseaseId[id]?.length ?? 0),
                      'pendingList': pendingByDiseaseId[id] ?? const <Map<String, dynamic>>[],
                    };
                  })
                  .toList();

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final id = item['id'] as String;
                  final name = item['name'] as String;
                  final data = item['data'] as Map<String, dynamic>;
                  final pendingCount = item['pendingCount'] as int;
                  final pendingList =
                      (item['pendingList'] as List).cast<Map<String, dynamic>>();
                  final treatments = (data['treatments'] as List? ?? [])
                      .map((e) => e.toString())
                      .toList();

                  final hasApproved = treatments.isNotEmpty;

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: DiseaseImage(diseaseId: id, size: 52, borderRadius: 10),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (pendingCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.orange.withOpacity(0.35)),
                              ),
                              child: Text(
                                'PENDING ($pendingCount)',
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            )
                          else if (hasApproved)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.green.withOpacity(0.25)),
                              ),
                              child: const Text(
                                'APPROVED',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        pendingCount > 0
                            ? 'Waiting for veterinarian approval'
                            : '${treatments.length} treatment item(s)',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      trailing: const Icon(Icons.edit, color: Colors.green),
                      onTap: () async {
                        if (pendingCount > 0) {
                          await showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(18),
                              ),
                            ),
                            builder: (context) {
                              return SafeArea(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              name,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () => Navigator.pop(context),
                                            icon: const Icon(Icons.close),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      if (pendingList.isNotEmpty) ...[
                                        const Text(
                                          'Pending submissions',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        ...pendingList.map((p) {
                                          final pid = (p['id'] ?? '').toString();
                                          final pTreatments = (p['treatments'] as List? ?? [])
                                              .map((e) => e.toString())
                                              .toList();
                                          return Container(
                                            margin: const EdgeInsets.only(bottom: 10),
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withOpacity(0.08),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: Colors.orange.withOpacity(0.2),
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    const Icon(Icons.pending_actions, color: Colors.orange, size: 18),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        'proposalId: $pid',
                                                        style: TextStyle(
                                                          color: Colors.grey[700],
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  '${pTreatments.length} treatment item(s)',
                                                  style: TextStyle(color: Colors.grey[700]),
                                                ),
                                                if (pTreatments.isNotEmpty) ...[
                                                  const SizedBox(height: 6),
                                                  ...pTreatments.take(3).map((t) => Text('• $t')),
                                                ],
                                                const SizedBox(height: 10),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: OutlinedButton(
                                                        onPressed: () async {
                                                          Navigator.pop(context);
                                                          await Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                              builder: (_) => TreatmentEditScreen(
                                                                diseaseId: id,
                                                                initial: p,
                                                                proposalId: pid,
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                        child: const Text('Edit / Resubmit'),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: OutlinedButton(
                                                        style: OutlinedButton.styleFrom(
                                                          foregroundColor: Colors.red,
                                                        ),
                                                        onPressed: () async {
                                                          final ok = await showDialog<bool>(
                                                            context: context,
                                                            builder: (context) => AlertDialog(
                                                              title: const Text('Delete pending submission?'),
                                                              content: const Text('This will remove the pending proposal.'),
                                                              actions: [
                                                                TextButton(
                                                                  onPressed: () => Navigator.pop(context, false),
                                                                  child: const Text('Cancel'),
                                                                ),
                                                                TextButton(
                                                                  onPressed: () => Navigator.pop(context, true),
                                                                  child: const Text('Delete'),
                                                                ),
                                                              ],
                                                            ),
                                                          );
                                                          if (ok == true) {
                                                            await _repo.deleteProposal(pid);
                                                            if (!context.mounted) return;
                                                            Navigator.pop(context);
                                                          }
                                                        },
                                                        child: const Text('Delete'),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                      const SizedBox(height: 8),
                                      ElevatedButton.icon(
                                        onPressed: () async {
                                          Navigator.pop(context);
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => TreatmentEditScreen(
                                                diseaseId: id,
                                                initial: data,
                                              ),
                                            ),
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          minimumSize: const Size.fromHeight(44),
                                        ),
                                        icon: const Icon(Icons.add),
                                        label: const Text('Create new update'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        } else {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TreatmentEditScreen(
                                diseaseId: id,
                                initial: data,
                              ),
                            ),
                          );
                        }
                      },
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

class TreatmentEditScreen extends StatefulWidget {
  const TreatmentEditScreen({
    super.key,
    required this.diseaseId,
    required this.initial,
    this.proposalId,
    this.directPublish = false,
  });

  final String diseaseId;
  final Map<String, dynamic> initial;
  final String? proposalId;
  final bool directPublish;

  @override
  State<TreatmentEditScreen> createState() => _TreatmentEditScreenState();
}

class _TreatmentEditScreenState extends State<TreatmentEditScreen> {
  final TreatmentsRepository _repo = TreatmentsRepository();
  final _name = TextEditingController();
  final _scientificName = TextEditingController();
  final List<TextEditingController> _treatmentCtrls = [];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.text = (widget.initial['name'] ?? '').toString();
    _scientificName.text = (widget.initial['scientificName'] ?? '').toString();
    final list = (widget.initial['treatments'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    if (list.isEmpty) list.add('');
    for (final t in list) {
      _treatmentCtrls.add(TextEditingController(text: t));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _scientificName.dispose();
    for (final c in _treatmentCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final treatments = _treatmentCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    setState(() => _saving = true);
    try {
      if (widget.directPublish) {
        await _repo.upsertPublicTreatment(
          diseaseId: widget.diseaseId,
          name: name,
          scientificName: _scientificName.text.trim(),
          treatments: treatments,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Published to farmers.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final proposalId = await _repo.submitProposal(
          proposalId: widget.proposalId,
          diseaseId: widget.diseaseId,
          name: name,
          scientificName: _scientificName.text.trim(),
          treatments: treatments,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Submitted for approval. (proposalId: $proposalId)'),
            backgroundColor: Colors.green,
          ),
        );
      }
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        title: Text(
          widget.directPublish
              ? 'Edit Treatment'
              : (widget.proposalId == null ? 'Edit Treatment' : 'Edit Pending Proposal'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Disease Photo',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Center(
                child: DiseaseImage(
                  diseaseId: widget.diseaseId,
                  size: 140,
                  borderRadius: 16,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Disease Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _scientificName,
              decoration: const InputDecoration(
                labelText: 'Scientific Name (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Treatments',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ..._treatmentCtrls.asMap().entries.map((entry) {
              final idx = entry.key;
              final ctrl = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        decoration: InputDecoration(
                          labelText: 'Treatment ${idx + 1}',
                          border: const OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _treatmentCtrls.length <= 1
                          ? null
                          : () {
                              setState(() {
                                _treatmentCtrls.removeAt(idx).dispose();
                              });
                            },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              );
            }),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _treatmentCtrls.add(TextEditingController());
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Add treatment item'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(widget.directPublish ? 'Save' : 'Submit for approval'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


