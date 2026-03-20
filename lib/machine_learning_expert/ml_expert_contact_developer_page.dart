import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// ML Expert: send messages to developer. Message is emailed to developer;
/// developer replies by email, so the ML Expert gets the reply in their email inbox.
class MLExpertContactDeveloperPage extends StatefulWidget {
  const MLExpertContactDeveloperPage({super.key});

  @override
  State<MLExpertContactDeveloperPage> createState() =>
      _MLExpertContactDeveloperPageState();
}

class _MLExpertContactDeveloperPageState
    extends State<MLExpertContactDeveloperPage> {
  bool _launching = false;
  static const String _developerEmail = 'jgulanes_220000000159@uic.edu.ph';

  Future<void> _openEmailComposer() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final name = await _getCurrentUserName();
      final email = await _getCurrentUserEmail();

      final subject = Uri.encodeComponent('OinkCheck: Message from $name');
      final body = Uri.encodeComponent('From: $name${email.isNotEmpty ? ' <$email>' : ''}\n\n');
      final uri = Uri.parse('mailto:$_developerEmail?subject=$subject&body=$body');

      setState(() => _launching = true);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open email app. Please install Gmail or an email client.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open email: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  Future<String> _getCurrentUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'ML Expert';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      return (doc.data()?['fullName'] ?? 'ML Expert').toString();
    } catch (_) {
      return 'ML Expert';
    }
  }

  Future<String> _getCurrentUserEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    return (user?.email ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Contact developer'), backgroundColor: Colors.green),
        body: const Center(child: Text('Please sign in.')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Contact developer'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.email_outlined, color: Colors.green.shade700, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This will open your email app and compose a message to $_developerEmail.',
                      style: TextStyle(fontSize: 13, color: Colors.green.shade900),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _launching ? null : _openEmailComposer,
              icon: _launching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.open_in_new),
              label: const Text('Open email app'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
