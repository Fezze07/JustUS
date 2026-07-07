// =============================================================================
// NotificationService - FCM event display via local notifications
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _localInitialized = false;
  bool _channelCreated = false;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;

  // Stream for notification taps (N7)
  final StreamController<String?> _onNotificationTapController =
      StreamController<String?>.broadcast();
  Stream<String?> get onNotificationTap => _onNotificationTapController.stream;

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

      // Handle notification launch payload (N7)
      try {
        final launchDetails =
            await _notifications.getNotificationAppLaunchDetails();
        if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
          final response = launchDetails.notificationResponse;
          if (response != null) {
            Future.delayed(const Duration(milliseconds: 500), () {
              _onNotificationTapController.add(response.payload);
            });
          }
        }
      } catch (e) {
        AnsiLogger.error('Failed to get launch details: $e',
            tag: 'NotificationService');
      }
    }

    if (registerForegroundHandler && _foregroundSubscription == null) {
      _foregroundSubscription =
          FirebaseMessaging.onMessage.listen((message) async {
        AnsiLogger.notification(
            'onMessage fired — key=${message.data["notificationKey"]} id=${message.messageId}',
            tag: 'NotificationService');
        await showRemoteMessage(message);
      });
    }
  }

  void dispose() {
    unawaited(_foregroundSubscription?.cancel());
    _foregroundSubscription = null;
  }

  Future<void> initLocalNotifications({bool isBackground = false}) async {
    if (kIsWeb) return;

    if (!_localInitialized) {
      const androidSettings = AndroidInitializationSettings('ic_notification');
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

      try {
        await _notifications.initialize(
          settings: initSettings,
          onDidReceiveNotificationResponse: (response) {
            _onNotificationTapController.add(response.payload);
          },
        );
        _localInitialized = true;
      } catch (e) {
        AnsiLogger.error('Local notifications initialization failed: $e',
            tag: 'NotificationService');
      }
    }

    // Android channel creation (N3)
    if (!isBackground && !_channelCreated && _localInitialized) {
      try {
        final androidImplementation =
            _notifications.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidImplementation != null) {
          await androidImplementation.requestNotificationsPermission();

          await androidImplementation.createNotificationChannel(
            const AndroidNotificationChannel(
              'justus_channel',
              'JustUs Notifications',
              description: 'Main channel for JustUs app notifications',
              importance: Importance.high,
            ),
          );
          _channelCreated = true;
        }
      } catch (e) {
        AnsiLogger.error('Failed to create Android notification channel: $e',
            tag: 'NotificationService');
      }
    }
  }

  Future<void> showRemoteMessage(RemoteMessage message,
      {bool isBackground = false}) async {
    if (kIsWeb) return;

    if (!_localInitialized) {
      await initLocalNotifications(isBackground: isBackground);
    }

    // Load the user's saved locale (N1)
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLanguageCode = prefs.getString(LanguageHelper.storageKey);
      if (savedLanguageCode != null && savedLanguageCode.isNotEmpty) {
        LanguageHelper.setAppLocale(Locale(savedLanguageCode));
      } else {
        LanguageHelper.initFromSystemLocale();
      }
    } catch (_) {
      LanguageHelper.initFromSystemLocale();
    }

    String title;
    String body;

    final notificationKey = message.data['notificationKey'] as String?;
    if (notificationKey != null && notificationKey.isNotEmpty) {
      final dynamic rawParams = message.data['params'];
      Map<String, dynamic> params = <String, dynamic>{};
      if (rawParams is Map) {
        params = Map<String, dynamic>.from(rawParams);
      } else if (rawParams is String && rawParams.isNotEmpty) {
        try {
          params = jsonDecode(rawParams) as Map<String, dynamic>;
        } catch (_) {}
      }
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
    if (!LanguageHelper.isLocaleInitialized) {
      LanguageHelper.initFromSystemLocale();
    }
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

  int _stableStringHash(String input) {
    int hash = 5381;
    for (int i = 0; i < input.length; i++) {
      hash = ((hash << 5) + hash) + input.codeUnitAt(i);
      hash = hash & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  static int _nextNotificationId = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;

  int _notificationId(RemoteMessage message) {
    final raw =
        (message.data['notificationId'] ?? message.messageId)?.toString();
    if (raw == null || raw.isEmpty) {
      _nextNotificationId = (_nextNotificationId + 1) & 0x7fffffff;
      if (_nextNotificationId == 0) _nextNotificationId = 1;
      return _nextNotificationId;
    }
    return _stableStringHash(raw);
  }
}
