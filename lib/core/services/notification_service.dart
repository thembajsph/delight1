// lib/core/services/notification_service.dart
// Push notifications via Firebase Cloud Messaging + local notifications
// Works on Android and iOS — web shows nothing (graceful no-op)

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Conditional import — Firebase only on mobile
import 'notification_service_mobile.dart'
  if (dart.library.html) 'notification_service_web.dart';

export 'notification_service_mobile.dart'
  if (dart.library.html) 'notification_service_web.dart'
  show NotificationServiceImpl;

final _localNotifications = FlutterLocalNotificationsPlugin();

const _channel = AndroidNotificationChannel(
  'delight_notifications',
  'Delight',
  description: 'Payment alerts, ticket updates and event reminders',
  importance: Importance.high,
  playSound: true,
);

class NotificationService {
  static bool get isSupported => !kIsWeb;

  static Future<void> initialize() async {
    if (!isSupported) return;

    // Create Android notification channel
    await _localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_channel);

    // Init local notifications
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true));

    await _localNotifications.initialize(initSettings);

    // Init Firebase + FCM via platform-specific impl
    await NotificationServiceImpl.initialize(_handleForegroundMessage);
  }

  static void _handleForegroundMessage(
      String title, String body, Map<String, dynamic> data) {
    // Show local notification when app is in foreground
    _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title, body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id, _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher'),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true)));
  }

  /// Send local notification immediately (for testing + in-app events)
  static Future<void> show({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (!isSupported) return;
    _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title, body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id, _channel.name,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher'),
        iOS: const DarwinNotificationDetails()));
  }

  /// Get FCM token — send this to Supabase to target this device
  static Future<String?> getToken() async {
    if (!isSupported) return null;
    return NotificationServiceImpl.getToken();
  }

  // ── Convenience methods for common Delight notifications ─────────────────

  static Future<void> paymentReceived(double zarAmount, String from) =>
    show(
      title: '💸 Money received!',
      body: 'R${zarAmount.toStringAsFixed(2)} from $from is in your wallet.');

  static Future<void> paymentSent(double zarAmount, String to) =>
    show(
      title: '✓ Payment sent',
      body: 'R${zarAmount.toStringAsFixed(2)} sent to $to.');

  static Future<void> ticketPurchased(String eventName) =>
    show(
      title: '🎟 Ticket confirmed!',
      body: 'Your NFT ticket for $eventName is in My Tickets.');

  static Future<void> ticketSold(double earningsZAR, String eventName) =>
    show(
      title: '🤑 Ticket sold!',
      body: 'R${earningsZAR.toStringAsFixed(2)} added to your wallet from $eventName ticket.');

  static Future<void> cashoutInitiated(double zarAmount) =>
    show(
      title: '🏦 Cash out initiated',
      body: 'R${zarAmount.toStringAsFixed(2)} is on its way to your bank. Arrives in 1–2 business days.');

  static Future<void> eventReminder(String eventName, String time) =>
    show(
      title: '🔥 Event tomorrow!',
      body: '$eventName starts $time. Your ticket is ready.');
}
