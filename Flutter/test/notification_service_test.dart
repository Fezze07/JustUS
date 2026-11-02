import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:justus/core/notifications/notification_service.dart';

void main() {
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
