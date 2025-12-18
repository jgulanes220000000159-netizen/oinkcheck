import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'login_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class RegisterPage extends StatefulWidget {
  const RegisterPage({Key? key}) : super(key: key);

  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedTerms = false;
  bool _hasValidated = false;
  Map<String, String?> _fieldErrors = {};

  // Location state (Philippines: Province → City/Municipality → Barangay)
  List<Map<String, String>> _provinces = [];
  List<Map<String, String>> _cities = [];
  List<Map<String, String>> _barangays = [];

  String? _selectedProvinceCode;
  String? _selectedCityCode;

  String? _selectedProvinceName;
  String? _selectedCityName;
  String? _selectedBarangayName;

  // Password strength tracking
  String _passwordStrength = '';
  Color _passwordStrengthColor = Colors.grey;

  // Password strength calculation
  void _calculatePasswordStrength(String password) {
    bool hasLength = password.length >= 8;
    bool hasUppercase = password.contains(RegExp(r'[A-Z]'));
    bool hasLowercase = password.contains(RegExp(r'[a-z]'));
    bool hasNumber = password.contains(RegExp(r'[0-9]'));
    bool hasSpecialChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

    setState(() {
      // Check if all required criteria are met (length, uppercase, lowercase, number)
      bool meetsRequirements =
          hasLength && hasUppercase && hasLowercase && hasNumber;

      if (!hasLength || (!hasUppercase && !hasLowercase && !hasNumber)) {
        _passwordStrength = 'Weak';
        _passwordStrengthColor = Colors.red;
      } else if (!meetsRequirements) {
        _passwordStrength = 'Medium';
        _passwordStrengthColor = Colors.orange;
      } else {
        // All requirements met, check if it has special characters for bonus
        _passwordStrength = hasSpecialChar ? 'Strong' : 'Good';
        _passwordStrengthColor =
            hasSpecialChar ? Colors.green : Colors.lightGreen;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadProvinces();
  }

  // --- Location loading using PSGC API (Philippines) ---
  Future<void> _loadProvinces() async {
    try {
      final response = await http
          .get(Uri.parse('https://psgc.gitlab.io/api/provinces/'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _provinces = data
              .map<Map<String, String>>(
                (p) => {
                  'code': p['code']?.toString() ?? '',
                  'name': p['name']?.toString() ?? '',
                },
              )
              .where((p) => p['code']!.isNotEmpty && p['name']!.isNotEmpty)
              .toList()
            ..sort(
              (a, b) => a['name']!.compareTo(b['name']!),
            );
        });
      }
    } catch (_) {
      // Fail silently – user can still type full address
    }
  }

  Future<void> _loadCitiesForProvince(String provinceCode) async {
    setState(() {
      _cities = [];
      _barangays = [];
      _selectedCityCode = null;
      _selectedCityName = null;
      _selectedBarangayName = null;
    });
    try {
      final response = await http.get(
        Uri.parse('https://psgc.gitlab.io/api/cities-municipalities/'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final filtered = data.where((c) {
          final pCode = (c['provinceCode'] ?? c['province_code'])?.toString();
          return pCode == provinceCode;
        }).toList();
        setState(() {
          _cities = filtered
              .map<Map<String, String>>(
                (c) => {
                  'code': c['code']?.toString() ?? '',
                  'name': c['name']?.toString() ?? '',
                },
              )
              .where((c) => c['code']!.isNotEmpty && c['name']!.isNotEmpty)
              .toList()
            ..sort(
              (a, b) => a['name']!.compareTo(b['name']!),
            );
        });
      }
    } catch (_) {}
  }

  Future<void> _loadBarangaysForCity(String cityCode) async {
    setState(() {
      _barangays = [];
      _selectedBarangayName = null;
    });
    try {
      final response = await http.get(
        Uri.parse('https://psgc.gitlab.io/api/barangays/'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final filtered = data.where((b) {
          final cCode = (b['cityCode'] ?? b['city_code'])?.toString();
          return cCode == cityCode;
        }).toList();
        setState(() {
          _barangays = filtered
              .map<Map<String, String>>(
                (b) => {
                  'code': b['code']?.toString() ?? '',
                  'name': b['name']?.toString() ?? '',
                },
              )
              .where((b) => b['code']!.isNotEmpty && b['name']!.isNotEmpty)
              .toList()
            ..sort(
              (a, b) => a['name']!.compareTo(b['name']!),
            );
        });
      }
    } catch (_) {}
  }

  // Form validation
  String? _validateFullName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your full name';
    }
    if (value.trim().length < 2) {
      return 'Name must be at least 2 characters';
    }
    return null;
  }

  String? _validateAddress(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your address';
    }
    if (value.trim().length < 5) {
      return 'Please enter a complete address';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your phone number';
    }
    // Philippine phone number validation: 09XXXXXXXXX (11 digits starting with 09)
    final phoneRegex = RegExp(r'^09\d{9}$');
    String cleanNumber = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (!phoneRegex.hasMatch(cleanNumber)) {
      return 'Please enter a valid mobile number (09XXXXXXXXX)';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your email';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!value.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!value.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter';
    }
    if (!value.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  void _handleRegister() async {
    setState(() {
      _hasValidated = true;
      // Validate all fields and store errors
      _fieldErrors = {
        'fullName': _validateFullName(_fullNameController.text),
        'address': _validateAddress(_addressController.text),
        'phone': _validatePhone(_phoneController.text),
        'email': _validateEmail(_emailController.text),
        'password': _validatePassword(_passwordController.text),
        'confirmPassword': _validateConfirmPassword(
          _confirmPasswordController.text,
        ),
      };
    });
    // Check if there are any validation errors
    if (_fieldErrors.values.any((error) => error != null && error.isNotEmpty)) {
      return;
    }

    if (!_acceptedTerms) {
      _showErrorDialog('Please accept the Terms and Conditions to continue.');
      return;
    }

    // Ensure address selections are made
    if (_selectedProvinceName == null ||
        _selectedCityName == null ||
        _selectedBarangayName == null) {
      _showErrorDialog(
        'Please select your Province, City/Municipality, and Barangay.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Create user with Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );
      final user = userCredential.user;
      if (user != null) {
        // Save user profile to Firestore
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'userId': user.uid,
          'fullName': _fullNameController.text.trim(),
          // Street / Purok / House no.
          'street': _addressController.text.trim(),
          'province': _selectedProvinceName,
          'cityMunicipality': _selectedCityName,
          'barangay': _selectedBarangayName,
          // Combined address for display/search
          'address':
              '${_addressController.text.trim()}, $_selectedBarangayName, $_selectedCityName, $_selectedProvinceName',
          'phoneNumber': _phoneController.text.trim(),
          'email': _emailController.text.trim(),
          'role': 'farmer',
          'status': 'pending',
          'imageProfile': '',
          'createdAt': DateTime.now(),
        });
      }
      setState(() {
        _isLoading = false;
      });

      // Show success dialog
      _showSuccessDialog();
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isLoading = false;
      });
      String message = 'Registration failed.';
      if (e.code == 'email-already-in-use') {
        message = 'Email already in use. Please use a different email.';
      } else if (e.code == 'weak-password') {
        message = 'Password is too weak. Please choose a stronger password.';
      } else if (e.code == 'invalid-email') {
        message = 'Please enter a valid email address.';
      } else if (e.code == 'operation-not-allowed') {
        message = 'Email/password accounts are not enabled.';
      }
      _showErrorDialog(message);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorDialog('An unexpected error occurred. Please try again.');
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 28),
                SizedBox(width: 12),
                Text('Success!', style: TextStyle(color: Colors.green)),
              ],
            ),
            content: Text(
              'Account created successfully! Your account is now pending admin approval. You will receive an email notification once your account is approved. Please use the login page to check your account status.',
              style: TextStyle(fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                    (route) => false,
                  );
                },
                child: Text(
                  'Continue to Login',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Registration Failed',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Text(message, style: TextStyle(fontSize: 16)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
    );
  }

  void _showTermsAndConditions() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.description, color: Colors.green, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Terms and Conditions',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'OinkCheck Terms of Service',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Last Updated: November 16, 2025\n',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  _buildTermsSection(
                    '1. Acceptance of Terms',
                    'By registering for and using OinkCheck, you agree to be bound by these Terms and Conditions. If you do not agree to these terms, please do not use this application.',
                  ),
                  _buildTermsSection(
                    '2. Service Description',
                    'OinkCheck is an agricultural technology application designed to assist pig farmers in detecting and identifying pig diseases using artificial intelligence and machine learning technology. The application provides diagnostic suggestions based on image analysis.',
                  ),
                  _buildTermsSection(
                    '3. User Account and Registration',
                    '• You must provide accurate and complete information during registration.\n'
                        '• You are responsible for maintaining the confidentiality of your account credentials.\n'
                        '• Your account is subject to admin approval before activation.',
                  ),
                  _buildTermsSection(
                    '4. Use of Service',
                    '• The application is intended for agricultural and educational purposes only.\n'
                        '• Disease detection results are advisory and should not replace professional agricultural consultation.\n'
                        '• You agree to use the service in compliance with all applicable laws and regulations.\n'
                        '• You will not misuse, abuse, or attempt to manipulate the service.',
                  ),
                  _buildTermsSection(
                    '5. Data Privacy and Collection',
                    '• We collect personal information including name, address, phone number, and email for account management.\n'
                        '• Images uploaded for disease detection may be stored and analyzed.\n'
                        '• Your data will be handled in accordance with applicable data privacy laws.\n'
                        '• We will not share your personal information with third parties without consent, except as required by law.',
                  ),
                  _buildTermsSection(
                    '6. Disclaimer of Warranties',
                    '• OinkCheck is provided "as is" without warranties of any kind.\n'
                        '• We do not guarantee 100% accuracy in disease detection.\n'
                        '• Results should be verified by qualified veterinary professionals.\n'
                        '• We are not liable for livestock losses or damages resulting from reliance on app recommendations.',
                  ),
                  _buildTermsSection(
                    '7. Limitation of Liability',
                    'OinkCheck, its developers, and administrators shall not be liable for any indirect, incidental, special, or consequential damages arising from the use or inability to use this service.',
                  ),
                  _buildTermsSection(
                    '8. Intellectual Property',
                    'All content, features, and functionality of OinkCheck are owned by the application developers and are protected by copyright and intellectual property laws.',
                  ),
                  _buildTermsSection(
                    '9. Account Termination',
                    'We reserve the right to suspend or terminate accounts that violate these terms or engage in fraudulent, abusive, or illegal activities.',
                  ),
                  _buildTermsSection(
                    '10. Changes to Terms',
                    'We reserve the right to modify these Terms and Conditions at any time. Continued use of the service after changes constitutes acceptance of modified terms.',
                  ),
                  _buildTermsSection(
                    '11. Contact Information',
                    'For questions, concerns, or support regarding these terms or the OinkCheck service, please contact us through the application support channels.',
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Text(
                      'By clicking "I Accept," you acknowledge that you have read, understood, and agree to be bound by these Terms and Conditions.',
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Close', style: TextStyle(color: Colors.grey[600])),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _acceptedTerms = true;
                  });
                  Navigator.of(context).pop();
                },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                child: Text('I Accept', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
    );
  }

  Widget _buildTermsSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          SizedBox(height: 4),
          Text(content, style: TextStyle(fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String fieldKey,
    bool isPassword = false,
    bool? obscureText,
    Widget? suffixIcon,
    IconData? prefixIcon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    void Function(String)? onChanged,
  }) {
    final errorText = _hasValidated ? _fieldErrors[fieldKey] : null;
    final hasError = errorText != null && errorText.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Builder(
          builder:
              (context) => Theme(
                data: Theme.of(context).copyWith(
                  textTheme: Theme.of(context).textTheme.apply(
                    bodyColor: Colors.white,
                    displayColor: Colors.white,
                  ),
                  colorScheme: Theme.of(context).colorScheme.copyWith(
                    error: Colors.redAccent,
                    onError: Colors.white,
                    onSurface: Colors.white,
                  ),
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(color: Colors.white),
                  child: TextField(
                    key: ValueKey('textfield_$fieldKey'),
                    controller: controller,
                    obscureText: isPassword ? (obscureText ?? true) : false,
                    style: const TextStyle(
                      color: Colors.white,
                      decorationColor: Colors.white,
                      fontSize: 16,
                    ),
                    cursorColor: Colors.white,
                    strutStyle: const StrutStyle(
                      fontSize: 16,
                      height: 1.0,
                      leading: 0,
                    ),
                    keyboardType: keyboardType,
                    inputFormatters: inputFormatters,
                    onChanged: (value) {
                      if (onChanged != null) onChanged(value);
                      if (_hasValidated && _fieldErrors.containsKey(fieldKey)) {
                        setState(() {
                          _fieldErrors[fieldKey] = validator?.call(value);
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: label,
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor:
                          hasError
                              ? Colors.redAccent.withOpacity(0.1)
                              : Colors.transparent,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: hasError ? Colors.redAccent : Colors.white70,
                          width: hasError ? 1.5 : 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: hasError ? Colors.redAccent : Colors.white,
                          width: hasError ? 1.5 : 1,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                          width: 1.5,
                        ),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                          width: 1.5,
                        ),
                      ),
                      prefixIcon:
                          prefixIcon != null
                              ? Icon(prefixIcon, color: Colors.white70)
                              : null,
                      suffixIcon: suffixIcon,
                      errorStyle: const TextStyle(height: 0, fontSize: 0),
                    ),
                  ),
                ),
              ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 6, right: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      errorText ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green, // Keep green background
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20.0,
              vertical: 16.0,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Logo and App Name
                  Center(
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(6),
                          child: Image.asset(
                            'assets/applogo_header.png',
                            width: 56,
                            height: 56,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Oink',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Check',
                              style: TextStyle(
                                color: Colors.yellow,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Sign Up Text
                  const Text(
                    'Sign Up!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Create an account, it\'s free',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  // Form Fields
                  _buildTextField(
                    label: 'Full Name',
                    controller: _fullNameController,
                    fieldKey: 'fullName',
                    prefixIcon: Icons.person,
                    validator: _validateFullName,
                    keyboardType: TextInputType.name,
                  ),
                  const SizedBox(height: 12),
                  // Province / City / Barangay selectors
                  const SizedBox(height: 12),
                  Text(
                    'Address',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    dropdownColor: Colors.green[700],
                    decoration: InputDecoration(
                      labelText: 'Province',
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.green[600],
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Colors.white70, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Colors.white, width: 1.5),
                      ),
                    ),
                    iconEnabledColor: Colors.white,
                    value: _selectedProvinceName,
                    items: _provinces
                        .map(
                          (p) => DropdownMenuItem<String>(
                            value: p['name'],
                            child: Text(
                              p['name']!,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedProvinceName = value;
                        final match = _provinces.firstWhere(
                          (p) => p['name'] == value,
                          orElse: () => {'code': '', 'name': ''},
                        );
                        _selectedProvinceCode = match['code'];
                      });
                      if (_selectedProvinceCode != null &&
                          _selectedProvinceCode!.isNotEmpty) {
                        _loadCitiesForProvince(_selectedProvinceCode!);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    dropdownColor: Colors.green[700],
                    decoration: InputDecoration(
                      labelText: 'City / Municipality',
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.green[600],
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Colors.white70, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Colors.white, width: 1.5),
                      ),
                    ),
                    iconEnabledColor: Colors.white,
                    value: _selectedCityName,
                    items: _cities
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c['name'],
                            child: Text(
                              c['name']!,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedCityName = value;
                        final match = _cities.firstWhere(
                          (c) => c['name'] == value,
                          orElse: () => {'code': '', 'name': ''},
                        );
                        _selectedCityCode = match['code'];
                      });
                      if (_selectedCityCode != null &&
                          _selectedCityCode!.isNotEmpty) {
                        _loadBarangaysForCity(_selectedCityCode!);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    dropdownColor: Colors.green[700],
                    decoration: InputDecoration(
                      labelText: 'Barangay',
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.green[600],
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Colors.white70, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Colors.white, width: 1.5),
                      ),
                    ),
                    iconEnabledColor: Colors.white,
                    value: _selectedBarangayName,
                    items: _barangays
                        .map(
                          (b) => DropdownMenuItem<String>(
                            value: b['name'],
                            child: Text(
                              b['name']!,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedBarangayName = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    label: 'Street / Purok / House No.',
                    controller: _addressController,
                    fieldKey: 'address',
                    prefixIcon: Icons.home,
                    validator: _validateAddress,
                    keyboardType: TextInputType.streetAddress,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    label: 'Phone Number',
                    controller: _phoneController,
                    fieldKey: 'phone',
                    prefixIcon: Icons.phone,
                    validator: _validatePhone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(15),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    label: 'Email',
                    controller: _emailController,
                    fieldKey: 'email',
                    prefixIcon: Icons.email,
                    validator: _validateEmail,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    label: 'Password',
                    controller: _passwordController,
                    fieldKey: 'password',
                    isPassword: true,
                    obscureText: _obscurePassword,
                    validator: _validatePassword,
                    onChanged: _calculatePasswordStrength,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    prefixIcon: Icons.lock,
                  ),
                  // Password Strength Indicator
                  if (_passwordController.text.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Password Strength: ',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _passwordStrengthColor,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            _passwordStrength,
                            style: TextStyle(
                              color: _passwordStrengthColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.white30, width: 1),
                      ),
                      child: LinearProgressIndicator(
                        value:
                            _passwordStrength == 'Weak'
                                ? 0.3
                                : _passwordStrength == 'Medium'
                                ? 0.6
                                : 1.0,
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _passwordStrengthColor,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _buildTextField(
                    label: 'Confirm Password',
                    controller: _confirmPasswordController,
                    fieldKey: 'confirmPassword',
                    isPassword: true,
                    obscureText: _obscureConfirmPassword,
                    validator: _validateConfirmPassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                    prefixIcon: Icons.lock_outline,
                  ),
                  const SizedBox(height: 12),
                  // Terms and Conditions Checkbox
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _acceptedTerms,
                        onChanged: (value) {
                          setState(() {
                            _acceptedTerms = value ?? false;
                          });
                        },
                        activeColor: Colors.white,
                        checkColor: Colors.green,
                        side: BorderSide(color: Colors.white70, width: 2),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: GestureDetector(
                            onTap: _showTermsAndConditions,
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                                children: [
                                  TextSpan(text: 'I agree to the '),
                                  TextSpan(
                                    text: 'Terms and Conditions',
                                    style: TextStyle(
                                      color: Colors.yellow,
                                      fontWeight: FontWeight.bold,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Register Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleRegister,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child:
                          _isLoading
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.green,
                                  ),
                                ),
                              )
                              :                               const Text(
                                'Create Account',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Login Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Already have an account? ',
                        style: TextStyle(color: Colors.white70),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LoginPage(),
                            ),
                            (route) => false,
                          );
                        },
                        child: const Text(
                          'Sign In',
                          style: TextStyle(
                            color: Colors.yellow,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
