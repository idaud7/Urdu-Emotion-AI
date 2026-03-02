import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'core/routes/app_router.dart';
import 'core/services/email_report_service.dart';
import 'core/services/firestore_service.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';

/// Must be a top-level function — called by FCM when the app is terminated.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const UrduEmotionApp());
}

class UrduEmotionApp extends StatefulWidget {
  const UrduEmotionApp({super.key});

  @override
  State<UrduEmotionApp> createState() => _UrduEmotionAppState();
}

class _UrduEmotionAppState extends State<UrduEmotionApp> {
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    // Each time a user signs in, check whether a weekly email is due.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      // Small delay so navigation settles before any network calls.
      await Future.delayed(const Duration(seconds: 2));
      final profile =
          await FirestoreService.instance.getUserProfile(user.uid);
      if (profile != null) {
        await EmailReportService.instance.maybeSendWeeklyEmail(profile);
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Urdu Emotion AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: AppRouter.router,
    );
  }
}
