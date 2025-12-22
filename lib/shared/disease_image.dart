import 'package:flutter/material.dart';

class DiseaseImage extends StatelessWidget {
  const DiseaseImage({
    super.key,
    required this.diseaseId,
    this.size = 56,
    this.borderRadius = 12,
  });

  final String diseaseId;
  final double size;
  final double borderRadius;

  String get _assetPath {
    // Map disease IDs (model or UI variants) to the actual image files.
    switch (diseaseId) {
      case 'infected_bacterial_erysipelas':
      case 'erysipelas':
      case 'bacterial_erysipelas':
        return 'assets/replace_disease/erysipelas.jpg';
      case 'infected_bacterial_greasy':
      case 'greasy_pig_disease':
      case 'greasy':
        return 'assets/replace_disease/greasy_pig.jpg';
      case 'infected_environmental_sunburn':
      case 'sunburn':
        return 'assets/replace_disease/sunburn.jpg';
      case 'infected_fungal_ringworm':
      case 'ringworm':
        return 'assets/replace_disease/ringworm.jpg';
      case 'infected_parasitic_mange':
      case 'mange':
        return 'assets/replace_disease/mange.jpg';
      case 'infected_viral_foot_and_mouth':
      case 'foot_and_mouth':
      case 'foot-and-mouth_disease':
      case 'foot and mouth disease':
        return 'assets/replace_disease/foot_disease.jpg';
      case 'swine_pox':
      case 'swine pox':
        return 'assets/replace_disease/swine_pox.jpg';
      default:
        // Fallback to default PNG location if you later add custom images there.
        return 'assets/images/diseases/$diseaseId.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: size,
        height: size,
        color: Colors.grey[200],
        child: Image.asset(
          _assetPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return Center(
              child: Icon(
                Icons.image_outlined,
                color: Colors.grey[600],
                size: size * 0.45,
              ),
            );
          },
        ),
      ),
    );
  }
}


