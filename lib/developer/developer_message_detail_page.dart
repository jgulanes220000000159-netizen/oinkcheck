import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Developer: view a single ML message and send a reply (saved to Firestore).
class DeveloperMessageDetailPage extends StatefulWidget {
  const DeveloperMessageDetailPage({
    super.key,
    required this.docId,
    required this.fromName,
    required this.fromEmail,
    required this.message,
    required this.createdAt,
    this.replyText,
    this.repliedAt,
  });

  final String docId;
  final String fromName;
  final String fromEmail;
  final String message;
  final dynamic createdAt;
  final String? replyText;
  final dynamic repliedAt;

  @override
  State<DeveloperMessageDetailPage> createState() =>
      _DeveloperMessageDetailPageState();
}

class _DeveloperMessageDetailPageState extends State<DeveloperMessageDetailPage> {
  final _replyController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.replyText != null && widget.replyText!.isNotEmpty) {
      _replyController.text = widget.replyText!;
    }
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  String _formatTimestamp(dynamic t) {
    if (t is Timestamp) {
      final dt = t.toDate();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '—';
  }

  Future<void> _saveReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('ml_developer_messages')
          .doc(widget.docId)
          .update({
        'replyText': text,
        'repliedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reply saved.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save reply: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasReply = widget.replyText != null && widget.replyText!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Message'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.fromName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.fromEmail,
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatTimestamp(widget.createdAt),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Text(
                      widget.message,
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Your reply',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _replyController,
              decoration: InputDecoration(
                hintText: 'Type your reply...',
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveReply,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(hasReply ? 'Update reply' : 'Send reply'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
