// =============================================================================
// NotificationService - Local notifications handler
// =============================================================================

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Open notification');
    final windowsSettings = WindowsInitializationSettings(
      appName: 'JustUs',
      appUserModelId: 'com.justus.app',
      guid: '09cd7eb2-30eb-4a5d-a8b9-c84f6ad53c8a',
    );
    final initSettings = InitializationSettings(
      android: androidSettings,
      linux: linuxSettings,
      windows: windowsSettings,
    );

    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        // Handle notification tap
      },
    );

    // Request permissions
    final androidImplementation = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'justus_channel',
      'JustUs Notifications',
      channelDescription: 'Main channel for JustUs app notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }
}
