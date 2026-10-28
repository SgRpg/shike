import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as zones;
import 'package:timezone/timezone.dart' as tz;

import 'journal_repository.dart';
import 'model.dart';

class CapsuleNotificationService {
  final JournalRepository repository;
  final FlutterLocalNotificationsPlugin plugin;
  void Function(String id)? onOpen;
  bool initialized = false;
  String? launchId;
  Future<void> _queue = Future.value();
  CapsuleNotificationService(
    this.repository, {
    FlutterLocalNotificationsPlugin? plugin,
  }) : plugin = plugin ?? FlutterLocalNotificationsPlugin();
  Future<void> initialize() async {
    if (kIsWeb || initialized) return;
    zones.initializeTimeZones();
    await plugin.initialize(
      settings: const InitializationSettings(
        iOS: IOSInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) onOpen?.call(response.payload!);
      },
    );
    final launched = await plugin.getNotificationAppLaunchDetails();
    if (launched?.didNotificationLaunchApp == true) {
      launchId = launched?.notificationResponse?.payload;
    }
    initialized = true;
  }

  Future<void> reconcile({bool requestPermission = false}) {
    _queue = _queue.catchError((_) {}).then((_) async {
      if (kIsWeb) return;
      await initialize();
      if (requestPermission) {
        await plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: false, badge: false);
      }
      await repository.reconcileCapsules();
      final next = repository.nearestNotifications.take(60).toList();
      final ids = await repository.state.transaction((s) {
        final mapping = Json.from(s.meta['notificationIds'] ?? {});
        var sequence = s.meta['notificationSequence'] as int? ?? 1000;
        for (final d in next) {
          mapping.putIfAbsent(d.id, () => ++sequence);
        }
        s.meta['notificationSequence'] = sequence;
        s.meta['notificationIds'] = mapping;
        return mapping;
      });
      // Clear legacy schedules too; only capsule notifications are used by this app.
      await plugin.cancelAll();
      for (final d in next) {
        await plugin.zonedSchedule(
          id: ids[d.id],
          title: '拾刻',
          body:
              '${d.created.year}.${d.created.month}.${d.created.day} 的你寄来了一封信',
          payload: d.id,
          scheduledDate: tz.TZDateTime.from(d.unlockAt!, tz.UTC),
          notificationDetails: const NotificationDetails(
            iOS: DarwinNotificationDetails(presentSound: false),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    });
    return _queue;
  }
}
