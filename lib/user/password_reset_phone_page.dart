import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'dart:math';

/// Phone-based password reset (OTP flow).
class PasswordResetPhonePage extends StatefulWidget {
  final String phoneNumber;
  final String userId;

  const PasswordResetPhonePage({
    Key? key,
    required this.phoneNumber,
    required this.userId,
  }) : super(key: key);

  @override
  _PasswordResetPhonePageState createState() => _PasswordResetPhonePageState();
}

class _PasswordResetPhonePageState extends State<PasswordResetPhonePage> {
  int _currentStep = 0; // 0: request OTP, 1: verify OTP, 2: new password
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  Future<void> _requestOTP() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Generate 6-digit OTP
      final otp = (100000 + Random().nextInt(900000)).toString();

      // Store OTP in Firestore with 10-minute expiration
      await FirebaseFirestore.instance
          .collection('password_reset_otps')
          .doc(widget.userId)
          .set({
            'otp': otp,
            'phoneNumber': widget.phoneNumber,
            'createdAt': FieldValue.serverTimestamp(),
            'expiresAt':
                DateTime.now()
                    .add(const Duration(minutes: 10))
                    .toIso8601String(),
            'used': false,
          });

      // TODO: Call Firebase Cloud Function to send SMS
      // For now, we'll show the OTP in a dialog for testing
      // In production, remove this and use the Cloud Function
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => AlertDialog(
                title: const Text('OTP (Testing Only)'),
                content: Text(
                  'OTP: $otp\n\nIn production, this will be sent via SMS.',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
        );
      }

      // Call Cloud Function to send SMS (if deployed)
      try {
        final firebaseFunctions = functions.FirebaseFunctions.instance;
        final callable = firebaseFunctions.httpsCallable(
          'sendPasswordResetOTP',
        );
        await callable.call({'phoneNumber': widget.phoneNumber, 'otp': otp});
      } catch (e) {
        // Cloud Function not deployed yet - that's OK for testing
        // OTP is already stored in Firestore, so user can still verify
        print('Cloud Function not available (testing mode): $e');
      }

      setState(() {
        _currentStep = 1;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to send OTP. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyOTP() async {
    final enteredOtp = _otpController.text.trim();

    if (enteredOtp.isEmpty || enteredOtp.length != 6) {
      setState(() {
        _errorMessage = 'Please enter the 6-digit OTP code.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final otpDoc =
          await FirebaseFirestore.instance
              .collection('password_reset_otps')
              .doc(widget.userId)
              .get();

      if (!otpDoc.exists) {
        setState(() {
          _errorMessage = 'OTP not found. Please request a new one.';
          _isLoading = false;
        });
        return;
      }

      final data = otpDoc.data() as Map<String, dynamic>;
      final storedOtp = data['otp'] as String?;
      final expiresAt = data['expiresAt'] as String?;
      final used = data['used'] as bool? ?? false;

      if (used) {
        setState(() {
          _errorMessage =
              'This OTP has already been used. Please request a new one.';
          _isLoading = false;
        });
        return;
      }

      if (expiresAt != null) {
        final expiry = DateTime.parse(expiresAt);
        if (DateTime.now().isAfter(expiry)) {
          setState(() {
            _errorMessage = 'OTP has expired. Please request a new one.';
            _isLoading = false;
          });
          return;
        }
      }

      if (enteredOtp != storedOtp) {
        setState(() {
          _errorMessage = 'Invalid OTP code. Please try again.';
          _isLoading = false;
        });
        return;
      }

      // Mark OTP as used
      await FirebaseFirestore.instance
          .collection('password_reset_otps')
          .doc(widget.userId)
          .update({'used': true});

      setState(() {
        _currentStep = 2;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Verification failed. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _resetPassword() async {
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (newPassword.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a new password.';
      });
      return;
    }

    if (newPassword.length < 8) {
      setState(() {
        _errorMessage = 'Password must be at least 8 characters.';
      });
      return;
    }

    if (newPassword != confirmPassword) {
      setState(() {
        _errorMessage = 'Passwords do not match.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Call Cloud Function to reset password using Admin SDK
      final firebaseFunctions = functions.FirebaseFunctions.instance;
      final callable = firebaseFunctions.httpsCallable('resetPasswordByPhone');
      await callable.call({
        'userId': widget.userId,
        'newPassword': newPassword,
      });

      // Success - show success message and navigate back
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Password Reset Successful'),
                  ],
                ),
                content: const Text(
                  'Your password has been reset successfully. You can now log in with your new password.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context); // Close dialog
                      Navigator.popUntil(context, (route) => route.isFirst);
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
        );
      }
    } catch (e) {
      String errorMessage = 'Failed to reset password. Please try again.';
      // Check if it's a Firebase Functions error
      if (e.toString().contains('not-found')) {
        errorMessage = 'User not found. Please contact support.';
      } else if (e.toString().contains('invalid-argument')) {
        errorMessage = 'Invalid password. Please try again.';
      } else if (e.toString().contains('functions')) {
        errorMessage =
            'Password reset requires Cloud Function. Please use email reset or contact support.';
      }
      setState(() {
        _errorMessage = errorMessage;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
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
              // Progress indicator
              Row(
                children: [
                  _buildStepIndicator(0, 'Request', _currentStep >= 0),
                  Expanded(child: _buildStepLine(_currentStep > 0)),
                  _buildStepIndicator(1, 'Verify', _currentStep >= 1),
                  Expanded(child: _buildStepLine(_currentStep > 1)),
                  _buildStepIndicator(2, 'Reset', _currentStep >= 2),
                ],
              ),
              const SizedBox(height: 32),
              if (_currentStep == 0) ...[
                // Step 1: Request OTP
                const Icon(Icons.phone, size: 64, color: brandGreen),
                const SizedBox(height: 24),
                const Text(
                  'Send OTP to Phone',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'We\'ll send a 6-digit code to:\n${widget.phoneNumber}',
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _requestOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child:
                        _isLoading
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                            : const Text(
                              'Send OTP',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                  ),
                ),
              ] else if (_currentStep == 1) ...[
                // Step 2: Verify OTP
                const Icon(Icons.lock_outline, size: 64, color: brandGreen),
                const SizedBox(height: 24),
                const Text(
                  'Enter OTP Code',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Enter the 6-digit code sent to your phone.',
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    hintText: '000000',
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child:
                        _isLoading
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                            : const Text(
                              'Verify OTP',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                  ),
                ),
                TextButton(
                  onPressed: _isLoading ? null : _requestOTP,
                  child: const Text('Resend OTP'),
                ),
              ] else if (_currentStep == 2) ...[
                // Step 3: New Password
                const Icon(Icons.lock_reset, size: 64, color: brandGreen),
                const SizedBox(height: 24),
                const Text(
                  'Create New Password',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _newPasswordController,
                  obscureText: _obscureNewPassword,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    hintText: 'Enter new password',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNewPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureNewPassword = !_obscureNewPassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    hintText: 'Confirm new password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _resetPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child:
                        _isLoading
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                            : const Text(
                              'Reset Password',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                  ),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 24),
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
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label, bool isActive) {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? const Color(0xFF4CAF50) : Colors.grey.shade300,
          ),
          child: Center(
            child: Text(
              '${step + 1}',
              style: TextStyle(
                color: isActive ? Colors.white : Colors.black54,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? Colors.black87 : Colors.black54,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(bool isActive) {
    return Container(
      height: 2,
      color: isActive ? const Color(0xFF4CAF50) : Colors.grey.shade300,
      margin: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}
