import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Runs an automatic check for a newer APK version on startup (Android only).
/// Expects Firestore: collection [app_config], document [android], fields:
/// - [version] (String, e.g. "1.0.1")
/// - [downloadUrl] (String, direct link to APK)
/// - [message] (String, optional) shown in the update dialog
class AppUpdateChecker extends StatefulWidget {
  const AppUpdateChecker({super.key, required this.child});

  final Widget child;

  @override
  State<AppUpdateChecker> createState() => _AppUpdateCheckerState();
}

class _AppUpdateCheckerState extends State<AppUpdateChecker> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    if (!Platform.isAndroid) return;
    if (!mounted) return;

    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('android')
          .get();

      if (!doc.exists) return;
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return;

      final latestVersion = (data['version'] ?? '').toString().trim();
      final downloadUrl = (data['downloadUrl'] ?? data['download_url'] ?? '').toString().trim();
      final message = (data['message'] ?? '').toString().trim();

      if (latestVersion.isEmpty || downloadUrl.isEmpty) return;
      if (!_isNewer(latestVersion, currentVersion)) return;
      if (!mounted) return;

      _showUpdateDialog(
        latestVersion: latestVersion,
        downloadUrl: downloadUrl,
        message: message.isNotEmpty ? message : null,
      );
    } catch (_) {
      // Ignore: no network, no config, or parse error
    }
  }

  /// Simple semver-style comparison: "1.0.1" > "1.0.0"
  bool _isNewer(String latest, String current) {
    final l = _parseVersion(latest);
    final c = _parseVersion(current);
    for (int i = 0; i < l.length || i < c.length; i++) {
      final a = i < l.length ? l[i] : 0;
      final b = i < c.length ? c[i] : 0;
      if (a > b) return true;
      if (a < b) return false;
    }
    return false;
  }

  List<int> _parseVersion(String s) {
    final versionPart = s.split('+').first.trim();
    final parts = versionPart.split('.').take(3);
    return parts.map((e) => int.tryParse(e.trim()) ?? 0).toList();
  }

  void _showUpdateDialog({
    required String latestVersion,
    required String downloadUrl,
    String? message,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Update available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A new version ($latestVersion) is available.'),
            if (message != null && message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(message),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _openDownloadUrl(downloadUrl);
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  Future<void> _openDownloadUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
