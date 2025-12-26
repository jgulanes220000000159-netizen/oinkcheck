import 'package:flutter/material.dart';
import '../shared/notifications_page.dart';

class ExpertNotificationsPage extends StatelessWidget {
  const ExpertNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return NotificationsPage(userRole: 'expert');
  }
}


