import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'user/login_page.dart';
import 'user/home_page.dart';
import 'user/register_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:easy_localization/easy_localization.dart';
import 'expert/expert_dashboard.dart';
import 'head_veterinarian/veterinarian_dashboard.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';
import 'shared/connectivity_service.dart';
import 'shared/no_internet_banner.dart';
import 'package:month_year_picker/month_year_picker.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      await Firebase.initializeApp();
      try {
        // Ensure Firestore offline cache is enabled
        await FirebaseFirestore.instance.enablePersistence();
      } catch (_) {}

      // Set Firebase Auth persistence to LOCAL (default)
      try {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      } catch (_) {}
      await Hive.initFlutter();
      await Hive.openBox('reviews'); // Open a box for review/request data
      await Hive.openBox('userBox'); // Box for login state and user profile
      await Hive.openBox('settings'); // Box for app settings (including locale)
      await Hive.openBox('notificationBox'); // Box for notification counts

      // Note: Android backup is disabled in AndroidManifest.xml
      // This ensures fresh installs don't have stale Hive data

      await EasyLocalization.ensureInitialized();
      await dotenv.load(); // Load environment variables
      await Supabase.initialize(
        url: dotenv.env['SUPABASE_URL']!,
        anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      );

      // Keep Hive login state in sync with Firebase Auth
      try {
        bool isFirstAuthCheck = true;
        FirebaseAuth.instance.authStateChanges().listen((user) async {
          // Skip the very first null event during app startup
          // Firebase Auth takes a moment to restore the session
          if (isFirstAuthCheck && user == null) {
            isFirstAuthCheck = false;
            return;
          }
          isFirstAuthCheck = false;

          final box = Hive.box('userBox');
          if (user == null) {
            // User actually signed out (not just app starting)
            await box.put('isLoggedIn', false);
            await box.delete('userProfile');
            return;
          }

          // Check user status before saving login state
          try {
            final doc =
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .get();

            if (doc.exists) {
              final data = doc.data() as Map<String, dynamic>;
              final status = data['status'];

              // Only save login state if user is active
              if (status == 'active') {
                await box.put('isLoggedIn', true);
                // Ensure minimal profile is saved locally for routing
                Map? profile = box.get('userProfile') as Map?;
                if (profile == null || profile['userId'] != user.uid) {
                  final updated = {
                    'userId': user.uid,
                    'fullName': data['fullName'] ?? profile?['fullName'] ?? '',
                    'email':
                        data['email'] ?? profile?['email'] ?? user.email ?? '',
                    'role': data['role'] ?? profile?['role'],
                  };
                  await box.put('userProfile', updated);
                }
              } else {
                // User is not active, clear any existing login state
                await box.put('isLoggedIn', false);
                await box.delete('userProfile');
              }
            } else {
              // User document doesn't exist, clear login state
              await box.put('isLoggedIn', false);
              await box.delete('userProfile');
            }
          } catch (_) {
            // On error, don't save login state
            await box.put('isLoggedIn', false);
            await box.delete('userProfile');
          }
        });
      } catch (_) {}

      // --- FCM Notification Setup ---
      final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
          FlutterLocalNotificationsPlugin();
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@drawable/ic_stat_notify');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);
      await flutterLocalNotificationsPlugin.initialize(initializationSettings);

      // Create Android notification channel (Android 8+)
      const AndroidNotificationChannel defaultChannel =
          AndroidNotificationChannel(
            'high_importance_v2',
            'High Importance Notifications',
            description:
                'Used for important notifications like reviews and requests',
            importance: Importance.high,
          );
      final androidPlugin =
          flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      await androidPlugin?.createNotificationChannel(defaultChannel);

      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      // --- End FCM Notification Setup ---

      // Initialize connectivity service
      connectivityService.initialize();

      // Style the system status bar (semi-transparent black with light icons)
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Color.fromARGB(102, 255, 255, 255),
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.dark,
        ),
      );

      // English-only (no language switching)
      const Locale startLocale = Locale('en');

      runApp(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/lang',
          fallbackLocale: const Locale('en'),
          startLocale: startLocale,
          child: const CapstoneApp(),
        ),
      );
    },
    (error, stack) {
      // Optionally forward to a crash reporter here in release.
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        // Only print in debug mode to improve performance in release
        if (!kReleaseMode) parent.print(zone, line);
      },
    ),
  );
}

// FCM background handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  try {
    // Initialize local notifications in background isolate
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/ic_stat_notify');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    // Ensure channel exists
    const AndroidNotificationChannel defaultChannel =
        AndroidNotificationChannel(
          'high_importance_v2',
          'High Importance Notifications',
          description:
              'Used for important notifications like reviews and requests',
          importance: Importance.high,
        );
    final androidPlugin =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    await androidPlugin?.createNotificationChannel(defaultChannel);

    // Avoid duplicates: if FCM includes a notification payload, Android will
    // display it automatically in background. Only show for data-only messages.
    if (message.notification == null) {
      final String title = message.data['title']?.toString() ?? 'Notification';
      final String body = message.data['body']?.toString() ?? '';

      await flutterLocalNotificationsPlugin.show(
        message.hashCode,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_v2',
            'High Importance Notifications',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    }
  } catch (_) {}
}

class CapstoneApp extends StatelessWidget {
  const CapstoneApp({Key? key}) : super(key: key);

  Future<Widget> _getStartPage() async {
    final box = Hive.box('userBox');
    final isLoggedIn = box.get('isLoggedIn', defaultValue: false) as bool;

    if (!isLoggedIn) {
      print('📱 No login state, showing login page');
      return const LoginPage();
    }

    final userProfile = box.get('userProfile');
    final rawRole = userProfile != null ? userProfile['role'] : null;
    final role =
        rawRole != null ? rawRole.toString().trim().toLowerCase() : null;
    final userId = userProfile != null ? userProfile['userId'] : null;

    print('📱 User logged in as: $role');

    // Check user approval status from Firestore
    if (userId != null) {
      try {
        final doc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .get();

        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'];

          // If user is not active, clear login state and show login page
          if (status != 'active') {
            print('📱 User status is $status, clearing login state');
            await box.put('isLoggedIn', false);
            await box.delete('userProfile');
            return const LoginPage();
          }
        }
      } catch (e) {
        print('📱 Error checking user status: $e');
        // On error, clear login state to be safe
        await box.put('isLoggedIn', false);
        await box.delete('userProfile');
        return const LoginPage();
      }
    }

    final normalizedRole = role == 'head_veterinarian' || role == 'head veterinarian'
        ? 'veterinarian'
        : role;

    if (normalizedRole == 'veterinarian') {
      return const VeterinarianDashboard();
    }
    if (normalizedRole == 'expert') {
      return const ExpertDashboard();
    } else {
      return const HomePage();
    }
  }

  void _setupFCM(BuildContext context) async {
    // Request notification permissions
    await FirebaseMessaging.instance.requestPermission();

    // Get FCM token and store it if needed
    String? token = await FirebaseMessaging.instance.getToken();
    // Store token for the signed-in user (farmer or expert)
    final user = FirebaseAuth.instance.currentUser;
    String? role;
    if (user != null) {
      try {
        // Ensure token is saved
        if (token != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({'fcmToken': token}, SetOptions(merge: true));
        }
        // Fetch role and server-side notification preference
        final userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();
        final data = userDoc.data();
        role = data != null ? data['role'] as String? : null;
        // If server flag missing, default to true so backend won't gate out
        final serverEnabled = data != null ? data['enableNotifications'] : null;
        if (serverEnabled == null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({'enableNotifications': true}, SetOptions(merge: true));
        }
      } catch (_) {
        // ignore read/write errors silently for now
      }
    }

    // Subscribe users to topics with local toggle
    try {
      final userBox = Hive.box('userBox');
      final profile = userBox.get('userProfile') as Map?;
      role = role ?? (profile != null ? profile['role'] as String? : null);
      final settingsBox = Hive.box('settings');
      // Ensure default is enabled if not yet set
      final hasKey = settingsBox.containsKey('enableNotifications');
      if (!hasKey) {
        await settingsBox.put('enableNotifications', true);
      }
      final notificationsEnabled =
          settingsBox.get('enableNotifications', defaultValue: true) as bool;
      if (notificationsEnabled) {
        await FirebaseMessaging.instance.subscribeToTopic('all_users');
        if (role == 'expert') {
          await FirebaseMessaging.instance.subscribeToTopic('experts');
        } else {
          await FirebaseMessaging.instance.unsubscribeFromTopic('experts');
        }
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic('all_users');
        await FirebaseMessaging.instance.unsubscribeFromTopic('experts');
      }
    } catch (_) {}

    // Listen for token refresh and persist
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(u.uid)
              .update({'fcmToken': newToken});
        } catch (_) {}
      }
      // Maintain topic subscription on refresh with local toggle
      try {
        final userBox = Hive.box('userBox');
        final profile = userBox.get('userProfile') as Map?;
        final role = profile != null ? profile['role'] as String? : null;
        final settingsBox = Hive.box('settings');
        final notificationsEnabled =
            settingsBox.get('enableNotifications', defaultValue: true) as bool;
        if (notificationsEnabled) {
          await FirebaseMessaging.instance.subscribeToTopic('all_users');
          if (role == 'expert') {
            await FirebaseMessaging.instance.subscribeToTopic('experts');
          } else {
            await FirebaseMessaging.instance.unsubscribeFromTopic('experts');
          }
        } else {
          await FirebaseMessaging.instance.unsubscribeFromTopic('all_users');
          await FirebaseMessaging.instance.unsubscribeFromTopic('experts');
        }
      } catch (_) {}
    });

    // Foreground notification handler (respect local toggle)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      try {
        final settingsBox = Hive.box('settings');
        final enabled =
            settingsBox.get('enableNotifications', defaultValue: true) as bool;
        if (!enabled) return;
      } catch (_) {}
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;
      if (notification != null && android != null) {
        final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
            FlutterLocalNotificationsPlugin();
        flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'high_importance_v2',
              'High Importance Notifications',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );
      }
    });

    // When app is opened from a notification (background)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      // Handle deep linking or navigation if needed using message.data
    });

    // When app is launched by tapping a notification (terminated)
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      // Handle cold-start navigation if needed
    }
  }

  @override
  Widget build(BuildContext context) {
    _setupFCM(context);
    return MaterialApp(
      title: 'OinkCheck - Pig Disease Detection',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.green, // Keep green header as in reference
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.green,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.blue,
          ),
        ),
      ),
      localizationsDelegates: [
        ...context.localizationDelegates,
        MonthYearPickerLocalizations.delegate,
      ],
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: FutureBuilder<Widget>(
        future: _getStartPage(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return snapshot.data!;
        },
      ),
      routes: {
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/user-home': (context) => const HomePage(),
        '/expert-home': (context) => const ExpertDashboard(),
      },
      builder:
          (context, child) =>
              NoInternetBanner(child: child ?? const SizedBox.shrink()),
    );
  }
}
