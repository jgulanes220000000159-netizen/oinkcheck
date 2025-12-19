import 'package:flutter/material.dart';

class AboutAppPage extends StatelessWidget {
  const AboutAppPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'About OinkCheck',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // App Logo and Name
                Center(
                  child: Column(
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Image.asset(
                          'assets/applogo_header.png',
                          width: 100,
                          height: 100,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'OINKCHECK',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pig Disease Detection & Surveillance',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                
                // Main Description
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'About the System',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'OINKCHECK is a mobile-optimized application that utilizes deep learning and Convolutional Neural Networks (CNN) for the rapid, on-site detection and surveillance of prevalent pig skin diseases.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'The system is designed to bridge the diagnostic gap for visually identifiable porcine dermatopathies in low-resource farming environments, particularly for backyard farmers in Davao del Norte.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'The application allows farmers to capture 1–5 images of a pig\'s skin to receive immediate, preliminary identification of diseases and localized treatment recommendations.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Key Features
                const Text(
                  'Key Features',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                
                _buildFeatureItem(
                  icon: Icons.camera_alt,
                  title: 'AI-Powered Detection',
                  description: 'Advanced CNN technology for accurate pig disease identification from skin images.',
                ),
                _buildFeatureItem(
                  icon: Icons.verified_user,
                  title: 'Expert Validation',
                  description: 'Professional veterinary experts review and validate disease diagnoses.',
                ),
                _buildFeatureItem(
                  icon: Icons.medical_services,
                  title: 'Treatment Recommendations',
                  description: 'Localized treatment plans tailored for backyard farming conditions.',
                ),
                _buildFeatureItem(
                  icon: Icons.map,
                  title: 'Disease Surveillance',
                  description: 'Track disease outbreaks and hotspots in your region.',
                ),
                _buildFeatureItem(
                  icon: Icons.speed,
                  title: 'Rapid Results',
                  description: 'Get preliminary disease identification in seconds.',
                ),
                
                const SizedBox(height: 40),
                
                // Version Info
                Center(
                  child: Column(
                    children: [
                      Text(
                        'Version 1.0.0',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '© 2025 OinkCheck',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
