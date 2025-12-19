import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../user/edit_profile_page.dart';
import '../user/login_page.dart';

class VeterinarianProfilePage extends StatefulWidget {
  const VeterinarianProfilePage({super.key});

  @override
  State<VeterinarianProfilePage> createState() => _VeterinarianProfilePageState();
}

class _VeterinarianProfilePageState extends State<VeterinarianProfilePage> {
  bool _loading = true;
  String _name = 'Veterinarian';
  String _email = '';
  String _memberSince = '—';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _logout() async {
    try {
      final box = await Hive.openBox('userBox');
      await box.put('isLoggedIn', false);
      await box.delete('userProfile');
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _load() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return;
      }

      // Try Firestore first
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final data = doc.data();
        if (data != null) {
          _name = (data['fullName'] ?? 'Veterinarian').toString();
          _email = (data['email'] ?? user.email ?? '').toString();
          final createdAt = data['createdAt'];
          if (createdAt is Timestamp) {
            final d = createdAt.toDate();
            _memberSince = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          } else if (createdAt is DateTime) {
            _memberSince = '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
          }
        }
      } catch (_) {
        // Fallback to Hive cached profile
        final box = await Hive.openBox('userBox');
        final profile = box.get('userProfile');
        if (profile is Map) {
          _name = (profile['fullName'] ?? 'Veterinarian').toString();
          _email = (profile['email'] ?? user.email ?? '').toString();
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildProfileOption({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.green),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          onTap: onTap,
        ),
        if (showDivider)
          Divider(height: 1, color: Colors.grey[200]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Header (same style as farmer/expert)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.only(
                          bottomRight: Radius.circular(50),
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.person,
                              size: 48,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _email,
                            style: TextStyle(color: Colors.white.withOpacity(0.9)),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                              ),
                            ),
                            child: const Text(
                              'veterinarian',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.calendar_today, color: Colors.green, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    _memberSince,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Member since',
                                    style: TextStyle(color: Colors.grey[700]),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Options card
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildProfileOption(
                            title: 'Edit Profile',
                            icon: Icons.edit,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const EditProfilePage(),
                                ),
                              );
                              // Refresh after editing
                              if (mounted) {
                                setState(() => _loading = true);
                                await _load();
                              }
                            },
                          ),
                          _buildProfileOption(
                            title: 'Change Password',
                            icon: Icons.lock,
                            onTap: () async {
                              final email = _email.trim();
                              if (email.isEmpty) return;
                              await FirebaseAuth.instance
                                  .sendPasswordResetEmail(email: email);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Password reset email sent to $email'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            },
                          ),
                          _buildProfileOption(
                            title: 'Logout',
                            icon: Icons.logout,
                            showDivider: false,
                            onTap: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Confirm logout'),
                                  content: const Text('Are you sure you want to logout?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text('Logout'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                await _logout();
                              }
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
    );
  }
}


