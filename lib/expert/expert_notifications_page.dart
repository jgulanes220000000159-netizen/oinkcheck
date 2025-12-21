import 'package:flutter/material.dart';

class ExpertNotificationsPage extends StatelessWidget {
  const ExpertNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        title: const Text('Notifications'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_none, size: 56, color: Colors.grey[600]),
              const SizedBox(height: 12),
              const Text(
                'No notifications yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'This page is reserved for future push notifications (e.g., new farmer submissions).',
                style: TextStyle(color: Colors.grey[700], height: 1.3),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


