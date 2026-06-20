// =============================================================================
// NotificationService - FCM event display via local notifications
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:justus/all_imports.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _localInitialized = false;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;

  Future<void> init({bool registerForegroundHandler = true}) async {
    await _requestRemoteNotificationPermission();
    await initLocalNotifications();

    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (_) {}
    }

    if (registerForegroundHandler && _foregroundSubscription == null) {
      _foregroundSubscription =
          FirebaseMessaging.onMessage.listen((message) async {
        AnsiLogger.notification('onMessage fired — key=${message.data["notificationKey"]} id=${message.messageId}', tag: 'NotificationService');
        await showRemoteMessage(message);
      });
    }
  }

  void dispose() {
    unawaited(_foregroundSubscription?.cancel());
    _foregroundSubscription = null;
  }

  Future<void> initLocalNotifications() async {
    if (_localInitialized || kIsWeb) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    const linuxSettings =
        LinuxInitializationSettings(defaultActionName: 'Open notification');
    const windowsSettings = WindowsInitializationSettings(
      appName: 'JustUs',
      appUserModelId: 'com.justus.app',
      guid: '09cd7eb2-30eb-4a5d-a8b9-c84f6ad53c8a',
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
      windows: windowsSettings,
    );

    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        // Navigation on tap can be wired here once deep-link targets exist.
      },
    );

    final androidImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }

    _localInitialized = true;
  }

  Future<void> showRemoteMessage(RemoteMessage message) async {
    if (kIsWeb) return;

    await initLocalNotifications();

    String title;
    String body;

    final notificationKey = message.data['notificationKey'] as String?;
    if (notificationKey != null && notificationKey.isNotEmpty) {
      final paramsJson = message.data['params'] as String?;
      final params = paramsJson != null && paramsJson.isNotEmpty
          ? jsonDecode(paramsJson) as Map<String, dynamic>
          : <String, dynamic>{};
      final localized = _localizeNotification(notificationKey, params);
      title = localized.title;
      body = localized.body;
    } else {
      final rawTitle =
          (message.data['title'] ?? message.notification?.title)?.toString();
      final rawBody =
          (message.data['body'] ?? message.notification?.body)?.toString();
      if (rawTitle == null ||
          rawTitle.isEmpty ||
          rawBody == null ||
          rawBody.isEmpty) {
        return;
      }
      title = rawTitle;
      body = rawBody;
    }

    await showNotification(
      id: _notificationId(message),
      title: title,
      body: body,
      payload: jsonEncode(message.data),
    );
  }

  ({String title, String body}) _localizeNotification(
      String key, Map<String, dynamic> params) {
    LanguageHelper.initFromSystemLocale();
    final loc = LanguageHelper.appLoc;
    final partnerName = (params['partnerName'] as String?) ?? 'Your partner';
    final emojiChar = (params['emojiChar'] as String?) ?? '❤️';

    switch (key) {
      case 'requestAccepted':
        return (
          title: loc.notif_requestAccepted_title,
          body: loc.notif_requestAccepted_body(partnerName)
        );
      case 'missyou':
        return (
          title: loc.notif_missyou_title,
          body: loc.notif_missyou_body(partnerName)
        );
      case 'moodUpdated':
        return (
          title: loc.notif_moodUpdated_title,
          body: loc.notif_moodUpdated_body(partnerName)
        );
      case 'answerSubmitted':
        return (
          title: loc.notif_answerSubmitted_title,
          body: loc.notif_answerSubmitted_body(partnerName)
        );
      case 'newQuestion':
        return (
          title: loc.notif_newQuestion_title,
          body: loc.notif_newQuestion_body
        );
      case 'driveItemAdded':
        return (
          title: loc.notif_driveItemAdded_title,
          body: loc.notif_driveItemAdded_body(partnerName)
        );
      case 'reactionAdded':
        return (
          title: loc.notif_reactionAdded_title,
          body: loc.notif_reactionAdded_body(partnerName, emojiChar)
        );
      case 'bucketItemAdded':
        return (
          title: loc.notif_bucketItemAdded_title,
          body: loc.notif_bucketItemAdded_body(partnerName)
        );
      default:
        return (title: 'JustUS', body: '');
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
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
    );
    const linuxDetails =
        LinuxNotificationDetails(defaultActionName: 'Open notification');
    const windowsDetails = WindowsNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
      linux: linuxDetails,
      windows: windowsDetails,
    );

    await _notifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  Future<void> _requestRemoteNotificationPermission() async {
    if (!(kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS)) {
      return;
    }

    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {
      // Firebase may be unavailable in tests or unsupported builds.
    }
  }

  int _notificationId(RemoteMessage message) {
    final raw =
        (message.data['notificationId'] ?? message.messageId)?.toString();
    if (raw == null || raw.isEmpty) {
      return DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    }
    return raw.hashCode & 0x7fffffff;
  }
}
