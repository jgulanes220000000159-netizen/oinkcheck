import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:io';
// import 'dart:convert';
import 'package:path_provider/path_provider.dart';
// import 'package:uuid/uuid.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mime/mime.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as img;
import 'tflite_detector.dart';
import 'detection_painter.dart';
import '../shared/pig_disease_ui.dart';
import '../shared/treatments_repository.dart';
import '../shared/geocoding_service.dart';
// import 'detection_carousel_screen.dart';
// import 'detection_result_card.dart';
// import 'tracking_page.dart';
// import '../shared/user_profile.dart';
// import '../shared/review_manager.dart';

class AnalysisSummaryScreen extends StatefulWidget {
  final Map<int, List<DetectionResult>> allResults;
  final List<String> imagePaths;

  const AnalysisSummaryScreen({
    Key? key,
    required this.allResults,
    required this.imagePaths,
  }) : super(key: key);

  @override
  State<AnalysisSummaryScreen> createState() => _AnalysisSummaryScreenState();
}

class _AnalysisSummaryScreenState extends State<AnalysisSummaryScreen> {
  final Map<String, Size> imageSizes = {};
  bool showBoundingBoxes = false;
  bool _isSubmitting = false;
  // final ReviewManager _reviewManager = ReviewManager();

  // Disease information loaded from Firestore
  Map<String, Map<String, dynamic>> _diseaseInfo = {};

  /// If the *average confidence* for a disease is below this threshold,
  /// we hide recommendations in the Analysis Summary (detections/boxes still show).
  static const double _recommendationAvgThreshold = 0.70;

  @override
  void initState() {
    super.initState();
    // sync from persistent preference used across farmer screens
    Future.microtask(() async {
      final box = await Hive.openBox('userBox');
      final pref = box.get('showBoundingBoxes');
      if (pref is bool && mounted) {
        setState(() {
          showBoundingBoxes = pref;
        });
      }
    });
    // Load disease information from Firestore
    _loadDiseaseInfo();
  }

  Future<void> _loadDiseaseInfo() async {
    final diseaseBox = await Hive.openBox('diseaseBox');
    // Try to load from local storage first (for offline access)
    final localDiseaseInfo = diseaseBox.get('diseaseInfo');
    if (localDiseaseInfo != null && localDiseaseInfo is Map) {
      setState(() {
        _diseaseInfo = Map<String, Map<String, dynamic>>.from(
          localDiseaseInfo.map(
            (k, v) =>
                MapEntry(k as String, Map<String, dynamic>.from(v as Map)),
          ),
        );
      });
      print(
        'DEBUG: Loaded disease info from cache: ${_diseaseInfo.keys.toList()}',
      );
      print('DEBUG: Cache data details:');
      _diseaseInfo.forEach((key, value) {
        print(
          '  - "$key": symptoms=${(value['symptoms'] as List).length}, treatments=${(value['treatments'] as List).length}',
        );
      });
    }

    // Try to fetch latest from Firestore (only if online)
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('diseases').get();
      final Map<String, Map<String, dynamic>> fetched = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final name = data['name'] ?? '';
        if (name.isNotEmpty) {
          fetched[name] = {
            'scientificName': data['scientificName'] ?? '',
            'symptoms': List<String>.from(data['symptoms'] ?? []),
            'treatments': List<String>.from(data['treatments'] ?? []),
          };
        }
      }
      if (fetched.isNotEmpty) {
        setState(() {
          _diseaseInfo = fetched;
        });
        await diseaseBox.put('diseaseInfo', fetched);
        print(
          'DEBUG: Updated disease info from Firestore: ${fetched.keys.toList()}',
        );
      } else {
        print('DEBUG: No disease info found in Firestore!');
      }
    } catch (e) {
      print('DEBUG: Could not fetch from Firestore (offline?): $e');
      if (_diseaseInfo.isEmpty) {
        print('DEBUG: No cached disease info available either!');
      } else {
        print('DEBUG: Using cached disease info for offline access');
      }
    }
  }

  /// Aggregates average confidence per disease label across all analyzed images.
  /// Replaces the old count-based summary.
  Map<String, Map<String, dynamic>> _getOverallDiseaseConfidenceStats() {
    final Map<String, double> sum = {};
    final Map<String, int> n = {};
    final Map<String, double> max = {};

    for (final results in widget.allResults.values) {
      for (final r in results) {
        final label = r.label;
        final conf = r.confidence;
        sum[label] = (sum[label] ?? 0) + conf;
        n[label] = (n[label] ?? 0) + 1;
        final prevMax = max[label] ?? 0.0;
        if (conf > prevMax) max[label] = conf;
      }
    }

    final Map<String, Map<String, dynamic>> out = {};
    for (final entry in n.entries) {
      final label = entry.key;
      final count = entry.value;
      final avg = count == 0 ? 0.0 : (sum[label] ?? 0.0) / count;
      out[label] = {
        'avg': avg,
        'max': max[label] ?? avg,
        // Keep sampleCount for internal/backward compatibility even if UI doesn't show "count"
        'sampleCount': count,
      };
    }
    return out;
  }

  // Compress image without resizing dimensions. Only re-encodes pixels.
  Future<File> _compressJpegSameSize(File original, {int quality = 85}) async {
    final bytes = await original.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return original;

    final encoded = img.encodeJpg(decoded, quality: quality);
    final tempDir = await getTemporaryDirectory();
    final out = File(
      '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_q$quality.jpg',
    );
    await out.writeAsBytes(encoded, flush: true);
    return out;
  }

  // If file exceeds 30 MB, progressively lower quality (85→65) until under limit.
  Future<File> _compressIfOver30Mb(File original) async {
    const int limitBytes = 30 * 1024 * 1024;
    final int sizeBytes = await original.length();
    if (sizeBytes <= limitBytes) return original;

    // Try descending quality steps; always re-encode from original bytes
    for (final quality in [85, 80, 75, 70, 65]) {
      final candidate = await _compressJpegSameSize(original, quality: quality);
      if (await candidate.length() <= limitBytes) return candidate;
    }
    // Return the smallest (last) attempt if still over limit
    return await _compressJpegSameSize(original, quality: 65);
  }

  Future<void> _loadImageSizes() async {
    for (int index = 0; index < widget.imagePaths.length; index++) {
      final image = File(widget.imagePaths[index]);
      final decodedImage = await image.readAsBytes();
      final imageInfo = await img.decodeImage(decodedImage);
      if (mounted) {
        setState(() {
          imageSizes[widget.imagePaths[index]] = Size(
            imageInfo!.width.toDouble(),
            imageInfo.height.toDouble(),
          );
        });
      }
    }
  }

  void _showSendingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(width: 24),
                  Flexible(
                    child: Text(
                      message,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Future<void> _sendForExternalReview() async {
    print('DEBUG: _sendForExternalReview called');
    setState(() {
      _isSubmitting = true;
    });
    _showSendingDialog(context, tr('sending_to_expert'));
    try {
      // final _userProfile = UserProfile();
      final user = FirebaseAuth.instance.currentUser;
      final userId = user?.uid ?? 'unknown';
      // final _reviewManager = ReviewManager();

      // --- Upload images to Firebase Storage and get URLs ---
      final List<Map<String, String>> uploadedImages = [];
      for (int i = 0; i < widget.imagePaths.length; i++) {
        final originalFile = File(widget.imagePaths[i]);
        // Compress only if over 30MB; keep dimensions unchanged
        final file = await _compressIfOver30Mb(originalFile);
        final fileName =
            '${userId}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        // Firebase Storage doesn't require manually creating folders.
        // The "folder" is just a prefix in the object path.
        final storagePath = 'diseases/$fileName';
        final ref = FirebaseStorage.instance.ref().child(storagePath);
        final detectedMime = lookupMimeType(file.path) ?? 'image/jpeg';
        await ref.putFile(file, SettableMetadata(contentType: detectedMime));
        final downloadUrl = await ref.getDownloadURL();
        uploadedImages.add({'url': downloadUrl, 'path': storagePath});
      }

      // Convert detection results to the format expected by ReviewManager
      final detections = <Map<String, dynamic>>[];
      for (var i = 0; i < widget.allResults.length; i++) {
        final results = widget.allResults[i] ?? [];
        for (var result in results) {
          detections.add({
            'disease': result.label,
            'confidence': result.confidence,
            'imageUrl': uploadedImages[i]['url'],
            'boundingBox': {
              'left': result.boundingBox.left,
              'top': result.boundingBox.top,
              'right': result.boundingBox.right,
              'bottom': result.boundingBox.bottom,
            },
          });
        }
      }

      // Build confidence-focused summary (avg/max). Keep count for backward compatibility.
      final stats = _getOverallDiseaseConfidenceStats();
      final diseaseSummary =
          stats.entries.map((entry) {
            final v = entry.value;
            final avg = (v['avg'] as double?) ?? 0.0;
            final mx = (v['max'] as double?) ?? avg;
            final cnt = (v['sampleCount'] as int?) ?? 0;
            return {
              'name': _formatLabel(entry.key),
              'label': entry.key,
              'avgConfidence': avg,
              'maxConfidence': mx,
              'count':
                  cnt, // kept so existing pages (map/recent activity) won't break
            };
          }).toList();

      // --- Also add to tracking (history) ---
      final box = await Hive.openBox('trackingBox');
      final List sessions = box.get('scans', defaultValue: []);
      final now = DateTime.now().toIso8601String();
      final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
      final List<Map<String, dynamic>> images = [];
      for (int i = 0; i < widget.imagePaths.length; i++) {
        final results = widget.allResults[i] ?? [];
        List<Map<String, dynamic>> resultList = [];
        if (results.isNotEmpty) {
          for (var result in results) {
            resultList.add({
              'disease': result.label,
              'confidence': result.confidence,
              'boundingBox': {
                'left': result.boundingBox.left,
                'top': result.boundingBox.top,
                'right': result.boundingBox.right,
                'bottom': result.boundingBox.bottom,
              },
            });
          }
        } else {
          resultList.add({'disease': 'Unknown', 'confidence': null});
        }

        // Get actual image dimensions for accurate offline bounding box positioning
        final imageFile = File(widget.imagePaths[i]);
        final imageBytes = await imageFile.readAsBytes();
        final imageInfo = await img.decodeImage(imageBytes);
        final imageWidth = imageInfo!.width.toDouble();
        final imageHeight = imageInfo.height.toDouble();

        // Save network URL and dimensions for proper caching
        images.add({
          'imageUrl': uploadedImages[i]['url'],
          'storagePath': uploadedImages[i]['path'],
          'imageWidth': imageWidth, // Add actual image width
          'imageHeight': imageHeight, // Add actual image height
          'results': resultList,
        });
      }
      sessions.add({
        'sessionId': sessionId,
        'date': now,
        'images': images,
        'source': 'expert_review',
      });
      await box.put('scans', sessions);
      print('DEBUG: sessions after add (review): ' + sessions.toString());
      // --- Upload to Firestore scan_requests collection ---
      // Get full name from Hive userBox
      final userBox = await Hive.openBox('userBox');
      final userProfile = userBox.get('userProfile');
      final fullName = userProfile?['fullName'] ?? 'Unknown';

      // Fetch user address + cached centroid (best-effort) so map can group by barangay.
      String? province;
      String? cityMunicipality;
      String? barangay;
      double? lat;
      double? lng;
      try {
        final userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .get();
        final ud = userDoc.data();
        if (ud != null) {
          province = (ud['province'] ?? '').toString();
          cityMunicipality = (ud['cityMunicipality'] ?? '').toString();
          barangay = (ud['barangay'] ?? '').toString();
          lat = (ud['latitude'] as num?)?.toDouble();
          lng = (ud['longitude'] as num?)?.toDouble();
        }
      } catch (_) {}

      // If no saved centroid yet, geocode once and also store on user doc.
      if ((lat == null || lng == null) &&
          (barangay ?? '').trim().isNotEmpty &&
          (cityMunicipality ?? '').trim().isNotEmpty &&
          (province ?? '').trim().isNotEmpty) {
        try {
          final geo = await GeocodingService().geocode(
            barangay: barangay!,
            cityMunicipality: cityMunicipality!,
            province: province!,
          );
          if (geo != null) {
            lat = geo['lat'];
            lng = geo['lng'];
            try {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .set({
                    'latitude': lat,
                    'longitude': lng,
                    'geoSource': 'nominatim_barangay_centroid',
                    'geoUpdatedAt': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
            } catch (_) {}
          }
        } catch (_) {}
      }

      await FirebaseFirestore.instance
          .collection('scan_requests')
          .doc(sessionId)
          .set({
            'id': sessionId,
            'userId': userId,
            'userName': fullName,
            'status': 'pending',
            'submittedAt': now,
            'province': province,
            'cityMunicipality': cityMunicipality,
            'barangay': barangay,
            'latitude': lat,
            'longitude': lng,
            'images': images, // This now includes both imageUrl and imagePath
            'diseaseSummary':
                diseaseSummary
                    .map(
                      (e) => {
                        'name': e['name'],
                        'count': e['count'],
                        'avgConfidence': e['avgConfidence'],
                        'maxConfidence': e['maxConfidence'],
                        'label': e['label'],
                      },
                    )
                    .toList(),
            // No expertReview yet
          });
      // --- End add to tracking ---

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('analysis_sent_successfully')),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 70, left: 16, right: 16),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr('error_sending_for_review', namedArgs: {'error': '$e'}),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 70, left: 16, right: 16),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  // Removed old count-percentage severity helper; we now focus on confidence averages.

  String _formatLabel(String label) {
    return PigDiseaseUI.displayName(label);
  }

  Widget _buildNoDiseasesMessage() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: Colors.grey[600], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr('no_detections'),
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiseaseSummaryCard(
    String disease,
    double avgConfidence,
    double maxConfidence,
  ) {
    final color = DetectionPainter.diseaseColors[disease] ?? Colors.grey;
    final isHealthy = disease.toLowerCase() == 'healthy';
    final isUnknown = disease.toLowerCase() == 'unknown';
    final canShowRecommendation =
        !isHealthy &&
        !isUnknown &&
        avgConfidence >= _recommendationAvgThreshold;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap:
            isHealthy
                ? () => _showHealthyStatus(context)
                : isUnknown
                ? () => _showUnknownStatus(context)
                : canShowRecommendation
                ? () => _showDiseaseRecommendations(context, disease)
                : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Icon(Icons.check_circle, size: 16, color: color),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _formatLabel(disease),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Avg ${(avgConfidence * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Average confidence',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: avgConfidence.clamp(0.0, 1.0),
                            backgroundColor: color.withOpacity(0.1),
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                            minHeight: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${(avgConfidence * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Max confidence: ${(maxConfidence * 100).toStringAsFixed(1)}%',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              if (isHealthy || isUnknown || canShowRecommendation) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isHealthy || isUnknown
                            ? Icons.info_outline
                            : Icons.medical_services_outlined,
                        color: color,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isHealthy || isUnknown
                            ? tr('not_applicable')
                            : tr('see_recommendation'),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Special cases for diseases not in Firestore (only for healthy and unknown)
  static const Map<String, Map<String, dynamic>> specialDiseaseInfo = {
    'healthy': {
      'symptoms': [
        'Vibrant green leaves without spots or lesions',
        'Normal growth pattern',
        'No visible signs of disease or pest damage',
      ],
      'treatments': [
        'Regular monitoring for early detection of problems',
        'Maintain proper irrigation and fertilization',
        'Practice good orchard sanitation',
      ],
    },
    'unknown': {
      'symptoms': ['N/A.'],
      'treatments': ['N/A.'],
    },
  };

  void _showDiseaseRecommendations(BuildContext context, String disease) async {
    final diseaseId = PigDiseaseUI.treatmentIdForLabel(disease);
    final repo = TreatmentsRepository();

    // Check if it's a special case (healthy/unknown) that's not in Firestore
    Map<String, dynamic>? info;
    if (specialDiseaseInfo.containsKey(diseaseId)) {
      info = specialDiseaseInfo[diseaseId];
    } else {
      // If disease info is not loaded yet, try to load it
      if (_diseaseInfo.isEmpty) {
        await _loadDiseaseInfo();
      }

      // If still empty after loading, try to load from cache directly
      if (_diseaseInfo.isEmpty) {
        try {
          final diseaseBox = await Hive.openBox('diseaseBox');
          final localDiseaseInfo = diseaseBox.get('diseaseInfo');
          if (localDiseaseInfo != null && localDiseaseInfo is Map) {
            _diseaseInfo = Map<String, Map<String, dynamic>>.from(
              localDiseaseInfo.map(
                (k, v) =>
                    MapEntry(k as String, Map<String, dynamic>.from(v as Map)),
              ),
            );
            print(
              'DEBUG: Loaded disease info from cache in recommendations: ${_diseaseInfo.keys.toList()}',
            );
          }
        } catch (e) {
          print('DEBUG: Could not load from cache: $e');
        }
      }

      // Try to get from Firestore data with multiple matching strategies
      info = _diseaseInfo[disease.toLowerCase()];

      // If not found, try with formatted label
      if (info == null) {
        final formattedLabel = _formatLabel(disease).toLowerCase();
        info = _diseaseInfo[formattedLabel];
      }

      // If still not found, try common variations
      if (info == null) {
        // Handle common naming variations
        String normalizedLabel =
            disease
                .toLowerCase()
                .replaceAll('_', ' ') // Replace underscores with spaces
                .replaceAll(
                  'blackspot',
                  'black spot',
                ) // Fix blackspot -> black spot
                .toLowerCase();
        info = _diseaseInfo[normalizedLabel];
      }

      // Special handling for bacterial black spot typo
      if (info == null &&
          (diseaseId.contains('bacterial') ||
              diseaseId.contains('backterial'))) {
        // Try to match with the correct database key
        if (diseaseId.contains('bacterial') ||
            diseaseId.contains('backterial')) {
          info = _diseaseInfo['Bacterial black spot'];
        }
      }

      // If still not found, try partial matching
      if (info == null) {
        for (String key in _diseaseInfo.keys) {
          final normalizedKey = key
              .toLowerCase()
              .replaceAll('_', ' ')
              .replaceAll('blackspot', 'black spot');
          final normalizedLabel = disease
              .toLowerCase()
              .replaceAll('_', ' ')
              .replaceAll('blackspot', 'black spot')
              .replaceAll('backterial', 'bacterial'); // Fix typo

          if (normalizedKey.contains(normalizedLabel) ||
              normalizedLabel.contains(normalizedKey) ||
              key.toLowerCase().contains(diseaseId) ||
              diseaseId.contains(key.toLowerCase())) {
            info = _diseaseInfo[key];
            break;
          }
        }
      }
    }

    // Debug print to help identify the issue
    print('DEBUG: Looking for disease: "$disease" (diseaseId: "$diseaseId")');
    print(
      'DEBUG: Available specialDiseaseInfo keys: ${specialDiseaseInfo.keys}',
    );
    print('DEBUG: Available _diseaseInfo keys: ${_diseaseInfo.keys}');
    print('DEBUG: _diseaseInfo length: ${_diseaseInfo.length}');
    print('DEBUG: Found info: ${info != null}');

    // Show what disease names are actually being detected
    print(
      'DEBUG: All detected disease labels: ${widget.allResults.values.expand((results) => results.map((r) => r.label)).toSet()}',
    );

    // Special debug for bacterial black spot
    if (diseaseId.contains('bacterial') ||
        diseaseId.contains('black') ||
        diseaseId.contains('backterial')) {
      print('DEBUG: BACTERIAL BLACK SPOT DEBUG:');
      print('  - Original disease: "$disease"');
      print('  - diseaseId: "$diseaseId"');
      print(
        '  - Looking for keys containing "bacterial": ${_diseaseInfo.keys.where((k) => k.toLowerCase().contains('bacterial')).toList()}',
      );
      print(
        '  - Looking for keys containing "backterial": ${_diseaseInfo.keys.where((k) => k.toLowerCase().contains('backterial')).toList()}',
      );
      print(
        '  - Looking for keys containing "black": ${_diseaseInfo.keys.where((k) => k.toLowerCase().contains('black')).toList()}',
      );
      print('  - All available keys: ${_diseaseInfo.keys.toList()}');
    }

    // Print all disease info for debugging
    if (_diseaseInfo.isNotEmpty) {
      print('DEBUG: _diseaseInfo contents:');
      _diseaseInfo.forEach((key, value) {
        print('  - "$key": ${value.keys}');
      });
    } else {
      print('DEBUG: _diseaseInfo is empty!');
    }

    final isHealthy = diseaseId == 'healthy';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder:
                (context, scrollController) => SingleChildScrollView(
                  controller: scrollController,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isHealthy
                                  ? Icons.check_circle
                                  : Icons.medical_services_outlined,
                              color:
                                  isHealthy
                                      ? Colors.green
                                      : PigDiseaseUI.colorFor(diseaseId),
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _formatLabel(disease),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        if (!isHealthy && diseaseId != 'unknown') ...[
                          Text(
                            tr('treatment_and_recommendations'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          FutureBuilder(
                            future: repo.getPublicDoc(diseaseId),
                            builder: (context, snap) {
                              if (snap.connectionState ==
                                  ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              if (snap.hasError) {
                                return Text(
                                  'Failed to load treatments: ${snap.error}',
                                  style: const TextStyle(fontSize: 14),
                                );
                              }
                              final doc = snap.data;
                              final data =
                                  doc != null && doc.exists ? doc.data() : null;
                              final treatments =
                                  (data?['treatments'] as List? ?? [])
                                      .map((e) => e.toString())
                                      .toList();
                              if (treatments.isEmpty) {
                                return const Text(
                                  'No approved treatments yet. Please wait for veterinarian approval.',
                                  style: TextStyle(fontSize: 15),
                                );
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ...treatments.map(
                                    (t) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        '• $t',
                                        style: const TextStyle(fontSize: 15),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ] else if (isHealthy) ...[
                          Text(
                            tr('treatment_and_recommendations'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'No disease detected. Keep monitoring and maintain good hygiene.',
                            style: TextStyle(fontSize: 15),
                          ),
                        ] else if (diseaseId == 'unknown') ...[
                          Text(
                            tr('treatment_and_recommendations'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'No recommendation available for Unknown. Please rescan with clearer images.',
                            style: TextStyle(fontSize: 15),
                          ),
                        ] else if (info != null) ...[
                          Text(
                            tr('symptoms'),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...(info['symptoms'] as List<String>).map<Widget>(
                            (s) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '• $s',
                                style: const TextStyle(fontSize: 15),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            tr('treatment_and_recommendations'),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...(info['treatments'] as List<String>).map<Widget>(
                            (t) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '• $t',
                                style: const TextStyle(fontSize: 15),
                              ),
                            ),
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange[200]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.orange[700],
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      tr('information_not_available'),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange[700],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  tr(
                                    'detailed_info_not_available_for',
                                    namedArgs: {
                                      'disease': _formatLabel(disease),
                                    },
                                  ),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.orange[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  tr('contact_expert_for_more_info'),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.orange[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
          ),
    );
  }

  void _showHealthyStatus(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder:
                (context, scrollController) => SingleChildScrollView(
                  controller: scrollController,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                tr('healthy_leaves'),
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        Center(
                          child: Text(
                            tr('not_applicable'),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            tr('no_additional_info_healthy_leaves'),
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
  }

  void _showUnknownStatus(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder:
                (context, scrollController) => SingleChildScrollView(
                  controller: scrollController,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.help_outline,
                              color: Colors.grey,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                tr('unknown'),
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        Center(
                          child: Text(
                            tr('not_applicable'),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            tr('no_additional_info_unknown'),
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
  }

  // Widget _buildStatusSection(String title, List<String> items) {
  //   return Column(
  //     crossAxisAlignment: CrossAxisAlignment.start,
  //     children: [
  //       Text(
  //         title,
  //         style: const TextStyle(
  //           fontSize: 16,
  //           fontWeight: FontWeight.bold,
  //           color: Colors.green,
  //         ),
  //       ),
  //       const SizedBox(height: 8),
  //       ...items.map(
  //         (item) => Padding(
  //           padding: const EdgeInsets.only(bottom: 8),
  //           child: Row(
  //             crossAxisAlignment: CrossAxisAlignment.start,
  //             children: [
  //               const Icon(
  //                 Icons.check_circle_outline,
  //                 size: 20,
  //                 color: Colors.green,
  //               ),
  //               const SizedBox(width: 8),
  //               Expanded(
  //                 child: Text(item, style: const TextStyle(fontSize: 14)),
  //               ),
  //             ],
  //           ),
  //         ),
  //       ),
  //     ],
  //   );
  // }

  Widget _buildImageGrid() {
    if (showBoundingBoxes && imageSizes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: widget.imagePaths.length,
      itemBuilder: (context, index) {
        final imagePath = widget.imagePaths[index];
        final results = widget.allResults[index] ?? [];
        final imageSize = imageSizes[imagePath] ?? const Size(1, 1);

        return GestureDetector(
          onTap: () => _showImageCarousel(index),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final widgetW = constraints.maxWidth;
              final widgetH = constraints.maxHeight;
              final imgW = imageSize.width;
              final imgH = imageSize.height;
              if (imgW == 0 || imgH == 0) {
                return const Center(child: CircularProgressIndicator());
              }
              // Calculate scale and offset for BoxFit.cover
              final widgetAspect = widgetW / widgetH;
              final imageAspect = imgW / imgH;
              double displayW, displayH, dx = 0, dy = 0;
              if (widgetAspect > imageAspect) {
                // Widget is wider than image
                displayW = widgetW;
                displayH = widgetW / imageAspect;
                dy = (widgetH - displayH) / 2;
              } else {
                // Widget is taller than image
                displayH = widgetH;
                displayW = widgetH * imageAspect;
                dx = (widgetW - displayW) / 2;
              }
              final displayedImageSize = Size(displayW, displayH);
              final displayedImageOffset = Offset(dx, dy);
              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(File(imagePath), fit: BoxFit.cover),
                  ),
                  if (showBoundingBoxes &&
                      results.isNotEmpty &&
                      imageSizes.isNotEmpty)
                    CustomPaint(
                      painter: DetectionPainter(
                        results: results,
                        originalImageSize: imageSize,
                        displayedImageSize: displayedImageSize,
                        displayedImageOffset: displayedImageOffset,
                      ),
                      size: Size(widgetW, widgetH),
                    ),
                  if (results.isNotEmpty)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${results.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showImageCarousel(int initialIndex) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (context) => _ImageCarouselViewer(
            imagePaths: widget.imagePaths,
            allResults: widget.allResults,
            imageSizes: imageSizes,
            initialIndex: initialIndex,
            showBoundingBoxes: showBoundingBoxes,
          ),
    );
  }

  // Removed: "Add to Tracking" option (user requested).
  // Keeping the implementation commented/removed prevents users from saving scans to tracking here.
  /* Future<void> _addToTracking() async {
    print('DEBUG: _addToTracking called');
    setState(() {
      _isSubmitting = true;
    });
    _showSendingDialog(context, tr('adding_to_tracking'));
    try {
      // final _userProfile = UserProfile();
      final user = FirebaseAuth.instance.currentUser;
      final userId = user?.uid ?? 'unknown';
      final box = await Hive.openBox('trackingBox');
      final List sessions = box.get('scans', defaultValue: []);
      final now = DateTime.now().toIso8601String();
      final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
      final List<Map<String, dynamic>> images = [];
      // --- Upload images to Firebase Storage and get URLs ---
      final List<Map<String, String>> uploadedImages2 = [];
      for (int i = 0; i < widget.imagePaths.length; i++) {
        final originalFile = File(widget.imagePaths[i]);
        // Compress only if over 30MB; keep dimensions unchanged
        final file = await _compressIfOver30Mb(originalFile);
        final fileName =
            '${userId}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        final storagePath = 'diseases/$fileName';
        final ref = FirebaseStorage.instance.ref().child(storagePath);
        final detectedMime = lookupMimeType(file.path) ?? 'image/jpeg';
        await ref.putFile(file, SettableMetadata(contentType: detectedMime));
        final downloadUrl = await ref.getDownloadURL();
        uploadedImages2.add({'url': downloadUrl, 'path': storagePath});
      }
      // Build diseaseSummary from detection results to power Recent Activity title
      final Map<String, int> diseaseLabelCounts = {};
      widget.allResults.values.forEach((results) {
        for (var result in results) {
          diseaseLabelCounts[result.label] =
              (diseaseLabelCounts[result.label] ?? 0) + 1;
        }
      });
      final diseaseCounts =
          diseaseLabelCounts.entries.map((entry) {
            return {
              'name': _formatLabel(entry.key),
              'label': entry.key,
              'count': entry.value,
            };
          }).toList();
      for (int i = 0; i < widget.imagePaths.length; i++) {
        final results = widget.allResults[i] ?? [];
        List<Map<String, dynamic>> resultList = [];
        if (results.isNotEmpty) {
          for (var result in results) {
            resultList.add({
              'disease': result.label,
              'confidence': result.confidence,
            });
          }
        } else {
          resultList.add({'disease': 'Unknown', 'confidence': null});
        }
        images.add({
          'imageUrl': uploadedImages2[i]['url'],
          'storagePath': uploadedImages2[i]['path'],
          'results': resultList,
        });
      }
      sessions.add({
        'sessionId': sessionId,
        'date': now,
        'images': images,
        'source': 'tracking',
      });
      await box.put('scans', sessions);
      print('DEBUG: sessions after add: ' + sessions.toString());
      // --- Upload to Firestore tracking collection ---
      await FirebaseFirestore.instance
          .collection('tracking')
          .doc(sessionId)
          .set({
            'sessionId': sessionId,
            'date': now,
            'images': images,
            'source': 'tracking',
            'userId': userId,
          });
      // --- End upload to Firestore ---
      // --- Also write to scan_requests so it appears under Recent Activity ---
      try {
        final userBox = await Hive.openBox('userBox');
        final userProfile = userBox.get('userProfile');
        final fullName = userProfile?['fullName'] ?? 'Unknown';
        await FirebaseFirestore.instance
            .collection('scan_requests')
            .doc(sessionId)
            .set({
              'id': sessionId,
              'userId': userId,
              'userName': fullName,
              'status': 'tracking',
              'submittedAt': now,
              'images': images,
              'diseaseSummary': diseaseCounts,
            });
      } catch (e) {
        // Non-fatal: tracking saved; recent activity write failed
        print('WARN: Failed to write tracking entry to scan_requests: $e');
      }
      // --- End recent activity write ---
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('analysis_added_to_tracking')),
            backgroundColor: Colors.blue,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 70, left: 16, right: 16),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr('error_adding_to_tracking', namedArgs: {'error': '$e'}),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 70, left: 16, right: 16),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  } */

  @override
  Widget build(BuildContext context) {
    final stats = _getOverallDiseaseConfidenceStats();
    // Kick off image size loading only when needed (first build), avoid blocking transition
    if (showBoundingBoxes && imageSizes.isEmpty) {
      // Defer loading sizes to next microtask to avoid layout jank
      Future.microtask(() => _loadImageSizes());
    }

    // Sort diseases by average confidence (descending)
    final sortedDiseases =
        stats.entries.toList()..sort((a, b) {
          final aAvg = (a.value['avg'] as double?) ?? 0.0;
          final bAvg = (b.value['avg'] as double?) ?? 0.0;
          return bAvg.compareTo(aAvg);
        });

    // Farmer feedback: if confidence is low, recommendations are hidden.
    final lowConfidenceDiseases =
        sortedDiseases.where((e) {
          final label = e.key.toString();
          final key = PigDiseaseUI.normalizeKey(label);
          if (key == 'healthy' || key == 'unknown') return false;
          final avg = (e.value['avg'] as double?) ?? 0.0;
          return avg < _recommendationAvgThreshold;
        }).toList();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(tr('analysis_summary')),
        centerTitle: true,
        backgroundColor: Colors.green,
        elevation: 0,
        actions: [],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tr('total_images'),
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${widget.imagePaths.length}',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: Colors.grey[300],
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Analyzed images',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${widget.imagePaths.length}',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          tr('analyzed_images'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Toggle button for bounding boxes
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(tr('show_bounding_boxes')),
                            Switch(
                              value: showBoundingBoxes,
                              onChanged: (value) async {
                                setState(() {
                                  showBoundingBoxes = value;
                                });
                                // persist same as detail page for consistency
                                final box = await Hive.openBox('userBox');
                                await box.put(
                                  'showBoundingBoxes',
                                  showBoundingBoxes,
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildImageGrid(),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      tr('disease_summary'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.white,
                    child:
                        sortedDiseases.isEmpty
                            ? _buildNoDiseasesMessage()
                            : Column(
                              children: [
                                if (lowConfidenceDiseases.isNotEmpty) ...[
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.orange.withOpacity(0.25),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.info_outline,
                                          color: Colors.orange,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'Some detections are below ${(_recommendationAvgThreshold * 100).toStringAsFixed(0)}% average confidence. Recommendations are hidden for these results and are intended for expert review/confirmation.',
                                            style: TextStyle(
                                              color: Colors.orange[900],
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                ...sortedDiseases.map((entry) {
                                  final v = entry.value;
                                  final avg = (v['avg'] as double?) ?? 0.0;
                                  final mx = (v['max'] as double?) ?? avg;
                                  return _buildDiseaseSummaryCard(
                                    entry.key,
                                    avg,
                                    mx,
                                  );
                                }).toList(),
                              ],
                            ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar:
          !_isSubmitting
              ? Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _sendForExternalReview,
                          icon: const Icon(Icons.send),
                          label: Text(tr('send_for_review')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
              : null,
    );
  }
}

class _ImageCarouselViewer extends StatefulWidget {
  final List<String> imagePaths;
  final Map<int, List<DetectionResult>> allResults;
  final Map<String, Size> imageSizes;
  final int initialIndex;
  final bool showBoundingBoxes;

  const _ImageCarouselViewer({
    required this.imagePaths,
    required this.allResults,
    required this.imageSizes,
    required this.initialIndex,
    required this.showBoundingBoxes,
  });

  @override
  State<_ImageCarouselViewer> createState() => _ImageCarouselViewerState();
}

class _ImageCarouselViewerState extends State<_ImageCarouselViewer> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          // Full screen image carousel
          GestureDetector(
            onTap: _toggleControls,
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemCount: widget.imagePaths.length,
              itemBuilder: (context, index) {
                final imagePath = widget.imagePaths[index];
                final results = widget.allResults[index] ?? [];
                final imageSize =
                    widget.imageSizes[imagePath] ?? const Size(1, 1);

                return Stack(
                  children: [
                    // Image + bounding boxes MUST be inside the same InteractiveViewer so they
                    // zoom/pan together (prevents "boxes are off" when user taps/zooms).
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final maxW = constraints.maxWidth;
                        final maxH = constraints.maxHeight;
                        final imageAspect = imageSize.width / imageSize.height;
                        final viewAspect = maxW / maxH;

                        double displayW;
                        double displayH;
                        if (viewAspect > imageAspect) {
                          // view is wider -> constrain by height
                          displayH = maxH;
                          displayW = maxH * imageAspect;
                        } else {
                          // view is taller -> constrain by width
                          displayW = maxW;
                          displayH = maxW / imageAspect;
                        }

                        return Center(
                          child: InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 3.0,
                            child: SizedBox(
                              width: displayW,
                              height: displayH,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    File(imagePath),
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: Colors.grey[800],
                                        child: Center(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.error_outline,
                                                color: Colors.white,
                                                size: 64,
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                tr('error_loading_image'),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  if (widget.showBoundingBoxes &&
                                      results.isNotEmpty &&
                                      widget.imageSizes.isNotEmpty)
                                    CustomPaint(
                                      painter: DetectionPainter(
                                        results: results,
                                        originalImageSize: imageSize,
                                        displayedImageSize: Size(
                                          displayW,
                                          displayH,
                                        ),
                                        displayedImageOffset: Offset.zero,
                                        // Keep labels + confidence visible in fullscreen viewer.
                                        debugMode: true,
                                      ),
                                      size: Size(displayW, displayH),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          // Controls overlay
          if (_showControls) ...[
            // Top controls
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                  ),
                ),
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: 16,
                  right: 16,
                  bottom: 16,
                ),
                child: Row(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_currentIndex + 1} / ${widget.imagePaths.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Detection count
                    if (widget.allResults[_currentIndex]?.isNotEmpty == true)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.visibility,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.allResults[_currentIndex]!.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Bottom controls with page indicators
            if (widget.imagePaths.length > 1)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  padding: EdgeInsets.only(
                    top: 16,
                    left: 16,
                    right: 16,
                    bottom: MediaQuery.of(context).padding.bottom + 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      widget.imagePaths.length,
                      (index) => GestureDetector(
                        onTap: () {
                          _pageController.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentIndex == index ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color:
                                _currentIndex == index
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
