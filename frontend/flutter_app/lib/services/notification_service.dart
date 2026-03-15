import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

/// Background message handler — must be top-level function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message: ${message.messageId}');
}

/// Firebase Cloud Messaging service.
///
/// Handles push notification registration, foreground/background
/// notification reception, token management, and server registration.
class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  String? _token;

  /// The current FCM device token.
  String? get token => _token;

  /// Callback for foreground notifications (set by the app).
  void Function(String title, String body)? onForegroundNotification;

  /// Callback for notification tap navigation (set by the app).
  void Function(Map<String, dynamic> data)? onNotificationTap;

  /// Initialize FCM and request permissions.
  Future<void> initialize() async {
    // Register background handler.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Request permission (iOS).
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('[FCM] Notification permission granted');
    } else {
      debugPrint('[FCM] Notification permission denied');
      return;
    }

    // Get device token.
    _token = await _messaging.getToken();
    debugPrint('[FCM] Device token: $_token');

    // Listen for token refresh.
    _messaging.onTokenRefresh.listen((newToken) {
      _token = newToken;
      debugPrint('[FCM] Token refreshed: $newToken');
    });

    // Foreground message handler — show in-app banner.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM] Foreground message: ${message.notification?.title}');
      final title = message.notification?.title ?? '';
      final body = message.notification?.body ?? '';
      if (title.isNotEmpty) {
        onForegroundNotification?.call(title, body);
      }
    });

    // Handle notification tap when app is in background.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM] Notification opened: ${message.data}');
      _handleNotificationData(message.data);
    });

    // Check if app was opened from a notification (terminated state).
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationData(initialMessage.data);
    }
  }

  /// Handle notification data — open product buy_url or forward to app
  /// callback.
  void _handleNotificationData(Map<String, dynamic> data) {
    final type = data['type'] as String?;

    if (type == 'product_discount') {
      // Open the product's e-commerce link.
      final buyUrl = data['buy_url'] as String?;
      if (buyUrl != null && buyUrl.isNotEmpty) {
        _openUrl(buyUrl);
        return;
      }
    }

    // All other notification types go through the app callback.
    onNotificationTap?.call(data);
  }

  /// Launch a URL in the user's browser.
  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('[FCM] Cannot launch URL: $url');
      }
    } catch (e) {
      debugPrint('[FCM] Error launching URL: $e');
    }
  }

  /// Register the FCM token with the backend server.
  Future<void> registerTokenWithServer(String userId) async {
    if (_token == null) return;
    try {
      await http.post(
        Uri.parse('${AppConfig.restBaseUrl}/api/register-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'token': _token}),
      );
      debugPrint('[FCM] Token registered with server for $userId');
    } catch (e) {
      debugPrint('[FCM] Failed to register token: $e');
    }
  }
}

