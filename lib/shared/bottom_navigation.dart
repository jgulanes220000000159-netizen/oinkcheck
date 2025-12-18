import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../user/scan_page.dart';
import '../user/user_request_tabbed_list.dart';
import '../user/tracking_page.dart';
import '../user/profile_page.dart';
import '../shared/review_manager.dart';

class CustomBottomNavigation extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  final ReviewManager reviewManager;

  const CustomBottomNavigation({
    Key? key,
    required this.currentIndex,
    required this.onTap,
    required this.reviewManager,
  }) : super(key: key);

  @override
  _CustomBottomNavigationState createState() => _CustomBottomNavigationState();
}

class _CustomBottomNavigationState extends State<CustomBottomNavigation> {
  int get _pendingCount =>
      widget.reviewManager.pendingReviews
          .where((r) => r['status'] == 'pending')
          .length;

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: widget.currentIndex,
      onTap: widget.onTap,
      selectedItemColor: Colors.green,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      items: [
        BottomNavigationBarItem(
          icon: const Icon(Icons.dashboard),
          label: tr('dashboard'),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.local_florist),
          label: tr('diseases'),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.camera_alt),
          label: tr('scan'),
        ),
        BottomNavigationBarItem(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.list_alt, size: 28),
              if (_pendingCount > 0)
                Positioned(
                  right: -8,
                  top: -8,
                  child: Container(
                    padding: const EdgeInsets.all(0),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      border: Border.all(color: Colors.white, width: 2),
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    child: Center(
                      child: Text(
                        '$_pendingCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          label: tr('my_requests'),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.show_chart),
          label: tr('tracking'),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.person),
          label: tr('profile'),
        ),
      ],
    );
  }
}

// Helper class to manage navigation pages
class NavigationPages {
  static List<Widget> getPages() {
    return [
      // Dashboard - placeholder, will be replaced by actual dashboard content
      Container(),
      // Diseases - placeholder, will be replaced by actual diseases content
      Container(),
      // Scan
      const ScanPage(),
      // My Requests
      const UserRequestTabbedList(),
      // Tracking
      const TrackingPage(),
      // Profile
      const ProfilePage(),
    ];
  }
}
