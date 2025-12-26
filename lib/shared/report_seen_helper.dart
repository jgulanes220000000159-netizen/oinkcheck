import 'package:hive/hive.dart';

/// Helper class to mark reports as seen (for both farmer and expert sides)
class ReportSeenHelper {
  /// Mark a completed report as seen (farmer side)
  static Future<void> markCompletedReportSeen(String requestId) async {
    if (requestId.isEmpty) return;
    try {
      final box = await Hive.openBox('userRequestsSeenBox');
      final saved = box.get('seenCompletedIds', defaultValue: []) as List;
      final seenIds = saved.map((e) => e.toString()).toSet();
      
      if (!seenIds.contains(requestId)) {
        seenIds.add(requestId);
        await box.put('seenCompletedIds', seenIds.toList());
      }
    } catch (e) {
      print('Error marking completed report as seen: $e');
    }
  }

  /// Mark a pending report as seen (expert side)
  static Future<void> markPendingReportSeen(String requestId) async {
    if (requestId.isEmpty) return;
    try {
      final box = await Hive.openBox('expertRequestsSeenBox');
      final saved = box.get('seenPendingIds', defaultValue: []) as List;
      final seenIds = saved.map((e) => e.toString()).toSet();
      
      if (!seenIds.contains(requestId)) {
        seenIds.add(requestId);
        await box.put('seenPendingIds', seenIds.toList());
      }
    } catch (e) {
      print('Error marking pending report as seen: $e');
    }
  }
}

