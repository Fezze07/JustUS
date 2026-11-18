import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:justus/all_imports.dart';

void main() {
  test('answerReminder localizes with the sender name', () {
    LanguageHelper.setAppLocale(const Locale('en'));

    final content = NotificationService().resolveNotificationContent(
      const RemoteMessage(
        data: <String, dynamic>{
          'notificationKey': 'answerReminder',
          'params': <String, dynamic>{'partnerName': 'Alex'},
        },
      ),
    );

    expect(content?.title, 'Answer Reminder');
    expect(content?.body, 'Alex is waiting for your answer');
  });

  test('unknown notificationKey falls back to the server title and body', () {
    final content = NotificationService().resolveNotificationContent(
      const RemoteMessage(
        data: <String, dynamic>{
          'notificationKey': 'futureKey',
          'title': 'Server title',
          'body': 'Server body',
        },
      ),
    );

    expect(content?.title, 'Server title');
    expect(content?.body, 'Server body');
  });

  test('unknown notificationKey without server text keeps the old defaults',
      () {
    final content = NotificationService().resolveNotificationContent(
      const RemoteMessage(
        data: <String, dynamic>{'notificationKey': 'futureKey'},
      ),
    );

    expect(content?.title, 'JustUS');
    expect(content?.body, '');
  });
}
