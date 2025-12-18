import 'package:flutter/material.dart';
import '../user/profile_page.dart';

class AppHeader extends StatelessWidget {
  final String? title;
  final VoidCallback? onProfileTap;
  final bool showProfileButton;

  const AppHeader({
    Key? key,
    this.title,
    this.onProfileTap,
    this.showProfileButton = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  // Pop all routes until first (home) if possible
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Image.asset(
                    'assets/applogo_header.png',
                    width: 37,
                    height: 37,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title ?? 'MangoSense',
                style: const TextStyle(
                  color: Colors.yellow,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (showProfileButton)
            GestureDetector(
              onTap:
                  onProfileTap ??
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfilePage(),
                      ),
                    );
                  },
              child: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, color: Colors.green),
              ),
            ),
        ],
      ),
    );
  }
}
