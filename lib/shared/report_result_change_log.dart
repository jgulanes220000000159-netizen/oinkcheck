import 'package:cloud_firestore/cloud_firestore.dart';
import 'pig_disease_ui.dart';

class ReportResultChangeLog {
  static Set<String> _labelsFromSummary(List<Map<String, dynamic>> summary) {
    return summary
        .map((e) => PigDiseaseUI.normalizeKey((e['label'] ?? e['disease'] ?? e['name'] ?? '').toString()))
        .where((k) => k.isNotEmpty && k != 'unknown')
        .toSet();
  }

  /// Builds a Firestore-friendly change log comparing previous vs new summary.
  /// We report **Added** and **Removed**. If both exist, that naturally implies "Changed".
  static Map<String, dynamic> build({
    required List<Map<String, dynamic>> before,
    required List<Map<String, dynamic>> after,
    required String byUid,
    required String byName,
    required String source, // e.g. 'expert_review' | 'discussion' | 'edit_completed'
  }) {
    final oldSet = _labelsFromSummary(before);
    final newSet = _labelsFromSummary(after);

    final added = (newSet.difference(oldSet)).toList()..sort();
    final removed = (oldSet.difference(newSet)).toList()..sort();

    final parts = <String>[];
    if (added.isNotEmpty) {
      parts.add(
        'Added: ${added.map(PigDiseaseUI.displayName).join(', ')}',
      );
    }
    if (removed.isNotEmpty) {
      parts.add(
        'Removed: ${removed.map(PigDiseaseUI.displayName).join(', ')}',
      );
    }

    final message =
        parts.isEmpty ? 'Results updated.' : 'Results updated • ${parts.join(' • ')}';

    return {
      'message': message,
      'added': added,
      'removed': removed,
      'byUid': byUid,
      'byName': byName,
      'source': source,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}


