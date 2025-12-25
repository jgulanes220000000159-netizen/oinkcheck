import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Widget for users to rate the app (1-5 stars) with optional comment.
/// Restrictions:
/// - Farmers: Must have at least one submitted report
/// - Experts/Head Vets: Must have at least one completed report
/// - ML Experts: Excluded (they have their own rating system)
class AppRatingWidget extends StatefulWidget {
  final String userRole; // 'farmer', 'expert', 'head_veterinarian', etc.
  
  const AppRatingWidget({
    Key? key,
    required this.userRole,
  }) : super(key: key);

  @override
  State<AppRatingWidget> createState() => _AppRatingWidgetState();
}

class _AppRatingWidgetState extends State<AppRatingWidget> {
  int? _currentRating;
  int? _savedRating;
  String? _savedComment;
  final TextEditingController _commentController = TextEditingController();
  bool _isLoading = false;
  bool _canRate = false;
  bool _isChecking = true;
  String _restrictionMessage = '';

  @override
  void initState() {
    super.initState();
    _checkEligibility();
    _loadExistingRating();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _checkEligibility() async {
    setState(() => _isChecking = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _canRate = false;
          _isChecking = false;
        });
        return;
      }

      // Normalize role for comparison
      final normalizedRole = widget.userRole.toLowerCase().trim();
      
      // ML Experts are excluded
      if (normalizedRole == 'machine_learning_expert') {
        setState(() {
          _canRate = false;
          _isChecking = false;
          _restrictionMessage = 'ML Experts have their own rating system';
        });
        return;
      }
      
      // Check based on role
      if (normalizedRole == 'farmer') {
        // Farmers need at least one submitted report
        final reports = await FirebaseFirestore.instance
            .collection('scan_requests')
            .where('userId', isEqualTo: user.uid)
            .limit(1)
            .get();
        
        setState(() {
          _canRate = reports.docs.isNotEmpty;
          _isChecking = false;
          if (!_canRate) {
            _restrictionMessage = 'Submit at least one report to rate the app';
          }
        });
      } else if (normalizedRole == 'expert' || normalizedRole == 'head_veterinarian') {
        // Experts/Head Vets need at least one completed report (where they are the reviewing expert)
        // Check both expertUid field and expertReview.expertUid
        final completedByMe = await FirebaseFirestore.instance
            .collection('scan_requests')
            .where('status', isEqualTo: 'completed')
            .where('expertUid', isEqualTo: user.uid)
            .limit(1)
            .get();
        
        // Also check if any completed report has this expert in expertReview
        bool foundInReview = false;
        if (completedByMe.docs.isEmpty) {
          final allCompleted = await FirebaseFirestore.instance
              .collection('scan_requests')
              .where('status', isEqualTo: 'completed')
              .limit(50) // Check up to 50 completed reports
              .get();
          
          for (final doc in allCompleted.docs) {
            final data = doc.data();
            final expertReview = data['expertReview'];
            if (expertReview is Map && expertReview['expertUid'] == user.uid) {
              foundInReview = true;
              break;
            }
          }
        }
        
        final hasCompletedReport = completedByMe.docs.isNotEmpty || foundInReview;
        
        setState(() {
          _canRate = hasCompletedReport;
          _isChecking = false;
          if (!_canRate) {
            _restrictionMessage = 'Complete at least one report review to rate the app';
          }
        });
      } else {
        // Other roles (veterinarian, admin, etc.) - require at least one completed report too
        // This ensures all expert-like roles follow the same rule
        final completedByMe = await FirebaseFirestore.instance
            .collection('scan_requests')
            .where('status', isEqualTo: 'completed')
            .where('expertUid', isEqualTo: user.uid)
            .limit(1)
            .get();
        
        bool foundInReview = false;
        if (completedByMe.docs.isEmpty) {
          final allCompleted = await FirebaseFirestore.instance
              .collection('scan_requests')
              .where('status', isEqualTo: 'completed')
              .limit(50)
              .get();
          
          for (final doc in allCompleted.docs) {
            final data = doc.data();
            final expertReview = data['expertReview'];
            if (expertReview is Map && expertReview['expertUid'] == user.uid) {
              foundInReview = true;
              break;
            }
          }
        }
        
        setState(() {
          _canRate = completedByMe.docs.isNotEmpty || foundInReview;
          _isChecking = false;
          if (!_canRate) {
            _restrictionMessage = 'Complete at least one report review to rate the app';
          }
        });
      }
    } catch (e) {
      print('Error checking rating eligibility: $e');
      setState(() {
        _canRate = false;
        _isChecking = false;
        _restrictionMessage = 'Unable to verify eligibility';
      });
    }
  }

  Future<void> _loadExistingRating() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final ratingDoc = await FirebaseFirestore.instance
          .collection('app_ratings')
          .doc(user.uid)
          .get();

      if (ratingDoc.exists) {
        final data = ratingDoc.data() as Map<String, dynamic>;
        setState(() {
          _savedRating = (data['rating'] as num?)?.toInt();
          _savedComment = data['comment']?.toString();
          _currentRating = _savedRating;
          if (_savedComment != null && _savedComment!.isNotEmpty) {
            _commentController.text = _savedComment!;
          }
        });
      }
    } catch (e) {
      print('Error loading existing rating: $e');
    }
  }

  Future<void> _submitRating() async {
    if (_currentRating == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a rating'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userName = userDoc.data()?['fullName'] ?? 'Unknown User';

      await FirebaseFirestore.instance
          .collection('app_ratings')
          .doc(user.uid)
          .set({
        'userId': user.uid,
        'userName': userName,
        'userEmail': user.email ?? '',
        'userRole': widget.userRole,
        'rating': _currentRating,
        'comment': _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() {
        _savedRating = _currentRating;
        _savedComment = _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim();
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rating submitted successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error submitting rating: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting rating: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const SizedBox.shrink(); // Don't show while checking
    }

    if (!_canRate) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _restrictionMessage,
                style: TextStyle(
                  color: Colors.orange[900],
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Rate OinkCheck',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Star rating
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final starValue = index + 1;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _currentRating = starValue;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    _currentRating != null && starValue <= _currentRating!
                        ? Icons.star
                        : Icons.star_border,
                    color: Colors.amber,
                    size: 36,
                  ),
                ),
              );
            }),
          ),
          if (_savedRating != null) ...[
            const SizedBox(height: 8),
            Text(
              'Your rating: $_savedRating/5',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          // Comment field
          TextField(
            controller: _commentController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Optional: Share your feedback...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.green, width: 1.5),
              ),
              filled: true,
              fillColor: Colors.grey[50],
            ),
          ),
          const SizedBox(height: 12),
          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submitRating,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Submit Rating',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

