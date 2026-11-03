import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shike/complete/journal_repository.dart';
import 'package:shike/complete/persistence.dart';
import 'package:shike/complete/notifications.dart';

import 'complete_core_test.dart' show diary;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Android capsule schedule uses silent channel, inexact mode and stable launch payload', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final calls = <MethodCall>[];
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getNotificationAppLaunchDetails') {
            return {
              'notificationLaunchedApp': true,
              'notificationResponse': {
                'notificationResponseType': 0,
                'id': 1001,
                'payload': 'capsule',
              },
            };
          }
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final now = DateTime.now();
    final repo = JournalRepository(
      await AtomicState.open(MemoryPersistence()),
      clock: () => now,
    );
    await repo.commitCompleted(
      diary(
        'capsule',
        now,
        state: 'capsule',
        unlock: now.add(const Duration(hours: 2)),
      ),
    );
    final service = CapsuleNotificationService(repo);
    await service.reconcile(requestPermission: true);
    expect(
      calls.any((c) => c.method == 'requestNotificationsPermission'),
      isTrue,
    );
    final scheduled =
        calls.singleWhere((c) => c.method == 'zonedSchedule').arguments as Map;
    expect(scheduled['payload'], 'capsule');
    final android = scheduled['platformSpecifics'] as Map;
    expect(android['channelId'], 'capsules_silent_v1');
    expect(android['playSound'], false);
    expect(android['enableVibration'], false);
    expect(android['scheduleMode'], 'inexactAllowWhileIdle');
  });
}
