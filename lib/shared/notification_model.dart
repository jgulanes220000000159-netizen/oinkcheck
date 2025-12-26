import 'package:cloud_firestore/cloud_firestore.dart';

/// Notification model for storing both locally (Hive) and in Firestore
class NotificationModel {
  final String id;
  final String userId; // Who should receive this notification
  final String type; // e.g., 'scan_reviewed', 'scan_request_created', 'treatment_approved'
  final String title;
  final String body;
  final Map<String, dynamic>? data; // Additional data like requestId, expertName, etc.
  final bool isRead;
  final DateTime createdAt;
  final DateTime? readAt;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.data,
    this.isRead = false,
    required this.createdAt,
    this.readAt,
  });

  /// Convert to Map for Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'userId': userId,
      'type': type,
      'title': title,
      'body': body,
      'data': data ?? {},
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
      'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
    };
  }

  /// Convert to Map for Hive (local storage)
  Map<String, dynamic> toHive() {
    return {
      'id': id,
      'userId': userId,
      'type': type,
      'title': title,
      'body': body,
      'data': data ?? {},
      'isRead': isRead,
      'createdAt': createdAt.toIso8601String(),
      'readAt': readAt?.toIso8601String(),
    };
  }

  /// Create from Firestore document
  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Handle createdAt - could be Timestamp or already a DateTime
    DateTime createdAt;
    if (data['createdAt'] is Timestamp) {
      createdAt = (data['createdAt'] as Timestamp).toDate();
    } else if (data['createdAt'] is DateTime) {
      createdAt = data['createdAt'] as DateTime;
    } else {
      createdAt = DateTime.now();
    }
    
    // Handle readAt
    DateTime? readAt;
    if (data['readAt'] is Timestamp) {
      readAt = (data['readAt'] as Timestamp).toDate();
    } else if (data['readAt'] is DateTime) {
      readAt = data['readAt'] as DateTime;
    }
    
    return NotificationModel(
      id: data['id'] as String? ?? doc.id,
      userId: data['userId']?.toString() ?? '',
      type: data['type']?.toString() ?? '',
      title: data['title']?.toString() ?? '',
      body: data['body']?.toString() ?? '',
      data: data['data'] is Map ? Map<String, dynamic>.from(data['data'] as Map) : null,
      isRead: data['isRead'] == true,
      createdAt: createdAt,
      readAt: readAt,
    );
  }

  /// Create from Hive map
  factory NotificationModel.fromHive(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      type: map['type'] ?? '',
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      data: map['data'] as Map<String, dynamic>?,
      isRead: map['isRead'] ?? false,
      createdAt: DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
      readAt: map['readAt'] != null ? DateTime.parse(map['readAt']) : null,
    );
  }

  /// Create a copy with updated read status
  NotificationModel copyWith({
    bool? isRead,
    DateTime? readAt,
  }) {
    return NotificationModel(
      id: id,
      userId: userId,
      type: type,
      title: title,
      body: body,
      data: data,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      readAt: readAt ?? this.readAt,
    );
  }
}

