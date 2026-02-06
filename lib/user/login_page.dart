import 'package:flutter/material.dart';
import 'home_page.dart';
import 'register_page.dart';
import 'password_reset_selection_page.dart';
import '../expert/expert_dashboard.dart';
import '../about_app_page.dart';
import '../head_veterinarian/veterinarian_dashboard.dart';
import '../machine_learning_expert/ml_expert_dashboard.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive/hive.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  final _formKey = GlobalKey<FormState>();
  bool _hasValidated = false;
  Map<String, String?> _fieldErrors = {};

  // Email/password only (Google sign-in removed).

  // DEV convenience: prefill password to reduce switching friction.
  // Remove before release.
  static const String _defaultPassword = '@Sherwen24';

  @override
  void initState() {
    super.initState();
    _passwordController.text = _defaultPassword;
  }

  String _normalizeRole(dynamic role) {
    final r = (role ?? '').toString().trim().toLowerCase();
    if (r == 'head_veterinarian' || r == 'head veterinarian')
      return 'veterinarian';
    if (r == 'machine_learning_expert' ||
        r == 'machine learning expert' ||
        r == 'ml_expert' ||
        r == 'ml expert') {
      return 'machine_learning_expert';
    }
    return r;
  }

  // Google sign-in removed (email/password only).

  void _handleLogin() async {
    setState(() {
      _hasValidated = true;
      _fieldErrors = {
        'email':
            _emailController.text.trim().isEmpty
                ? 'Please enter your email'
                : null,
        'password':
            _passwordController.text.trim().isEmpty
                ? 'Please enter your password'
                : null,
      };
    });

    if (_fieldErrors.values.any((error) => error != null && error.isNotEmpty)) {
      return;
    }

    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final email = _emailController.text.trim();
        final password = _passwordController.text.trim();

        // First, check if the email exists in Firestore
        final usersQuery =
            await FirebaseFirestore.instance
                .collection('users')
                .where('email', isEqualTo: email)
                .limit(1)
                .get();

        if (usersQuery.docs.isEmpty) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Email address "$email" is not registered. Please check your email or create a new account.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
          return;
        }

        // Email exists, now try to sign in
        UserCredential userCredential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);

        final user = userCredential.user;
        if (user != null) {
          // Fetch user profile from Firestore
          DocumentSnapshot userDoc =
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get();

          if (userDoc.exists) {
            final data = userDoc.data() as Map<String, dynamic>;
            final role = _normalizeRole(data['role']);
            final status = data['status'];

            // Debug: Print user data to console
            print('User data: $data');
            print('Role: $role, Status: $status');

            if (status != 'active') {
              setState(() {
                _isLoading = false;
              });
              String roleText = role == 'expert' ? 'expert' : 'farmer';
              String statusText = status ?? 'inactive';
              String statusMessage = '';

              // Create friendly status messages
              switch (statusText) {
                case 'pending':
                  statusMessage =
                      'Your $roleText account is pending approval. You will receive an email notification once your account is approved by an administrator.';
                  break;
                case 'rejected':
                case 'declined':
                  statusMessage =
                      'Your $roleText account has been declined. Please contact support for more information.';
                  break;
                case 'suspended':
                case 'banned':
                  statusMessage =
                      'Your $roleText account has been suspended. Please contact support for assistance.';
                  break;
                default:
                  statusMessage =
                      'Your $roleText account is currently $statusText. Please contact support for assistance.';
              }

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(statusMessage),
                  backgroundColor:
                      statusText == 'pending' ? Colors.orange : Colors.red,
                  duration: const Duration(seconds: 5),
                ),
              );
            } else if (role == 'farmer') {
              // Ensure FCM token is saved so server can notify
              try {
                final token = await FirebaseMessaging.instance.getToken();
                if (token != null) {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .set({'fcmToken': token}, SetOptions(merge: true));
                }
              } catch (_) {}
              // Save login state and user info to Hive
              final userBox = await Hive.openBox('userBox');
              await userBox.put('isLoggedIn', true);
              await userBox.put('userProfile', {
                'fullName': data['fullName'] ?? '',
                'email': data['email'] ?? '',
                'phoneNumber': data['phoneNumber'] ?? '',
                'address': data['address'] ?? '',
                'role': role,
                'imageProfile': data['imageProfile'] ?? '',
                'userId': user.uid,
              });
              // Navigate to HomePage for farmer
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const HomePage()),
                (route) => false,
              );
            } else if (role == 'veterinarian') {
              // Save login state and veterinarian info to Hive
              final userBox = await Hive.openBox('userBox');
              await userBox.put('isLoggedIn', true);
              await userBox.put('userProfile', {
                'fullName': data['fullName'] ?? '',
                'email': data['email'] ?? '',
                'phoneNumber': data['phoneNumber'] ?? '',
                'address': data['address'] ?? '',
                'role': role,
                'imageProfile': data['imageProfile'] ?? '',
                'userId': user.uid,
              });
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const VeterinarianDashboard(),
                ),
              );
            } else if (role == 'expert') {
              // Ensure FCM token is saved for expert too
              try {
                final token = await FirebaseMessaging.instance.getToken();
                if (token != null) {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .set({'fcmToken': token}, SetOptions(merge: true));
                }
              } catch (_) {}
              // Save login state and expert info to Hive
              final userBox = await Hive.openBox('userBox');
              await userBox.put('isLoggedIn', true);
              await userBox.put('userProfile', {
                'fullName': data['fullName'] ?? '',
                'email': data['email'] ?? '',
                'phoneNumber': data['phoneNumber'] ?? '',
                'address': data['address'] ?? '',
                'role': role,
                'imageProfile': data['imageProfile'] ?? '',
                'userId': user.uid,
              });
              // Navigate to ExpertDashboard for expert
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const ExpertDashboard(),
                ),
              );
            } else if (role == 'machine_learning_expert') {
              final userBox = await Hive.openBox('userBox');
              await userBox.put('isLoggedIn', true);
              await userBox.put('userProfile', {
                'fullName': data['fullName'] ?? '',
                'email': data['email'] ?? '',
                'phoneNumber': data['phoneNumber'] ?? '',
                'address': data['address'] ?? '',
                'role': role,
                'imageProfile': data['imageProfile'] ?? '',
                'userId': user.uid,
              });
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (_) => const MachineLearningExpertDashboard(),
                ),
                (route) => false,
              );
            } else if (role == 'admin') {
              setState(() {
                _isLoading = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Admin accounts should use the admin login portal.',
                  ),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 4),
                ),
              );
            } else {
              setState(() {
                _isLoading = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Unknown user role: $role. Please contact support.',
                  ),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          } else {
            setState(() {
              _isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'User profile not found. Please contact support.',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } on FirebaseAuthException catch (e) {
        setState(() {
          _isLoading = false;
        });

        String message;
        Color backgroundColor;

        switch (e.code) {
          case 'wrong-password':
          case 'invalid-credential':
          case 'INVALID_LOGIN_CREDENTIALS':
            message =
                'Incorrect email or password. Please check your credentials and try again.';
            backgroundColor = Colors.red;
            break;
          case 'user-not-found':
            message =
                'Email address not found. Please check your email or create a new account.';
            backgroundColor = Colors.orange;
            break;
          case 'invalid-email':
            message = 'Please enter a valid email address.';
            backgroundColor = Colors.orange;
            break;
          case 'user-disabled':
            message = 'This account has been disabled. Please contact support.';
            backgroundColor = Colors.red;
            break;
          case 'too-many-requests':
            message =
                'Too many failed login attempts. Please try again later or reset your password.';
            backgroundColor = Colors.orange;
            break;
          case 'network-request-failed':
            message =
                'Network error. Please check your internet connection and try again.';
            backgroundColor = Colors.orange;
            break;
          case 'operation-not-allowed':
            message =
                'Email/password sign-in is not enabled. Please contact support.';
            backgroundColor = Colors.red;
            break;
          case 'weak-password':
            message =
                'Password is too weak. Please choose a stronger password.';
            backgroundColor = Colors.orange;
            break;
          default:
            // Show the actual error code for debugging purposes
            message =
                'Login failed: ${e.code}. Please try again or contact support.';
            backgroundColor = Colors.red;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: backgroundColor,
            duration: const Duration(seconds: 4),
          ),
        );
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An unexpected error occurred: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const brandGreen = Color(0xFF4CAF50);
    final greyFill = Colors.grey.shade200;

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey,
          letterSpacing: 0.4,
        ),
      ),
    );

    InputDecoration fieldDecoration({
      required String hint,
      bool hasError = false,
    }) {
      return InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
        filled: true,
        fillColor: hasError ? Colors.redAccent.withOpacity(0.08) : greyFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? Colors.redAccent : brandGreen,
            width: 1.2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top header (green with rounded bottom-right)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 18, bottom: 18),
              decoration: const BoxDecoration(
                color: brandGreen,
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(70),
                ),
              ),
              child: Center(
                child: Container(
                  width: 220,
                  height: 155,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(70),
                    ),
                  ),
                  child: Center(
                    child: Image.asset(
                      'assets/applogo_header.png',
                      width: 96,
                      height: 96,
                    ),
                  ),
                ),
              ),
            ),
            // Form area
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 380),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 18,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewInsets.bottom,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 6),
                            const Center(
                              child: Text(
                                'OinkCheck',
                                style: TextStyle(
                                  color: brandGreen,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Center(
                              child: Text(
                                'Sign in to continue.',
                                style: TextStyle(
                                  color: Colors.black38,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),

                            // NAME
                            label('NAME'),
                            TextField(
                              key: const ValueKey('textfield_email'),
                              controller: _emailController,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 14,
                              ),
                              keyboardType: TextInputType.emailAddress,
                              onChanged: (value) {
                                if (_hasValidated) {
                                  setState(() {
                                    _fieldErrors['email'] =
                                        value.trim().isEmpty
                                            ? 'Please enter your email'
                                            : null;
                                  });
                                }
                              },
                              decoration: fieldDecoration(
                                hint: 'username or email',
                                hasError:
                                    _hasValidated &&
                                    _fieldErrors['email'] != null,
                              ),
                            ),
                            if (_hasValidated &&
                                _fieldErrors['email'] != null &&
                                _fieldErrors['email']!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6, left: 6),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _fieldErrors['email']!,
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 14),

                            // PASSWORD
                            label('PASSWORD'),
                            TextField(
                              key: const ValueKey('textfield_password'),
                              controller: _passwordController,
                              obscureText:
                                  true, // match reference (no eye icon)
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 14,
                              ),
                              onChanged: (value) {
                                if (_hasValidated) {
                                  setState(() {
                                    _fieldErrors['password'] =
                                        value.trim().isEmpty
                                            ? 'Please enter your password'
                                            : null;
                                  });
                                }
                              },
                              decoration: fieldDecoration(
                                hint: '••••••••',
                                hasError:
                                    _hasValidated &&
                                    _fieldErrors['password'] != null,
                              ),
                            ),
                            if (_hasValidated &&
                                _fieldErrors['password'] != null &&
                                _fieldErrors['password']!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6, left: 6),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _fieldErrors['password']!,
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 18),

                            // Login Button
                            SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: brandGreen,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child:
                                    _isLoading
                                        ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                          ),
                                        )
                                        : const Text(
                                          'Log in',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                              ),
                            ),

                            const SizedBox(height: 10),

                            // Forgot Password
                            TextButton(
                              onPressed:
                                  () => _showForgotPasswordDialog(context),
                              child: const Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  color: Colors.black38,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),

                            const SizedBox(height: 2),

                            // Bottom links
                            Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (context) => const RegisterPage(),
                                        ),
                                      );
                                    },
                                    child: const Text(
                                      'Signup !',
                                      style: TextStyle(
                                        color: brandGreen,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  TextButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (context) => const AboutAppPage(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.info_outline,
                                      color: brandGreen,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'About',
                                      style: TextStyle(
                                        color: brandGreen,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showForgotPasswordDialog(BuildContext context) {
    // Navigate to password reset selection page
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PasswordResetSelectionPage(),
      ),
    );
  }
}
