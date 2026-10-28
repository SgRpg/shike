import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as timezones;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';
import 'store.dart';

class CapsuleNotifications {
 static final _plugin=FlutterLocalNotificationsPlugin();
 static Future<void> schedule(Diary diary) async {
  if(kIsWeb || diary.unlockAt==null)return;
  try {
   timezones.initializeTimeZones();final info=await FlutterTimezone.getLocalTimezone();tz.setLocalLocation(tz.getLocation(info.identifier));
   await _plugin.initialize(settings:const InitializationSettings(iOS:IOSInitializationSettings(requestAlertPermission:false,requestBadgePermission:false,requestSoundPermission:false)));
   final ios=_plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
   final permitted=await ios?.requestPermissions(alert:true,badge:false,sound:false)??false;if(!permitted)return;
   final prefs=await SharedPreferences.getInstance();final id=(prefs.getInt('capsule.notificationId')??0)+1;await prefs.setInt('capsule.notificationId',id);
   await _plugin.zonedSchedule(id:id,title:'拾刻',body:'${DateFormat('yyyy.MM.dd').format(diary.created)} 的你寄来了一封信',scheduledDate:tz.TZDateTime.from(diary.unlockAt!,tz.local),notificationDetails:const NotificationDetails(iOS:DarwinNotificationDetails()),androidScheduleMode:AndroidScheduleMode.inexactAllowWhileIdle);
  } catch (_) { /* Notifications never prevent sealing and reading a capsule. */ }
 }
}
