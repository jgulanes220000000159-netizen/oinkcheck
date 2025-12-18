import 'package:flutter/material.dart';
// fl_chart is not used directly here; charts are built in TrackingPage
import 'package:intl/intl.dart';
import 'tracking_models.dart';

class TrackingChart {
  // Helper to get the start date for the selected range
  static DateTime rangeStartDate(
    int selectedRangeIndex, {
    DateTime? customStart,
  }) {
    final days = TrackingModels.timeRanges[selectedRangeIndex]['days'] as int?;
    if (days == null) {
      // Custom: use provided start or fallback far past
      return customStart != null
          ? DateTime(customStart.year, customStart.month, customStart.day)
          : DateTime(1970);
    }
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));
  }

  // Group scans for charting based on selected range
  static List<String> chartWeekLabels(int weeks) {
    return List.generate(weeks, (i) => 'W${i + 1}');
  }

  // Helper to get the last 12 months ending with the current month
  static List<String> last12Months(DateTime now) {
    return List.generate(12, (i) {
      final d = DateTime(now.year, now.month - 11 + i, 1);
      return DateFormat('yyyy-MM').format(d);
    });
  }

  // Aggregate chart data for the selected range
  static List<Map<String, dynamic>> chartData(
    List<Map<String, dynamic>> scans,
    int selectedRangeIndex, {
    DateTime? customStart,
    DateTime? customEnd,
    int? monthlyYear,
    int? monthlyMonth,
  }) {
    final start = rangeStartDate(selectedRangeIndex, customStart: customStart);
    // Last 7 days (index 0): group by day
    if (selectedRangeIndex == 0) {
      final groups = List.generate(7, (i) {
        final d = start.add(Duration(days: i));
        return DateFormat('yyyy-MM-dd').format(d);
      });
      final Map<String, Map<String, int>> data = {
        for (final g in groups)
          g: {
            'healthy': 0,
            ...{for (var d in TrackingModels.diseaseLabels) d: 0},
          },
      };
      for (final scan in scans) {
        final label = (scan['disease'] ?? '').toLowerCase();
        if (label == 'tip_burn' || label == 'unknown') continue;
        final dateStr = scan['date'];
        if (dateStr == null) continue;
        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;
        final groupKey = DateFormat('yyyy-MM-dd').format(date);
        if (!data.containsKey(groupKey)) continue;
        if (label == 'healthy') {
          data[groupKey]!['healthy'] = (data[groupKey]!['healthy'] ?? 0) + 1;
        } else if (TrackingModels.isRealDisease(label)) {
          data[groupKey]![label] = (data[groupKey]![label] ?? 0) + 1;
        }
      }
      return groups.map((g) => {'group': g, ...data[g]!}).toList();
    }
    // Monthly (index 1): group by day within the selected month
    if (selectedRangeIndex == 1 &&
        monthlyYear != null &&
        monthlyMonth != null) {
      final startOfMonth = DateTime(monthlyYear, monthlyMonth, 1);
      final endOfMonth = DateTime(monthlyYear, monthlyMonth + 1, 0);
      final daysInMonth = endOfMonth.day;

      final groups = List.generate(daysInMonth, (i) {
        final d = startOfMonth.add(Duration(days: i));
        return DateFormat('yyyy-MM-dd').format(d);
      });

      final Map<String, Map<String, int>> data = {
        for (final g in groups)
          g: {
            'healthy': 0,
            ...{for (var d in TrackingModels.diseaseLabels) d: 0},
          },
      };

      for (final scan in scans) {
        final label = (scan['disease'] ?? '').toLowerCase();
        if (label == 'tip_burn' || label == 'unknown') continue;
        final dateStr = scan['date'];
        if (dateStr == null) continue;
        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;
        final d = DateTime(date.year, date.month, date.day);
        if (d.isBefore(startOfMonth) || d.isAfter(endOfMonth)) continue;
        final groupKey = DateFormat('yyyy-MM-dd').format(d);
        if (!data.containsKey(groupKey)) continue;
        if (label == 'healthy') {
          data[groupKey]!['healthy'] = (data[groupKey]!['healthy'] ?? 0) + 1;
        } else if (TrackingModels.isRealDisease(label)) {
          data[groupKey]![label] = (data[groupKey]![label] ?? 0) + 1;
        }
      }
      return groups.map((g) => {'group': g, ...data[g]!}).toList();
    }

    // Custom range (index 2): adapt grouping by span
    if (selectedRangeIndex == 2) {
      if (customStart == null || customEnd == null) return [];
      final startDay = DateTime(
        customStart.year,
        customStart.month,
        customStart.day,
      );
      final endDay = DateTime(customEnd.year, customEnd.month, customEnd.day);
      final totalDays = endDay.difference(startDay).inDays + 1;

      // <= 31 days: group by day
      if (totalDays <= 31) {
        final groups = List.generate(totalDays, (i) {
          final d = startDay.add(Duration(days: i));
          return DateFormat('yyyy-MM-dd').format(d);
        });
        final Map<String, Map<String, int>> data = {
          for (final g in groups)
            g: {
              'healthy': 0,
              ...{for (var d in TrackingModels.diseaseLabels) d: 0},
            },
        };
        for (final scan in scans) {
          final label = (scan['disease'] ?? '').toLowerCase();
          if (label == 'tip_burn' || label == 'unknown') continue;
          final dateStr = scan['date'];
          if (dateStr == null) continue;
          final date = DateTime.tryParse(dateStr);
          if (date == null) continue;
          final d = DateTime(date.year, date.month, date.day);
          if (d.isBefore(startDay) || d.isAfter(endDay)) continue;
          final groupKey = DateFormat('yyyy-MM-dd').format(d);
          if (!data.containsKey(groupKey)) continue;
          if (label == 'healthy') {
            data[groupKey]!['healthy'] = (data[groupKey]!['healthy'] ?? 0) + 1;
          } else if (TrackingModels.isRealDisease(label)) {
            data[groupKey]![label] = (data[groupKey]![label] ?? 0) + 1;
          }
        }
        return groups.map((g) => {'group': g, ...data[g]!}).toList();
      }

      // <= 180 days: group by week from start
      if (totalDays <= 180) {
        final weeks = (totalDays / 7).ceil();
        final weekLabels = chartWeekLabels(weeks);
        final List<Map<String, dynamic>> out = List.generate(
          weekLabels.length,
          (i) => {
            'group': weekLabels[i],
            'healthy': 0,
            ...{for (var d in TrackingModels.diseaseLabels) d: 0},
          },
        );
        for (final scan in scans) {
          final label = (scan['disease'] ?? '').toLowerCase();
          if (label == 'tip_burn' || label == 'unknown') continue;
          final dateStr = scan['date'];
          if (dateStr == null) continue;
          final date = DateTime.tryParse(dateStr);
          if (date == null) continue;
          final d = DateTime(date.year, date.month, date.day);
          if (d.isBefore(startDay) || d.isAfter(endDay)) continue;
          final weekIndex = ((d.difference(startDay).inDays) / 7).floor();
          if (weekIndex < 0 || weekIndex >= weekLabels.length) continue;
          if (label == 'healthy') {
            out[weekIndex]['healthy'] = (out[weekIndex]['healthy'] as int) + 1;
          } else if (TrackingModels.isRealDisease(label)) {
            out[weekIndex][label] = (out[weekIndex][label] as int) + 1;
          }
        }
        return out;
      }

      // > 180 days: group by month
      final months = <String>[];
      DateTime d = DateTime(startDay.year, startDay.month, 1);
      while (!d.isAfter(DateTime(endDay.year, endDay.month, 1))) {
        months.add(DateFormat('yyyy-MM').format(d));
        d = DateTime(d.year, d.month + 1, 1);
      }
      final Map<String, Map<String, int>> data = {
        for (final m in months)
          m: {
            'healthy': 0,
            ...{for (var dd in TrackingModels.diseaseLabels) dd: 0},
          },
      };
      for (final scan in scans) {
        final label = (scan['disease'] ?? '').toLowerCase();
        if (label == 'tip_burn' || label == 'unknown') continue;
        final dateStr = scan['date'];
        if (dateStr == null) continue;
        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;
        final dd = DateTime(date.year, date.month, date.day);
        if (dd.isBefore(startDay) || dd.isAfter(endDay)) continue;
        final groupKey = DateFormat('yyyy-MM').format(dd);
        if (!data.containsKey(groupKey)) continue;
        if (label == 'healthy') {
          data[groupKey]!['healthy'] = (data[groupKey]!['healthy'] ?? 0) + 1;
        } else if (TrackingModels.isRealDisease(label)) {
          data[groupKey]![label] = (data[groupKey]![label] ?? 0) + 1;
        }
      }
      return months.map((m) => {'group': m, ...data[m]!}).toList();
    }
    // fallback
    return [];
  }

  // Percentage-based, fixed-bin aggregation (default 6 bins) across the selected range.
  // Each bin outputs per-disease percentages relative to total diseased counts
  // (excludes healthy, tip_burn, and unknown). The label is the midpoint date (MM-dd).
  static List<Map<String, dynamic>> chartDataPercentBinned(
    List<Map<String, dynamic>> scans,
    int selectedRangeIndex, {
    DateTime? customStart,
    DateTime? customEnd,
    int? monthlyYear,
    int? monthlyMonth,
    int bins = 6,
  }) {
    if (bins <= 0) return [];

    DateTime startDay;
    DateTime endDay;
    final now = DateTime.now();

    if (selectedRangeIndex == 0) {
      startDay = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 6));
      endDay = DateTime(now.year, now.month, now.day);
    } else if (selectedRangeIndex == 1) {
      if (monthlyYear != null && monthlyMonth != null) {
        startDay = DateTime(monthlyYear, monthlyMonth, 1);
        endDay = DateTime(monthlyYear, monthlyMonth + 1, 0);
      } else {
        startDay = DateTime(now.year, now.month, 1);
        endDay = DateTime(now.year, now.month + 1, 0);
      }
    } else {
      if (customStart != null && customEnd != null) {
        startDay = DateTime(customStart.year, customStart.month, customStart.day);
        endDay = DateTime(customEnd.year, customEnd.month, customEnd.day);
      } else {
        endDay = DateTime(now.year, now.month, now.day);
        startDay = endDay.subtract(const Duration(days: 29));
      }
    }

    if (endDay.isBefore(startDay)) {
      final tmp = startDay;
      startDay = endDay;
      endDay = tmp;
    }

    final totalDays = endDay.difference(startDay).inDays + 1;
    if (totalDays <= 0) return [];

    // Create bin boundaries
    final List<DateTime> boundaries = List.generate(bins + 1, (i) {
      final dayOffset = (totalDays * i / bins).floor();
      final d = startDay.add(Duration(days: dayOffset));
      return DateTime(d.year, d.month, d.day);
    });
    // Ensure the last boundary is strictly after endDay
    boundaries[boundaries.length - 1] = endDay.add(const Duration(days: 1));

    // Initialize counts per bin (include healthy)
    final List<Map<String, num>> binCounts = List.generate(
      bins,
      (_) => {
        'healthy': 0,
        for (final d in TrackingModels.diseaseLabels) d: 0,
      },
    );

    for (final scan in scans) {
      final label = (scan["disease"] ?? '').toLowerCase();
      // We count healthy and real diseases; skip tip_burn/unknown
      if (label != 'healthy' && !TrackingModels.isRealDisease(label)) continue;
      final dateStr = scan['date'];
      if (dateStr == null) continue;
      final parsed = DateTime.tryParse(dateStr);
      if (parsed == null) continue;
      final d = DateTime(parsed.year, parsed.month, parsed.day);
      if (d.isBefore(startDay) || d.isAfter(endDay)) continue;

      int idx = -1;
      for (int i = 0; i < bins; i++) {
        if (!d.isBefore(boundaries[i]) && d.isBefore(boundaries[i + 1])) {
          idx = i;
          break;
        }
      }
      if (idx == -1) continue;
      binCounts[idx][label] = (binCounts[idx][label] ?? 0) + 1;
    }

    final List<Map<String, dynamic>> out = [];
    for (int i = 0; i < bins; i++) {
      final binStart = boundaries[i];
      final binEndExclusive = boundaries[i + 1];
      final binEnd = binEndExclusive.subtract(const Duration(days: 1));
      final midMillis = (binStart.millisecondsSinceEpoch + binEnd.millisecondsSinceEpoch) ~/ 2;
      final mid = DateTime.fromMillisecondsSinceEpoch(midMillis);
      final label = DateFormat('MM-dd').format(mid);

      final totalDiseased = TrackingModels.diseaseLabels
          .map((d) => binCounts[i][d] as num)
          .fold<num>(0, (a, b) => a + b);
      final totalAll = (binCounts[i]['healthy'] as num) + totalDiseased;
      final denom = totalAll == 0 ? 1 : totalAll;

      final Map<String, double> binPercents = {
        'healthy': ((binCounts[i]['healthy'] as num) * 100.0 / denom)
            .toDouble(),
        for (final d in TrackingModels.diseaseLabels)
          d: ((binCounts[i][d] as num) * 100.0 / denom).toDouble(),
      };

      out.add({'group': label, ...binPercents});
    }

    return out;
  }

  static Widget buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          color: color,
          margin: const EdgeInsets.only(right: 4),
        ),
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 12),
      ],
    );
  }
}
