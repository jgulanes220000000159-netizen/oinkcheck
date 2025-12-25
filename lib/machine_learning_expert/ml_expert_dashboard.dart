import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import 'ml_expert_scan_page.dart';
import 'ml_expert_completed_reports_page.dart';
import 'ml_expert_profile.dart';
import 'ml_expert_my_evaluations_page.dart';

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
      final name = (profile is Map ? profile['fullName'] : null)?.toString() ?? '';
      if (name.trim().isEmpty) return 'ML';
      return name.trim().split(' ').first;
    } catch (_) {
      return 'ML';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showHeader = _selectedIndex != 4; // Profile page has its own header
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
                          Text(
                            'Hello - ${_firstName()}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
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
                                border: Border.all(color: Colors.white, width: 2),
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
                            Icon(Icons.auto_awesome, color: Colors.white70, size: 18),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
      ],
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


