import 'package:flutter/material.dart';

/// UI helpers for the 8 pig disease classes used by the current model (`assets/labels.txt`).
class PigDiseaseUI {
  static const Map<String, Color> diseaseColors = {
    'healthy': Color(0xFF1E88E5), // blue
    'infected_bacterial_erysipelas': Color(0xFFE53935), // red
    'infected_bacterial_greasy': Color(0xFFFB8C00), // orange
    'infected_environmental_sunburn': Color(0xFFFDD835), // yellow
    'infected_fungal_ringworm': Color(0xFF8E24AA), // purple
    'infected_parasitic_mange': Color(0xFF6D4C41), // brown
    'infected_viral_foot_and_mouth': Color(0xFFD81B60), // pink
    'swine_pox': Color(0xFF43A047), // green
    // fallback
    'unknown': Colors.grey,
  };

  static String normalizeKey(String label) {
    return label.toLowerCase().trim().replaceAll(' ', '_');
  }

  /// Maps model output labels -> treatments_public document IDs.
  ///
  /// Your model labels are like `infected_bacterial_erysipelas`, but the
  /// approved treatments are stored under IDs like `erysipelas`.
  static String treatmentIdForLabel(String label) {
    final key = normalizeKey(label);
    switch (key) {
      case 'infected_bacterial_erysipelas':
        return 'erysipelas';
      case 'infected_bacterial_greasy':
        return 'greasy_pig_disease';
      case 'infected_environmental_sunburn':
        return 'sunburn';
      case 'infected_fungal_ringworm':
        return 'ringworm';
      case 'infected_parasitic_mange':
        return 'mange';
      case 'infected_viral_foot_and_mouth':
        return 'foot_and_mouth';
      case 'swine_pox':
        return 'swine_pox';
      case 'healthy':
        return 'healthy';
      default:
        // Fallback: best effort
        return key;
    }
  }

  static Color colorFor(String label) {
    final key = normalizeKey(label);
    return diseaseColors[key] ?? diseaseColors['unknown']!;
  }

  static String displayName(String label) {
    final key = normalizeKey(label);
    switch (key) {
      case 'healthy':
        return 'Healthy';
      case 'infected_bacterial_erysipelas':
        return 'Bacterial Erysipelas';
      case 'infected_bacterial_greasy':
        return 'Greasy Pig Disease';
      case 'infected_environmental_sunburn':
        return 'Sunburn';
      case 'infected_fungal_ringworm':
        return 'Ringworm';
      case 'infected_parasitic_mange':
        return 'Mange';
      case 'infected_viral_foot_and_mouth':
        return 'Foot-and-Mouth Disease';
      case 'swine_pox':
        return 'Swine Pox';
      default:
        // nice fallback for any future classes
        return key
            .split('_')
            .where((w) => w.isNotEmpty)
            .map((w) => w[0].toUpperCase() + w.substring(1))
            .join(' ');
    }
  }
}


