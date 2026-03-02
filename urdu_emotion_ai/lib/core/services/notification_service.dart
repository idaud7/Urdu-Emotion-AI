import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'firestore_service.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  /// Shared secret that must match ADMIN_NOTIFICATION_SECRET on the backend.
  /// Set this to any random string you choose (e.g. a UUID).
  static const String _adminSecret = 'UrduEmotionAI-NotifSecret-2026';

  // ── Token management ────────────────────────────────────────────────────────

  /// Call once after the user is confirmed logged in.
  /// Requests permission, gets the FCM token, and saves it to Firestore.
  Future<void> initForUser() async {
    try {
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final token = await _fcm.getToken();
      if (token == null) return;

      await FirestoreService.instance.saveFcmToken(uid, token);

      // Keep token fresh if Firebase rotates it.
      _fcm.onTokenRefresh.listen((newToken) async {
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        if (currentUid != null) {
          await FirestoreService.instance.saveFcmToken(currentUid, newToken);
        }
      });
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationService.initForUser error: $e');
    }
  }

  // ── Admin send ───────────────────────────────────────────────────────────────

  /// Called by the admin panel to send a push notification via the FastAPI backend.
  /// [target] is either 'All Users' or 'Active Users'.
  Future<void> sendAdminNotification({
    required String title,
    required String body,
    required String target,
  }) async {
    final uri = Uri.parse('${ApiService.instance.baseUrl}/send-notification');

    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-admin-secret': _adminSecret,
          },
          body: jsonEncode({'title': title, 'body': body, 'target': target}),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      final detail = (jsonDecode(response.body) as Map<String, dynamic>)['detail']
          ?? 'Unknown error';
      throw Exception('Backend error ${response.statusCode}: $detail');
    }
  }
}
