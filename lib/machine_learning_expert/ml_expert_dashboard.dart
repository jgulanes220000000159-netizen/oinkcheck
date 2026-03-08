import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import 'ml_expert_scan_page.dart';
import 'ml_expert_completed_reports_page.dart';
import 'ml_expert_profile.dart';
import 'ml_expert_my_evaluations_page.dart';
import '../shared/profile_update_notifier.dart';

class MachineLearningExpertDashboard extends StatefulWidget {
  const MachineLearningExpertDashboard({super.key});

  @override
  State<MachineLearningExpertDashboard> createState() =>
      _MachineLearningExpertDashboardState();
}

class _MachineLearningExpertDashboardState
    extends State<MachineLearningExpertDashboard> {
  int _selectedIndex = 0;

  void goTo(int index) {
    setState(() => _selectedIndex = index);
  }

  List<Widget> get _pages => const [
    _MLExpertHomePage(),
    MLExpertScanPage(),
    MLExpertMyEvaluationsPage(),
    MLExpertCompletedReportsPage(),
    MLExpertProfilePage(),
  ];

  bool _canGoBack() => _selectedIndex != 0;

  String _firstName() {
    try {
      final profile = Hive.box('userBox').get('userProfile');
      final name =
          (profile is Map ? profile['fullName'] : null)?.toString() ?? '';
      if (name.trim().isEmpty) return 'ML';
      return name.trim().split(' ').first;
    } catch (_) {
      return 'ML';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showHeader =
        _selectedIndex != 4; // Profile page has its own header
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Column(
            children: [
              // Header (match app design language)
              if (showHeader)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: const BorderRadius.only(
                      bottomRight: Radius.circular(50),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ListenableBuilder(
                            listenable: ProfileUpdateNotifier.instance,
                            builder: (context, _) {
                              final name = _firstName();
                              return Text(
                                'Hello - $name',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                          GestureDetector(
                            // Pages: 0 Home, 1 Scan, 2 History, 3 Completed, 4 Profile
                            onTap: () => setState(() => _selectedIndex = 4),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.psychology_alt,
                                color: Colors.green,
                                size: 26,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.auto_awesome,
                              color: Colors.white70,
                              size: 18,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Machine Learning Expert Portal',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(child: _pages[_selectedIndex]),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          bottom: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F8F0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                if (_canGoBack())
                  InkWell(
                    onTap: () => setState(() => _selectedIndex = 0),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.arrow_back, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Back',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),
                const Spacer(),
                _NavIcon(
                  icon: Icons.home,
                  selected: _selectedIndex == 0,
                  onTap: () => setState(() => _selectedIndex = 0),
                ),
                const SizedBox(width: 10),
                _NavIcon(
                  icon: Icons.qr_code_scanner,
                  selected: _selectedIndex == 1,
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
                const SizedBox(width: 10),
                _NavIcon(
                  icon: Icons.history,
                  selected: _selectedIndex == 2,
                  onTap: () => setState(() => _selectedIndex = 2),
                ),
                const SizedBox(width: 10),
                _NavIcon(
                  icon: Icons.checklist,
                  selected: _selectedIndex == 3,
                  onTap: () => setState(() => _selectedIndex = 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? Colors.green : Colors.green.shade50;
    final fg = selected ? Colors.white : Colors.green;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: fg, size: 24),
      ),
    );
  }
}

class _MLExpertHomePage extends StatelessWidget {
  const _MLExpertHomePage();

  @override
  Widget build(BuildContext context) {
    final dash =
        context.findAncestorStateOfType<_MachineLearningExpertDashboardState>();
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            // Three equal-sized cards in a grid
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    title: 'Scan\nImages',
                    icon: Icons.qr_code_scanner,
                    color: Colors.green,
                    onTap: () => dash?.goTo(1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionCard(
                    title: 'Completed\nReports',
                    icon: Icons.check_circle_outline,
                    color: const Color(0xFF00BCD4),
                    onTap: () => dash?.goTo(3),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionCard(
                    title: 'My Scan\nHistory',
                    icon: Icons.history,
                    color: Colors.orange,
                    onTap: () => dash?.goTo(2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'What you can do',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bullet(
                    'Scan',
                    'Run the model and view bounding boxes (no expert review submission).',
                  ),
                  const SizedBox(height: 8),
                  _bullet(
                    'Rate',
                    'Rate the scan (1–5 stars) and leave a comment for later admin analysis.',
                  ),
                  const SizedBox(height: 8),
                  _bullet(
                    'Review completed reports',
                    'View all farmer reports already marked as completed.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const _ModelComparisonSection(),
          ],
        ),
      ),
    );
  }

  Widget _bullet(String title, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 5),
          decoration: const BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.black87, height: 1.25),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ModelPerformanceRow {
  _ModelPerformanceRow({
    required this.modelName,
    required this.trainLoss,
    required this.valLoss,
    required this.map50,
    required this.map75,
    required this.map,
    required this.precision,
    required this.recall,
    required this.f1,
  });

  final String modelName;
  final double trainLoss;
  final double valLoss;
  final double map50;
  final double map75;
  final double map;
  final double precision;
  final double recall;
  final double f1;
}

class _ModelComparisonSection extends StatelessWidget {
  const _ModelComparisonSection();

  List<_ModelPerformanceRow> get _rows => [
    _ModelPerformanceRow(
      modelName: 'SSD',
      trainLoss: 0.4965,
      valLoss: 1.9059,
      map50: 0.7232,
      map75: 0.4529, // used as mAP@0.5:0.95 in table
      map: 0.4529,
      precision: 0.6651,
      recall: 0.5020,
      f1: 0.5722,
    ),
    _ModelPerformanceRow(
      modelName: 'Faster R-CNN',
      trainLoss: 0.0384,
      valLoss: 0.1043,
      map50: 0.8010,
      map75: 0.5197, // used as mAP@0.5:0.95 in table
      map: 0.5197,
      precision: 0.8369,
      recall: 0.5529,
      f1: 0.6659,
    ),
    _ModelPerformanceRow(
      modelName: 'YOLOv12',
      trainLoss: 2.6604,
      valLoss: 3.3004,
      map50: 0.9333,
      map75: 0.6646, // mAP@0.5:0.95
      map: 0.6646,
      precision: 0.9103,
      recall: 0.8773,
      f1: 0.8935,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final rows = [..._rows]..sort((a, b) => b.f1.compareTo(a.f1));
    final bestF1 = rows.isNotEmpty ? rows.first.f1 : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Training metrics summary',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Best‑epoch training and validation metrics for the three object detection models '
          '(SSD, Faster R-CNN, YOLOv12). These values are taken from the highlighted rows in the '
          'training logs and summarise how each model performs on the validation set.',
          style: TextStyle(color: Colors.grey[700], fontSize: 13, height: 1.3),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _ModelGraphCard(
                title: 'YOLOv12',
                assetPath: 'assets/MODEL_GRAPHS/YOLO_GRAPH.png',
              ),
              _ModelGraphCard(
                title: 'Faster R-CNN',
                assetPath: 'assets/MODEL_GRAPHS/FAST_R_GRAPH.png',
              ),
              _ModelGraphCard(
                title: 'SSD',
                assetPath: 'assets/MODEL_GRAPHS/SSD_GRAPH.png',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 44,
              columnSpacing: 18,
              headingTextStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
              dataTextStyle: const TextStyle(fontSize: 12),
              columns: const [
                DataColumn(label: Text('Rank')),
                DataColumn(label: Text('Model')),
                DataColumn(label: Text('Precision')),
                DataColumn(label: Text('Recall')),
                DataColumn(label: Text('F1 score')),
                DataColumn(label: Text('mAP@0.5')),
                DataColumn(label: Text('mAP@0.5:0.95')),
              ],
              rows:
                  rows.asMap().entries.map((entry) {
                    final index = entry.key;
                    final r = entry.value;
                    final isBest = r.f1 == bestF1;
                    final rank = index + 1;
                    final modelWidget = Row(
                      children: [
                        Text(
                          r.modelName,
                          style: TextStyle(
                            fontWeight:
                                isBest ? FontWeight.w800 : FontWeight.w600,
                            color: isBest ? Colors.green[800] : Colors.black87,
                          ),
                        ),
                        if (isBest) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.emoji_events,
                            size: 14,
                            color: Colors.amber,
                          ),
                        ],
                      ],
                    );
                    return DataRow(
                      cells: [
                        DataCell(Text('#$rank')),
                        DataCell(modelWidget),
                        DataCell(Text(r.precision.toStringAsFixed(4))),
                        DataCell(Text(r.recall.toStringAsFixed(4))),
                        DataCell(Text(r.f1.toStringAsFixed(4))),
                        DataCell(Text(r.map50.toStringAsFixed(4))),
                        DataCell(Text(r.map75.toStringAsFixed(4))),
                      ],
                    );
                  }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Overall, YOLOv12 achieved the strongest detection performance, with the highest precision '
          '(0.9103 ), recall (0.8773 ), F1 score (0.8935) and mAP scores. Faster R-CNN performs '
          'second best and SSD trails behind, which is consistent with the more modern architecture '
          'and capacity of YOLOv12 on this dataset.',
          style: TextStyle(
            color: Colors.grey[700],
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _ModelGraphCard extends StatelessWidget {
  const _ModelGraphCard({required this.title, required this.assetPath});

  final String title;
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Icon(Icons.open_in_full, size: 14, color: Colors.black54),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder:
                      (_) => _ModelGraphFullScreenPage(
                        title: title,
                        assetPath: assetPath,
                      ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.asset(assetPath, fit: BoxFit.cover),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelGraphFullScreenPage extends StatelessWidget {
  const _ModelGraphFullScreenPage({
    required this.title,
    required this.assetPath,
  });

  final String title;
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: RotatedBox(
            quarterTurns: 1,
            child: Image.asset(assetPath, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 120, // Fixed height for all cards
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Colors.grey[800],
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
