import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'notification_model.dart';

/// Service for managing notifications (Firestore + local Hive storage)
class NotificationService {
  static const String _hiveBoxName = 'notificationsBox';
  static const String _firestoreCollection = 'notifications';

  /// Save notification to both Firestore and local storage
  static Future<void> saveNotification(NotificationModel notification) async {
    try {
      // Save to Firestore
      await FirebaseFirestore.instance
          .collection(_firestoreCollection)
          .doc(notification.id)
          .set(notification.toFirestore());

      // Save to local Hive storage
      final box = await Hive.openBox(_hiveBoxName);
      final notifications = box.get('notifications', defaultValue: <Map<String, dynamic>>[]) as List;
      final notificationsList = notifications.map((e) => Map<String, dynamic>.from(e)).toList();
      
      // Remove existing notification with same ID if present
      notificationsList.removeWhere((n) => n['id'] == notification.id);
      
      // Add new notification
      notificationsList.add(notification.toHive());
      
      // Sort by createdAt descending (newest first)
      notificationsList.sort((a, b) {
        final aTime = DateTime.parse(a['createdAt'] ?? '');
        final bTime = DateTime.parse(b['createdAt'] ?? '');
        return bTime.compareTo(aTime);
      });
      
      // Keep only last 100 notifications locally
      if (notificationsList.length > 100) {
        notificationsList.removeRange(100, notificationsList.length);
      }
      
      await box.put('notifications', notificationsList);
    } catch (e) {
      print('Error saving notification: $e');
    }
  }

  /// Get all notifications for current user (from local storage first, then sync with Firestore)
  static Future<List<NotificationModel>> getNotifications() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return [];

      // Sync with Firestore first to get latest data
      await _syncWithFirestore(user.uid);

      // Load from local storage (which should now be synced)
      final box = await Hive.openBox(_hiveBoxName);
      final notifications = box.get('notifications', defaultValue: <Map<String, dynamic>>[]) as List;
      final localNotifications = notifications
          .map((e) {
            try {
              return NotificationModel.fromHive(Map<String, dynamic>.from(e));
            } catch (err) {
              print('Error parsing notification: $err');
              return null;
            }
          })
          .whereType<NotificationModel>()
          .where((n) => n.userId == user.uid)
          .toList();

      // Sort by createdAt descending (newest first)
      localNotifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return localNotifications;
    } catch (e) {
      print('Error getting notifications: $e');
      return [];
    }
  }

  /// Sync local notifications with Firestore
  static Future<void> _syncWithFirestore(String userId) async {
    try {
      print('Syncing notifications for user: $userId');
      // Fetch from Firestore (without orderBy to avoid index requirement)
      final snapshot = await FirebaseFirestore.instance
          .collection(_firestoreCollection)
          .where('userId', isEqualTo: userId)
          .limit(100)
          .get();

      print('Found ${snapshot.docs.length} notifications in Firestore');

      final firestoreNotifications = snapshot.docs
          .map((doc) {
            try {
              return NotificationModel.fromFirestore(doc);
            } catch (e) {
              print('Error parsing notification ${doc.id}: $e');
              return null;
            }
          })
          .whereType<NotificationModel>()
          .toList();

      print('Parsed ${firestoreNotifications.length} notifications');

      // Sort by createdAt descending (newest first)
      firestoreNotifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Update local storage
      final box = await Hive.openBox(_hiveBoxName);
      final notificationsList = firestoreNotifications.map((n) => n.toHive()).toList();
      await box.put('notifications', notificationsList);
      print('Saved ${notificationsList.length} notifications to local storage');
    } catch (e) {
      print('Error syncing notifications: $e');
      // If sync fails, at least return what we have locally
    }
  }

  /// Mark notification as read
  static Future<void> markAsRead(String notificationId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Update local storage first for immediate UI update
      final box = await Hive.openBox(_hiveBoxName);
      final notifications = box.get('notifications', defaultValue: <Map<String, dynamic>>[]) as List;
      final notificationsList = notifications.map((e) => Map<String, dynamic>.from(e)).toList();
      
      final index = notificationsList.indexWhere((n) => n['id'] == notificationId);
      if (index != -1) {
        notificationsList[index]['isRead'] = true;
        notificationsList[index]['readAt'] = DateTime.now().toIso8601String();
        await box.put('notifications', notificationsList);
      }

      // Update Firestore (this will trigger the stream update)
      await FirebaseFirestore.instance
          .collection(_firestoreCollection)
          .doc(notificationId)
          .update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  /// Get unread count
  static Future<int> getUnreadCount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 0;

      // Check local storage first
      final box = await Hive.openBox(_hiveBoxName);
      final notifications = box.get('notifications', defaultValue: <Map<String, dynamic>>[]) as List;
      final unreadCount = notifications
          .map((e) => NotificationModel.fromHive(Map<String, dynamic>.from(e)))
          .where((n) => n.userId == user.uid && !n.isRead)
          .length;

      return unreadCount;
    } catch (e) {
      print('Error getting unread count: $e');
      return 0;
    }
  }

  /// Stream notifications for real-time updates
  static Stream<List<NotificationModel>> watchNotifications() {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return Stream.value([]);

      return FirebaseFirestore.instance
          .collection(_firestoreCollection)
          .where('userId', isEqualTo: user.uid)
          .limit(100)
          .snapshots()
          .map((snapshot) {
        final notifications = snapshot.docs
            .map((doc) {
              try {
                return NotificationModel.fromFirestore(doc);
              } catch (e) {
                print('Error parsing notification from Firestore: $e');
                return null;
              }
            })
            .whereType<NotificationModel>()
            .toList();

        // Sort by createdAt descending (newest first)
        notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        // Update local storage in background
        _updateLocalStorage(notifications);

        return notifications;
      }).handleError((error) {
        print('Error in watchNotifications stream: $error');
        // Fallback to local storage on error
        return _getLocalNotifications();
      });
    } catch (e) {
      print('Error watching notifications: $e');
      // Fallback to local storage
      return Stream.value(_getLocalNotifications());
    }
  }

  /// Get notifications from local storage only
  static List<NotificationModel> _getLocalNotifications() {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return [];

      final box = Hive.box(_hiveBoxName);
      final notifications = box.get('notifications', defaultValue: <Map<String, dynamic>>[]) as List;
      final localNotifications = notifications
          .map((e) {
            try {
              return NotificationModel.fromHive(Map<String, dynamic>.from(e));
            } catch (err) {
              return null;
            }
          })
          .whereType<NotificationModel>()
          .where((n) => n.userId == user.uid)
          .toList();

      localNotifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return localNotifications;
    } catch (e) {
      print('Error getting local notifications: $e');
      return [];
    }
  }

  /// Update local storage with Firestore data
  static Future<void> _updateLocalStorage(List<NotificationModel> notifications) async {
    try {
      final box = await Hive.openBox(_hiveBoxName);
      final notificationsList = notifications.map((n) => n.toHive()).toList();
      await box.put('notifications', notificationsList);
    } catch (e) {
      print('Error updating local storage: $e');
    }
  }

  /// Delete notification
  static Future<void> deleteNotification(String notificationId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Delete from Firestore
      await FirebaseFirestore.instance
          .collection(_firestoreCollection)
          .doc(notificationId)
          .delete();

      // Delete from local storage
      final box = await Hive.openBox(_hiveBoxName);
      final notifications = box.get('notifications', defaultValue: <Map<String, dynamic>>[]) as List;
      final notificationsList = notifications.map((e) => Map<String, dynamic>.from(e)).toList();
      notificationsList.removeWhere((n) => n['id'] == notificationId);
      await box.put('notifications', notificationsList);
    } catch (e) {
      print('Error deleting notification: $e');
    }
  }
}

