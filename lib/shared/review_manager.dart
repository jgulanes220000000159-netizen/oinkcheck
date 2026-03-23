import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';

class ReviewManager {
  static final ReviewManager _instance = ReviewManager._internal();
  factory ReviewManager() => _instance;
  ReviewManager._internal() {
    _loadFromHive();
  }

  final List<Map<String, dynamic>> _pendingReviews = [
    // Pending review sample
    {
      'id': 'review_001',
      'userId': 'user_001',
      'userName': 'John Doe',
      'status': 'pending',
      'submittedAt': '2024-06-20T10:00:00',
      'images': [
        {'path': 'assets/sample1.jpg', 'detections': []},
      ],
      'diseaseSummary': [
        {'disease': 'Ringworm', 'averageConfidence': 0.92},
      ],
      'notes': 'Raised circular skin lesions noted on the flank.',
    },
    // Completed review sample
    {
      'id': 'review_002',
      'userId': 'user_002',
      'userName': 'Jane Smith',
      'status': 'reviewed',
      'submittedAt': '2024-06-19T14:30:00',
      'images': [
        {'path': 'assets/sample2.jpg', 'detections': []},
      ],
      'diseaseSummary': [
        {'disease': 'Greasy Pig Disease', 'averageConfidence': 0.85},
      ],
      'notes': 'Greasy, darkened patches along the back.',
      'expertReview': {
        'comment':
            'Consistent with greasy pig disease. Recommend cleaning and topical care per farm SOP; involve a veterinarian for prescription treatment.',
        'severityAssessment': {
          'level': 'medium',
          'confidence': 0.85,
          'notes': 'Expert assessment based on image analysis',
        },
        'treatmentPlan': {
          'recommendations': [
            {
              'treatment':
                  'Gentle washing with vet-directed antiseptic shampoo',
              'dosage': 'Per product label',
              'frequency': 'As advised until skin improves',
              'precautions': 'Avoid harsh scrubbing; dry the pig thoroughly',
            },
          ],
          'preventiveMeasures': [
            'Improve pen hygiene and drainage',
            'Separate severely affected animals if advised',
            'Review nutrition with a veterinarian',
          ],
        },
        'reviewedAt': '2024-06-20T12:00:00',
      },
    },
    // Completed review for Maria Santos
    {
      'id': 'review_003',
      'userId': 'user_003',
      'userName': 'Maria Santos',
      'status': 'reviewed',
      'submittedAt': '2024-06-10T09:15:00',
      'images': [
        {'path': 'assets/sample3.jpg', 'detections': []},
      ],
      'diseaseSummary': [
        {'disease': 'Mange', 'averageConfidence': 0.88},
      ],
      'notes': 'Intense scratching and patchy hair loss.',
      'expertReview': {
        'comment':
            'Signs suggest mange. Veterinary diagnosis and acaricide treatment are recommended.',
        'severityAssessment': {
          'level': 'medium',
          'confidence': 0.88,
          'notes': 'Expert assessment based on image analysis',
        },
        'treatmentPlan': {
          'recommendations': [
            {
              'treatment': 'Veterinary-prescribed acaricide protocol',
              'dosage': 'Per veterinarian',
              'frequency': 'Per treatment protocol',
              'precautions':
                  'Observe withdrawal periods for food-producing pigs',
            },
          ],
          'preventiveMeasures': [
            'Treat in-contact pigs as directed',
            'Disinfect equipment and improve pen cleanliness',
            'Monitor the herd for new scratching or hair loss',
          ],
        },
        'reviewedAt': '2024-06-11T10:00:00',
      },
    },
  ];
  final _uuid = const Uuid();
  final String _boxName = 'reviews';

  Future<void> _loadFromHive() async {
    final box = Hive.box(_boxName);
    _pendingReviews.clear();
    for (var review in box.values) {
      _pendingReviews.add(Map<String, dynamic>.from(review));
    }
  }

  Future<void> submitForReview({
    required String userId,
    required List<String> imagePaths,
    required List<Map<String, dynamic>> detections,
    required List<Map<String, dynamic>> diseaseCounts,
    String? notes,
  }) async {
    final review = {
      'id': _uuid.v4(),
      'userId': userId,
      'userName': userId,
      'status': 'pending',
      'submittedAt': DateTime.now().toIso8601String(),
      'images':
          imagePaths
              .map(
                (path) => {
                  'path': path,
                  'detections':
                      detections.where((d) => d['imagePath'] == path).toList(),
                },
              )
              .toList(),
      'diseaseSummary': diseaseCounts,
      'notes': notes,
    };

    _pendingReviews.insert(0, review);
    final box = Hive.box(_boxName);
    await box.put(review['id'], review);
  }

  Future<void> updateReview({
    required String reviewId,
    required String status,
    Map<String, dynamic>? expertReview,
  }) async {
    final index = _pendingReviews.indexWhere(
      (review) => review['id'] == reviewId,
    );
    if (index != -1) {
      _pendingReviews[index]['status'] = status;
      if (expertReview != null) {
        _pendingReviews[index]['expertReview'] = expertReview;
      }
      final box = Hive.box(_boxName);
      await box.put(_pendingReviews[index]['id'], _pendingReviews[index]);
    }
  }

  Future<void> clearReviews() async {
    _pendingReviews.clear();
    final box = Hive.box(_boxName);
    await box.clear();
  }

  List<Map<String, dynamic>> get pendingReviews => _pendingReviews;
}
