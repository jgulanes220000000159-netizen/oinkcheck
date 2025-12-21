import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Firestore model:
/// - treatments_public/{diseaseId}  -> APPROVED data read by farmers
/// - treatment_proposals/{proposalId} -> PENDING/APPROVED/REJECTED changes created by experts
class TreatmentsRepository {
  TreatmentsRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _public =>
      _db.collection('treatments_public');

  CollectionReference<Map<String, dynamic>> get _proposals =>
      _db.collection('treatment_proposals');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchApprovedTreatments() {
    return _public.orderBy('name').snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchProposalsBySubmitter(
    String submittedBy,
  ) {
    return _proposals.where('submittedBy', isEqualTo: submittedBy).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingProposals() {
    // NOTE: Avoid composite index requirements by not using orderBy here.
    // We sort client-side in the UI if needed.
    return _proposals.where('status', isEqualTo: 'pending').snapshots();
  }

  Future<void> deleteProposal(String proposalId) async {
    await _proposals.doc(proposalId).delete();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getPublicDoc(
    String diseaseId,
  ) async {
    return _public.doc(diseaseId).get();
  }

  /// Head veterinarian direct publish (no approval step).
  /// Writes directly to `treatments_public/{diseaseId}` so farmers see it immediately.
  Future<void> upsertPublicTreatment({
    required String diseaseId,
    required String name,
    String? scientificName,
    required List<String> treatments,
    String? imageUrl,
  }) async {
    final user = _auth.currentUser;
    await _public.doc(diseaseId).set({
      'diseaseId': diseaseId,
      'name': name,
      'scientificName': scientificName ?? '',
      'treatments': treatments,
      if (imageUrl != null) 'imageUrl': imageUrl,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user?.uid,
      'updatedByRole': 'head_veterinarian',
    }, SetOptions(merge: true));
  }

  Future<String> submitProposal({
    String? proposalId,
    required String diseaseId,
    required String name,
    String? scientificName,
    required List<String> treatments,
    String? imageUrl,
  }) async {
    final user = _auth.currentUser;
    final submittedBy = user?.uid;

    // Best-effort: attach expert display info to the proposal so veterinarians can see
    // who submitted it without extra lookups.
    String submittedByName = '';
    String submittedByEmail = user?.email ?? '';
    if (submittedBy != null) {
      try {
        final userDoc = await _db.collection('users').doc(submittedBy).get();
        final u = userDoc.data();
        if (u != null) {
          submittedByName = (u['fullName'] ?? u['expertName'] ?? '').toString();
          if (submittedByEmail.isEmpty) {
            submittedByEmail = (u['email'] ?? '').toString();
          }
        }
      } catch (_) {
        // Ignore lookup errors; proposal can still be submitted.
      }
    }
    final data = <String, dynamic>{
      'diseaseId': diseaseId,
      'name': name,
      'scientificName': scientificName ?? '',
      'treatments': treatments,
      'status': 'pending',
      'imageUrl': imageUrl ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
      'submittedBy': submittedBy,
      'submittedByName': submittedByName,
      'submittedByEmail': submittedByEmail,
    };

    // Helps with debugging and UI ordering even before serverTimestamp resolves.
    final nowIso = DateTime.now().toIso8601String();

    if (proposalId != null && proposalId.trim().isNotEmpty) {
      // Resubmission/edit of an existing proposal: keep original submittedAt if present.
      await _proposals.doc(proposalId).set({
        ...data,
        'resubmittedAt': FieldValue.serverTimestamp(),
        'resubmittedAtLocal': nowIso,
      }, SetOptions(merge: true));
      return proposalId;
    }

    final ref = await _proposals.add({
      ...data,
      'submittedAt': FieldValue.serverTimestamp(),
      'submittedAtLocal': nowIso,
    });
    return ref.id;
  }

  /// Veterinarian-only edit of a pending proposal. Keeps the original `submittedBy`.
  Future<void> vetEditPendingProposal({
    required String proposalId,
    required String name,
    String? scientificName,
    required List<String> treatments,
    String? imageUrl,
  }) async {
    final vet = _auth.currentUser;
    await _proposals.doc(proposalId).set({
      'name': name,
      'scientificName': scientificName ?? '',
      'treatments': treatments,
      if (imageUrl != null) 'imageUrl': imageUrl,
      'status': 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
      'vetEditedAt': FieldValue.serverTimestamp(),
      'vetEditedBy': vet?.uid,
    }, SetOptions(merge: true));
  }

  Future<void> approveProposal({
    required String proposalId,
    required Map<String, dynamic> proposalData,
  }) async {
    final user = _auth.currentUser;
    final batch = _db.batch();

    final diseaseId = (proposalData['diseaseId'] ?? '').toString();
    if (diseaseId.isEmpty) {
      throw StateError('Proposal missing diseaseId');
    }

    final publicRef = _public.doc(diseaseId);
    final proposalRef = _proposals.doc(proposalId);

    batch.set(publicRef, {
      'diseaseId': diseaseId,
      'name': proposalData['name'] ?? '',
      'scientificName': proposalData['scientificName'] ?? '',
      'treatments': (proposalData['treatments'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      'imageUrl': (proposalData['imageUrl'] ?? '').toString(),
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': user?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.update(proposalRef, {
      'status': 'approved',
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': user?.uid,
    });

    await batch.commit();
  }

  Future<void> rejectProposal({
    required String proposalId,
    String? reason,
  }) async {
    final user = _auth.currentUser;
    await _proposals.doc(proposalId).update({
      'status': 'rejected',
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': user?.uid,
      'rejectionReason': reason ?? '',
    });
  }
}


