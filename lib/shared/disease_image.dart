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

  String get _assetPath => 'assets/images/diseases/$diseaseId.png';

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


