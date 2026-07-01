import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'ble_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Android notification channel ID
  static const String _channelId = "high_risk_alerts";
  static const String _channelName = "High Risk Alerts";

  static Future<void> init() async {
    // Android settings
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS settings
    const iosInit = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (payload) {
        // Optional: handle notification tap
      },
    );

    // Create Android notification channel
    final androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Notifications for high-risk alerts',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(const [0, 1000, 500, 1000]),
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);
  }

  static Future<void> showHighRiskNotification({
    RemoteMessage? message,
    String? title,
    String? body,
  }) async {
    // 🚨 CRITICAL: DO NOT SKIP ALERTS FOR WEARABLE - admins still need vibration alerts
    // Removed admin bypass check

    // 1. Determine the content
    String displayTitle =
        title ?? message?.notification?.title ?? "⚠️ EMERGENCY";
    String displayBody =
        body ?? message?.notification?.body ?? "High Risk Alert Detected";

    // 2. Vibrate phone
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(pattern: [0, 1000, 500, 1000]);
    }

    // 3. 🆕 Send "V" to ESP32 wearable via BLE with error handling
    final ble = BleService();
    if (ble.isConnected) {
      final vibrateSent = await ble.sendVibrate();
      if (!vibrateSent) {
        debugPrint(
          '[ALERT] ⚠️ Failed to send vibration to ESP32 despite connection status',
        );
      } else {
        debugPrint('[ALERT] ✅ Vibration command sent to ESP32 successfully');
      }
    } else {
      debugPrint(
        '[ALERT] ⚠️ ESP32 not connected. Will queue vibration command for retry.',
      );
      ble.queueVibrationCommand(); // Queue for retry when reconnected
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'high_risk_alerts',
          'High Risk Alerts',
          channelDescription: 'Used for emergency risk alerts',
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: true,
          icon: '@mipmap/ic_launcher',
        );

    // 4. Show notification
    await _notificationsPlugin.show(
      message?.hashCode ?? DateTime.now().millisecondsSinceEpoch % 100000,
      displayTitle,
      displayBody,
      const NotificationDetails(android: androidDetails),
    );
  }

  // For FCM messages
  static Future<void> showFCMNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;

    if (notification != null) {
      await showHighRiskNotification(message: message);
    }
  }
}
