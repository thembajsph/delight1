// lib/core/services/notification_service_mobile.dart
// Firebase Messaging — Android + iOS only

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Background message handler — must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Background messages are handled by the OS notification tray
}

class NotificationServiceImpl {
  static Future<void> initialize(
      void Function(String, String, Map<String, dynamic>) onMessage) async {
    await Firebase.initializeApp();

    // Request permission (iOS requires explicit request)
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true, badge: true, sound: true,
      provisional: false);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((msg) {
      final title = msg.notification?.title ?? 'Delight';
      final body  = msg.notification?.body  ?? '';
      onMessage(title, body, msg.data);
    });

    // Background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      // TODO: navigate to relevant screen based on msg.data['type']
    });
  }

  static Future<String?> getToken() async {
    return FirebaseMessaging.instance.getToken();
  }
}
