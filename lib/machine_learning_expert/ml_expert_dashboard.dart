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
            // --- Section: Quick actions (division with label) ---
            Text(
              'Quick actions',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 10),
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
            const Divider(height: 1, color: Colors.grey),
            const SizedBox(height: 16),
            // --- Section: What you can do (division with label) ---
            Text(
              'What you can do',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 10),
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
            const Divider(height: 1, color: Colors.grey),
            const SizedBox(height: 16),
            // --- Section: Model performance (division with label) ---
            Text(
              'Model performance',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 10),
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
        const SizedBox(height: 16),
        // Emphasized training curves: label + container + larger graphs
        Text(
          'Training curves',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ModelGraphCard(
                  title: 'YOLOv12',
                  slidePaths: [
                    'assets/MODEL_GRAPHS/YOLOTV.png',
                    'assets/MODEL_GRAPHS/YOLOMAP.png',
                    'assets/MODEL_GRAPHS/YOLOPR.png',
                    'assets/MODEL_GRAPHS/YOLO_GRAPH.png',
                  ],
                ),
                _ModelGraphCard(
                  title: 'Faster R-CNN',
                  slidePaths: [
                    'assets/MODEL_GRAPHS/FASTTV.png',
                    'assets/MODEL_GRAPHS/FASTMAP.png',
                    'assets/MODEL_GRAPHS/FASTPR.png',
                    'assets/MODEL_GRAPHS/FAST_R_GRAPH.png',
                  ],
                ),
                _ModelGraphCard(
                  title: 'SSD',
                  slidePaths: [
                    'assets/MODEL_GRAPHS/SSDTV.png',
                    'assets/MODEL_GRAPHS/SSDMAP.png',
                    'assets/MODEL_GRAPHS/SSDPR.png',
                    'assets/MODEL_GRAPHS/SSD_GRAPH.png',
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
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
                    const boldStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.bold);
                    return DataRow(
                      cells: [
                        DataCell(Text('#$rank')),
                        DataCell(modelWidget),
                        DataCell(Text(r.precision.toStringAsFixed(4), style: boldStyle)),
                        DataCell(Text(r.recall.toStringAsFixed(4), style: boldStyle)),
                        DataCell(Text(r.f1.toStringAsFixed(4), style: boldStyle)),
                        DataCell(Text(r.map50.toStringAsFixed(4), style: boldStyle)),
                        DataCell(Text(r.map75.toStringAsFixed(4), style: boldStyle)),
                      ],
                    );
                  }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        RichText(
          text: TextSpan(
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.normal,
            ),
            children: [
              const TextSpan(text: 'Overall, YOLOv12 achieved the strongest detection performance, with the highest '),
              TextSpan(text: 'precision (0.9103), recall (0.8773), F1 score (0.8935)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[800])),
              const TextSpan(text: ' and mAP scores. Faster R-CNN performs second best and SSD trails behind, which is consistent with the more modern architecture and capacity of YOLOv12 on this dataset.'),
            ],
          ),
        ),
      ],
    );
  }
}

/// Slide labels for the 4 graphs: Train/Val, mAP, Precision/Recall, Overview.
const List<String> _kGraphSlideLabels = [
  'Train & validation loss',
  'Mean average precision (mAP)',
  'Precision & recall',
  'Overview (all metrics)',
];

class _ModelGraphCard extends StatelessWidget {
  const _ModelGraphCard({
    required this.title,
    required this.slidePaths,
  });

  final String title;
  /// Four image paths: [TV, MAP, PR, composite]
  final List<String> slidePaths;

  @override
  Widget build(BuildContext context) {
    // Front view: show mAP graph (slide 2) for each model
    final thumbnailPath = slidePaths.length >= 2 ? slidePaths[1] : slidePaths.first;
    return Container(
      width: 300,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Icon(Icons.open_in_full, size: 16, color: Colors.black54),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _ModelGraphSlidesPage(
                    title: title,
                    slidePaths: slidePaths,
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
                aspectRatio: 3 / 2,
                child: Image.asset(thumbnailPath, fit: BoxFit.cover),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelGraphSlidesPage extends StatefulWidget {
  const _ModelGraphSlidesPage({
    required this.title,
    required this.slidePaths,
  });

  final String title;
  final List<String> slidePaths;

  @override
  State<_ModelGraphSlidesPage> createState() => _ModelGraphSlidesPageState();
}

class _ModelGraphSlidesPageState extends State<_ModelGraphSlidesPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paths = widget.slidePaths;
    final count = paths.length;
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemCount: count,
              itemBuilder: (context, index) {
                final path = paths[index];
                final label = index < _kGraphSlideLabels.length
                    ? _kGraphSlideLabels[index]
                    : '${index + 1} of $count';
                final isLastSlide = index == count - 1;
                return GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _ModelGraphFullScreenPage(
                          title: '${widget.title} – $label',
                          assetPath: path,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: isLastSlide
                              ? InteractiveViewer(
                                  minScale: 0.5,
                                  maxScale: 4,
                                  child: RotatedBox(
                                    quarterTurns: 1,
                                    child: Image.asset(path, fit: BoxFit.contain),
                                  ),
                                )
                              : Image.asset(path, fit: BoxFit.contain),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 24, top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${_currentPage + 1} of $count',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(width: 16),
                ...List.generate(count, (i) {
                  final selected = i == _currentPage;
                  return GestureDetector(
                    onTap: () => _pageController.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: selected ? 10 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? Colors.white : Colors.white38,
                      ),
                    ),
                  );
                }),
              ],
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
