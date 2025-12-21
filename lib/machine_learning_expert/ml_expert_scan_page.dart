import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/scheduler.dart';
import 'dart:async';

import '../user/tflite_detector.dart';
import 'ml_expert_scan_result_page.dart';

class MLExpertScanPage extends StatefulWidget {
  const MLExpertScanPage({super.key});

  @override
  State<MLExpertScanPage> createState() => _MLExpertScanPageState();
}

class _MLExpertScanPageState extends State<MLExpertScanPage> {
  Widget _buildProcessingIndicator() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: Image.asset('assets/animation.gif', fit: BoxFit.contain),
        ),
        const SizedBox(height: 16),
        Text(
          'Processing...',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }

  Future<Map<int, List<DetectionResult>>> _performAnalysisWithUIYielding(
    List<String> imagePaths,
  ) async {
    final detector = TFLiteDetector();
    await detector.loadModel();
    final Map<int, List<DetectionResult>> allResults = {};
    for (int i = 0; i < imagePaths.length; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      await SchedulerBinding.instance.endOfFrame;
      await Future.delayed(const Duration(milliseconds: 50));
      allResults[i] = await detector.detectDiseases(imagePaths[i]);
      await Future.delayed(const Duration(milliseconds: 30));
      await SchedulerBinding.instance.endOfFrame;
    }
    detector.closeModel();
    return allResults;
  }

  Future<void> _selectFromGallery(BuildContext context) async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    if (images.isEmpty) return;
    if (images.length > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum of 5 images only.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    Timer? animationTimer;
    bool isAnalysisComplete = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          animationTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
            if (!isAnalysisComplete) setDialogState(() {});
          });
          return AlertDialog(
            title: const Text('Analyzing images'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildProcessingIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Please wait…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    await Future.delayed(const Duration(milliseconds: 300));
    try {
      final imagePaths = images.map((e) => e.path).toList();
      final allResults = await _performAnalysisWithUIYielding(imagePaths);
      isAnalysisComplete = true;
      animationTimer?.cancel();
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MLExpertScanResultPage(
            allResults: allResults,
            imagePaths: imagePaths,
          ),
        ),
      );
    } catch (e) {
      isAnalysisComplete = true;
      animationTimer?.cancel();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error analyzing images: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _takePicture(BuildContext context) async {
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (photo == null) return;

    // Analyze single photo (scan-only; no submission)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        title: Text('Analyzing image'),
        content: SizedBox(
          height: 72,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );
    try {
      final imagePaths = [photo.path];
      final allResults = await _performAnalysisWithUIYielding(imagePaths);
      if (!mounted) return;
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MLExpertScanResultPage(
            allResults: allResults,
            imagePaths: imagePaths,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error analyzing image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Scan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This mode runs the model locally and shows bounding boxes. It does not submit for expert review.',
                    style: TextStyle(color: Colors.grey[700], height: 1.25),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _takePicture(context),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Camera'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(44),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _selectFromGallery(context),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Gallery'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            minimumSize: const Size.fromHeight(44),
                            side: const BorderSide(color: Colors.green),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Tips',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '- Keep pig centered\n- Good lighting\n- Distance: 10cm to 100cm\n- Avoid blurry shots',
              style: TextStyle(color: Colors.grey[700], height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}


