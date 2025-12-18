import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class TrackingModels {
  // Use the same color mapping as DetectionPainter
  static const Map<String, Color> diseaseColors = {
    'anthracnose': Colors.orange,
    'backterial_blackspot': Colors.purple,
    'dieback': Colors.red,
    'healthy': Color.fromARGB(255, 2, 119, 252),
    'powdery_mildew': Color.fromARGB(255, 9, 46, 2),
    'tip_burn': Colors.brown,
    'Unknown': Colors.grey,
  };

  // List of real diseases (excluding tip burn/unknown)
  static const List<String> diseaseLabels = [
    'anthracnose',
    'backterial_blackspot',
    'powdery_mildew',
    'dieback',
  ];

  static const List<Map<String, dynamic>> timeRanges = [
    {'label': 'Last 7 Days', 'days': 7},
    {'label': 'Monthly', 'days': 30},
    {'label': 'Custom', 'days': null},
  ];

  static bool isRealDisease(String label) {
    final l = label.toLowerCase();
    return diseaseLabels.contains(l);
  }

  static String getSourceDisplayText(String? source) {
    switch (source) {
      case 'expert_review':
        return tr('reviewing');
      case 'completed':
        return tr('completed');
      case 'reviewed':
        return tr('reviewed');
      case 'pending':
        return tr('pending');
      case 'pending_review':
        return tr('pending_review');
      default:
        return tr('tracking');
    }
  }

  static Color getSourceColor(String? source) {
    switch (source) {
      case 'expert_review':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'reviewed':
        return Colors.green;
      case 'pending':
        return Colors.orangeAccent;
      case 'pending_review':
        return Colors.yellow;
      default:
        return Colors.blue;
    }
  }

  static String formatLabel(String label) {
    switch (label.toLowerCase()) {
      case 'backterial_blackspot':
        return 'Bacterial black spot';
      case 'powdery_mildew':
        return 'Powdery Mildew';
      case 'tip_burn':
        return 'Tip Burn';
      case 'healthy':
        return 'Healthy';
      case 'dieback':
        return 'Dieback';
      case 'anthracnose':
        return 'Anthracnose';
      default:
        return label.isNotEmpty
            ? label[0].toUpperCase() + label.substring(1)
            : 'Unknown';
    }
  }

  static List<Map<String, dynamic>> filterSessions(
    List<Map<String, dynamic>> sessions,
    int selectedRangeIndex, {
    DateTime? customStart,
    DateTime? customEnd,
    int? monthlyYear,
    int? monthlyMonth,
  }) {
    if (sessions.isEmpty) return [];
    final now = DateTime.now();

    // Index 0: Last 7 Days
    if (selectedRangeIndex == 0) {
      final startInclusive = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 6)); // 7 days inclusive
      final endInclusive = DateTime(now.year, now.month, now.day);
      return sessions.where((session) {
        final dateStr = session['date'];
        if (dateStr == null) return false;
        final parsed = DateTime.tryParse(dateStr);
        if (parsed == null) return false;
        final d = DateTime(parsed.year, parsed.month, parsed.day);
        return !d.isBefore(startInclusive) && !d.isAfter(endInclusive);
      }).toList();
    }

    // Index 1: Monthly (with month/year picker)
    if (selectedRangeIndex == 1) {
      if (monthlyYear != null && monthlyMonth != null) {
        final startInclusive = DateTime(monthlyYear, monthlyMonth, 1);
        final endInclusive = DateTime(monthlyYear, monthlyMonth + 1, 0);
        return sessions.where((session) {
          final dateStr = session['date'];
          if (dateStr == null) return false;
          final parsed = DateTime.tryParse(dateStr);
          if (parsed == null) return false;
          final d = DateTime(parsed.year, parsed.month, parsed.day);
          return !d.isBefore(startInclusive) && !d.isAfter(endInclusive);
        }).toList();
      }
      // If no month/year selected, show all
      return List<Map<String, dynamic>>.from(sessions);
    }

    // Index 2: Custom range
    if (selectedRangeIndex == 2) {
      if (customStart == null || customEnd == null) {
        return List<Map<String, dynamic>>.from(sessions);
      }
      final startInclusive = DateTime(
        customStart.year,
        customStart.month,
        customStart.day,
      );
      final endInclusive = DateTime(
        customEnd.year,
        customEnd.month,
        customEnd.day,
      );
      return sessions.where((session) {
        final dateStr = session['date'];
        if (dateStr == null) return false;
        final parsed = DateTime.tryParse(dateStr);
        if (parsed == null) return false;
        final d = DateTime(parsed.year, parsed.month, parsed.day);
        return !d.isBefore(startInclusive) && !d.isAfter(endInclusive);
      }).toList();
    }

    // Default: show all
    return List<Map<String, dynamic>>.from(sessions);
  }

  static Map<String, Map<String, int>> monthlyHealthyAndDiseases(
    List<Map<String, dynamic>> scans,
  ) {
    final Map<String, Map<String, int>> result = {};
    for (final scan in scans) {
      final date = scan['date'] ?? '';
      final label = (scan['disease'] ?? '').toLowerCase();
      if (date.isEmpty || label == 'tip_burn' || label == 'unknown') continue;
      final month = date.substring(0, 7); // 'YYYY-MM'
      result.putIfAbsent(
        month,
        () => {
          'healthy': 0,
          ...{for (var d in diseaseLabels) d: 0},
        },
      );
      if (label == 'healthy') {
        result[month]!['healthy'] = (result[month]!['healthy'] ?? 0) + 1;
      } else if (isRealDisease(label)) {
        result[month]![label] = (result[month]![label] ?? 0) + 1;
      }
    }
    return result;
  }

  static Map<String, int> overallHealthyAndDiseases(
    List<Map<String, dynamic>> scans,
  ) {
    final Map<String, int> result = {
      'healthy': 0,
      ...{for (var d in diseaseLabels) d: 0},
    };
    for (final scan in scans) {
      final label = (scan['disease'] ?? '').toLowerCase();
      if (label == 'tip_burn' || label == 'unknown') continue;
      if (label == 'healthy') {
        result['healthy'] = (result['healthy'] ?? 0) + 1;
      } else if (isRealDisease(label)) {
        result[label] = (result[label] ?? 0) + 1;
      }
    }
    return result;
  }

  static List<Map<String, dynamic>> flattenScans(
    List<Map<String, dynamic>> sessions,
  ) {
    final List<Map<String, dynamic>> scans = [];
    for (final session in sessions) {
      final date = session['date'];
      final images = session['images'] as List? ?? [];
      for (final img in images) {
        final results = img['results'] as List? ?? [];
        for (final res in results) {
          scans.add({
            'disease': res['disease'],
            'confidence': res['confidence'],
            'date': date,
            'imagePath': img['imagePath'],
          });
        }
      }
    }
    return scans;
  }
}
