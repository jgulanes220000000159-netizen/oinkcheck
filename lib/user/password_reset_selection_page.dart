import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'password_reset_email_page.dart';
import 'password_reset_phone_page.dart';

/// Password reset method selection screen.
/// Shows options based on what the user has (email, phone, or both).
class PasswordResetSelectionPage extends StatefulWidget {
  const PasswordResetSelectionPage({Key? key}) : super(key: key);

  @override
  _PasswordResetSelectionPageState createState() =>
      _PasswordResetSelectionPageState();
}

class _PasswordResetSelectionPageState
    extends State<PasswordResetSelectionPage> {
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _hasEmail = false;
  bool _hasPhone = false;
  String? _userEmail;
  String? _userPhone;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _checkUserInfo();
  }

  Future<void> _checkUserInfo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final phone = _phoneController.text.trim();
      final email = _emailController.text.trim();

      if (phone.isEmpty && email.isEmpty) {
        setState(() {
          _errorMessage = 'Please enter your phone number or email address.';
          _isLoading = false;
        });
        return;
      }

      QuerySnapshot? query;

      // Search by phone first (if provided)
      if (phone.isNotEmpty) {
        query = await FirebaseFirestore.instance
            .collection('users')
            .where('phoneNumber', isEqualTo: phone)
            .limit(1)
            .get();
      }

      // If not found and email provided, search by email
      if ((query == null || query.docs.isEmpty) && email.isNotEmpty) {
        query = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
      }

      if (query == null || query.docs.isEmpty) {
        setState(() {
          _errorMessage =
              'No account found with the provided phone number or email.';
          _isLoading = false;
        });
        return;
      }

      final userDoc = query.docs.first;
      final data = userDoc.data() as Map<String, dynamic>;
      _userId = userDoc.id;
      _userEmail = (data['email'] as String?)?.trim() ?? '';
      _userPhone = (data['phoneNumber'] as String?)?.trim() ?? '';
      _hasEmail = _userEmail!.isNotEmpty &&
          !_userEmail!.endsWith('@oinkcheck.local');
      _hasPhone = _userPhone!.isNotEmpty;

      if (!_hasEmail && !_hasPhone) {
        setState(() {
          _errorMessage =
              'Account found but no email or phone number on file. Please contact support.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
        _isLoading = false;
      });
    }
  }

  void _handleMethodSelection(String method) {
    if (_userId == null) return;

    if (method == 'email' && _hasEmail) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PasswordResetEmailPage(
            email: _userEmail!,
            userId: _userId!,
          ),
        ),
      );
    } else if (method == 'phone' && _hasPhone) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PasswordResetPhonePage(
            phoneNumber: _userPhone!,
            userId: _userId!,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
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
                'Enter your phone number or email to find your account.',
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '09XXXXXXXXX',
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'OR',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black54,
                ),
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
                  onPressed: _isLoading ? null : _checkUserInfo,
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
              if (_hasEmail || _hasPhone) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 24),
                const Text(
                  'Choose Reset Method',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                if (_hasEmail && _hasPhone) ...[
                  // Both available - show choice
                  _buildMethodCard(
                    icon: Icons.email,
                    title: 'Send reset link to email',
                    subtitle: _userEmail,
                    onTap: () => _handleMethodSelection('email'),
                  ),
                  const SizedBox(height: 12),
                  _buildMethodCard(
                    icon: Icons.phone,
                    title: 'Send OTP to phone',
                    subtitle: _userPhone,
                    onTap: () => _handleMethodSelection('phone'),
                  ),
                ] else if (_hasEmail) ...[
                  // Only email
                  _buildMethodCard(
                    icon: Icons.email,
                    title: 'Send reset link to email',
                    subtitle: _userEmail,
                    onTap: () => _handleMethodSelection('email'),
                  ),
                ] else if (_hasPhone) ...[
                  // Only phone
                  _buildMethodCard(
                    icon: Icons.phone,
                    title: 'Send OTP to phone',
                    subtitle: _userPhone,
                    onTap: () => _handleMethodSelection('phone'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMethodCard({
    required IconData icon,
    required String title,
    required String? subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: const Color(0xFF4CAF50)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black54),
            ],
          ),
        ),
      ),
    );
  }
}
