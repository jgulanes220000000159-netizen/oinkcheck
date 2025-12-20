import 'package:flutter/material.dart';
import 'tflite_detector.dart';
import 'package:easy_localization/easy_localization.dart';
import '../shared/pig_disease_ui.dart';
import '../shared/treatments_repository.dart';

class DetectionResultCard extends StatelessWidget {
  final DetectionResult result;
  final int? count;
  final double? percentage;
  final VoidCallback? onTap;

  const DetectionResultCard({
    Key? key,
    required this.result,
    this.count,
    this.percentage,
    this.onTap,
  }) : super(key: key);

  Color get diseaseColor {
    return PigDiseaseUI.colorFor(result.label);
  }

  String _formatLabel(String label) {
    return PigDiseaseUI.displayName(label);
  }

  IconData _getSeverityIcon() {
    if (percentage != null) {
      if (percentage! > 0.01) return Icons.warning_rounded;
      return Icons.info_outline;
    }
    return Icons.info_outline;
  }

  // Pig disease info is handled in the Treatments page; keep this card focused on scan results UI.

  void _showDiseaseRecommendations(BuildContext context) {
    final label = result.label.toLowerCase();
    final isHealthy = PigDiseaseUI.normalizeKey(label) == 'healthy';
    final isUnknown = PigDiseaseUI.normalizeKey(label) == 'unknown';
    final repo = TreatmentsRepository();
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
                              color: isHealthy ? Colors.green : diseaseColor,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _formatLabel(result.label),
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
                        const Text(
                          'Treatment & Recommendations',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        if (isHealthy)
                          const Text(
                            'No disease detected. Keep monitoring and maintain good hygiene.',
                            style: TextStyle(fontSize: 15),
                          )
                        else if (isUnknown)
                          const Text(
                            'No recommendation available for Unknown. Please rescan with clearer images.',
                            style: TextStyle(fontSize: 15),
                          )
                        else
                          FutureBuilder(
                            future: repo.getPublicDoc(PigDiseaseUI.treatmentIdForLabel(label)),
                            builder: (context, snap) {
                              if (snap.connectionState == ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              if (snap.hasError) {
                                return Text(
                                  'Failed to load treatments: ${snap.error}',
                                  style: const TextStyle(fontSize: 14),
                                );
                              }
                              final doc = snap.data;
                              final data = doc != null && doc.exists ? doc.data() : null;
                              final treatments =
                                  (data?['treatments'] as List? ?? []).map((e) => e.toString()).toList();
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
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Text('• $t', style: const TextStyle(fontSize: 15)),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
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
                            const Expanded(
                              child: Text(
                                'Healthy Leaves',
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
                        const Center(
                          child: Text(
                            'N/A',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Center(
                          child: Text(
                            'No additional information for healthy leaves.',
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

  @override
  Widget build(BuildContext context) {
    final isHealthy = result.label.toLowerCase() == 'healthy';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap:
            () =>
                isHealthy
                    ? _showHealthyStatus(context)
                    : _showDiseaseRecommendations(context),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: diseaseColor.withOpacity(0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: diseaseColor, width: 2),
                    ),
                    child: Icon(
                      isHealthy ? Icons.check_circle : _getSeverityIcon(),
                      color: diseaseColor,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _formatLabel(result.label),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            if (count != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: diseaseColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'x$count',
                                  style: TextStyle(
                                    color: diseaseColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (percentage != null) ...[
                          Text(
                            tr('percentage_of_total_leaves'),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: percentage,
                              backgroundColor: diseaseColor.withOpacity(0.1),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                diseaseColor,
                              ),
                              minHeight: 8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${(percentage! * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: diseaseColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: diseaseColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isHealthy
                          ? Icons.info_outline
                          : Icons.medical_services_outlined,
                      color: diseaseColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isHealthy
                          ? tr('not_applicable')
                          : tr('see_recommendation'),
                      style: TextStyle(
                        color: diseaseColor,
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
    );
  }
}
