import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'notification_service.dart';
import 'notification_model.dart';
import 'report_seen_helper.dart';
import '../user/user_request_detail.dart';
import '../expert/scan_request_detail.dart';

/// Shared notifications page widget
class NotificationsPage extends StatefulWidget {
  final String userRole; // 'farmer', 'expert', 'head_veterinarian'

  const NotificationsPage({
    super.key,
    required this.userRole,
  });

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<NotificationModel> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _subscribeToNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    final notifications = await NotificationService.getNotifications();
    setState(() {
      _notifications = notifications;
      _isLoading = false;
    });
  }

  void _subscribeToNotifications() {
    NotificationService.watchNotifications().listen((notifications) {
      if (mounted) {
        setState(() {
          _notifications = notifications;
        });
      }
    });
  }

  Future<void> _handleNotificationTap(NotificationModel notification) async {
    // Mark as read
    if (!notification.isRead) {
      await NotificationService.markAsRead(notification.id);
      // Update local state immediately
      setState(() {
        final index = _notifications.indexWhere((n) => n.id == notification.id);
        if (index != -1) {
          _notifications[index] = notification.copyWith(
            isRead: true,
            readAt: DateTime.now(),
          );
        }
      });
      // Force refresh to ensure Firestore updates are reflected
      await _loadNotifications();
    }

    // Navigate based on notification type
    final data = notification.data ?? {};
    final requestId = data['requestId'] as String?;

    if (requestId == null) {
      // No navigation needed
      return;
    }

    if (notification.type == 'scan_request_completed') {
      // Farmer: Navigate to completed report detail
      if (widget.userRole == 'farmer') {
        try {
          // Mark as seen before navigating
          await ReportSeenHelper.markCompletedReportSeen(requestId);
          
          final doc = await FirebaseFirestore.instance
              .collection('scan_requests')
              .doc(requestId)
              .get();
          
          if (doc.exists) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UserRequestDetail(
                  request: {'id': doc.id, ...doc.data()!},
                ),
              ),
            );
          }
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading report: $e')),
          );
        }
      }
    } else if (notification.type == 'scan_request_created') {
      // Expert/Head Vet: Navigate to pending report detail
      if (widget.userRole == 'expert' || widget.userRole == 'head_veterinarian') {
        try {
          // Mark as seen before navigating
          await ReportSeenHelper.markPendingReportSeen(requestId);
          
          final doc = await FirebaseFirestore.instance
              .collection('scan_requests')
              .doc(requestId)
              .get();
          
          if (doc.exists) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ScanRequestDetail(
                  request: {'id': doc.id, ...doc.data()!},
                ),
              ),
            );
          }
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading report: $e')),
          );
        }
      }
    }
  }

  Future<void> _markAllAsRead() async {
    for (final notification in _notifications) {
      if (!notification.isRead) {
        await NotificationService.markAsRead(notification.id);
      }
    }
    await _loadNotifications();
    // Force refresh to ensure stream updates
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    await NotificationService.deleteNotification(notificationId);
    await _loadNotifications();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        title: const Text('Notifications'),
        actions: [
          if (_notifications.any((n) => !n.isRead))
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text(
                'Mark all as read',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No notifications yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You\'ll see notifications here when you receive them.',
                        style: TextStyle(color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final notification = _notifications[index];
                      return _buildNotificationCard(notification);
                    },
                  ),
                ),
    );
  }

  Widget _buildNotificationCard(NotificationModel notification) {
    final isRead = notification.isRead;
    final timeAgo = _getTimeAgo(notification.createdAt);

    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _deleteNotification(notification.id),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: isRead ? Colors.white : Colors.blue[50],
        child: InkWell(
          onTap: () => _handleNotificationTap(notification),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon based on notification type
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getIconColor(notification.type).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getIcon(notification.type),
                    color: _getIconColor(notification.type),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                // Notification content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          if (!isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.body,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'scan_request_completed':
        return Icons.check_circle;
      case 'scan_request_created':
        return Icons.assignment;
      case 'treatment_approved':
        return Icons.verified;
      default:
        return Icons.notifications;
    }
  }

  Color _getIconColor(String type) {
    switch (type) {
      case 'scan_request_completed':
        return Colors.green;
      case 'scan_request_created':
        return Colors.orange;
      case 'treatment_approved':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return DateFormat('MMM d, y').format(dateTime);
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

