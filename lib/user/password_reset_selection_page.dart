import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'password_reset_email_page.dart';

/// Email-only password reset lookup screen.
class PasswordResetSelectionPage extends StatefulWidget {
  const PasswordResetSelectionPage({Key? key}) : super(key: key);

  @override
  _PasswordResetSelectionPageState createState() =>
      _PasswordResetSelectionPageState();
}

class _PasswordResetSelectionPageState
    extends State<PasswordResetSelectionPage> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  
  Future<void> _findAccountByEmail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();

      if (email.isEmpty) {
        setState(() {
          _errorMessage = 'Please enter your email address.';
          _isLoading = false;
        });
        return;
      }

      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        setState(() {
          _errorMessage = 'No account found with the provided email address.';
          _isLoading = false;
        });
        return;
      }

      final userDoc = query.docs.first;
      final data = userDoc.data();
      final userId = userDoc.id;
      final userEmail = data['email']?.toString().trim() ?? '';
      final hasRealEmail =
          userEmail.isNotEmpty && !userEmail.endsWith('@oinkcheck.local');

      if (!hasRealEmail) {
        setState(() {
          _errorMessage =
              'This account has no valid email for password reset. Please contact support.';
          _isLoading = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PasswordResetEmailPage(
            email: userEmail,
            userId: userId,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const brandGreen = Color(0xFF4CAF50);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Reset Password',
          style: TextStyle(color: Colors.black87, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Text(
                'Find Your Account',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your email address to find your account.',
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  hintText: 'you@example.com',
                  prefixIcon: const Icon(Icons.email),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (_errorMessage != null) const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _findAccountByEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Find Account',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
