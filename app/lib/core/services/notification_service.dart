import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;

  NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String _channelId = 'katharscan_reminders';
  static const String _channelName = 'Document Reminders';
  static const String _channelDesc = 'Notifications for unexported documents and feature tips';

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      tz.initializeTimeZones();
      // Safe local timezone detection with UTC fallback
      try {
        final String tzName = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(tzName));
      } catch (e) {
        tz.setLocalLocation(tz.getLocation('UTC'));
      }

      const androidSettings = AndroidInitializationSettings('@drawable/notification_icon');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Android permission request removed to prevent cold-start crash

    // iOS permission request removed to prevent cold-start crash

    await _createNotificationChannel();
    
    // Wrap scheduling in try/catch to prevent any timezone/scheduling errors from crashing the app
    try {
      await _scheduleFeatureDiscovery();
    } catch (e) {
      // 'Feature discovery schedule failed: \$e'
    }
    try {
      await _scheduleWeeklySummary();
    } catch (e) {
      // 'Weekly summary schedule failed: \$e'
    }

    _initialized = true;
    } catch (e) {
      // 'Notification initialization failed: \$e'
    }
  }

  Future<void> _createNotificationChannel() async {
    // Android channels are created automatically on first notification
    // The channel ID, name, and description are passed with each notification
  }

  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    // Handle deep link based on payload format: "doc:{id}" or "feature:{type}"
    _pendingPayload.value = payload;
  }

  final ValueNotifier<String?> _pendingPayload = ValueNotifier<String?>(null);
  ValueNotifier<String?> get pendingPayload => _pendingPayload;


  Future<bool> requestPermission() async {
    if (!_initialized) return false;
    final status = await Permission.notification.status;
    if (status.isGranted) return true;
    final result = await Permission.notification.request();
    return result.isGranted;
  }

  Future<void> scheduleExportReminder({
    required String documentId,
    required String documentTitle,
    required DateTime scheduledTime,
  }) async {
    if (!_initialized) return;
    await requestPermission();

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
    );

    final iosDetails = DarwinNotificationDetails();

    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    final notifId = documentId.hashCode.abs();

    await _notifications.zonedSchedule(
      notifId,
      'Unexported Document',
      'Your document "$documentTitle" is ready to export',
      tz.TZDateTime.from(scheduledTime, tz.local),
      details,
      payload: 'doc:$documentId',
      androidScheduleMode: AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelDocumentNotifications(String documentId) async {
    if (!_initialized) return;
    final notifId = documentId.hashCode.abs();
    await _notifications.cancel(notifId);
  }

  Future<void> _scheduleFeatureDiscovery() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('feature_discovery_shown') ?? false;
    if (shown) return;

    final threeDaysLater = DateTime.now().add(const Duration(days: 3));

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    final iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _notifications.zonedSchedule(
      999999,
      'Try the Seal & Sign Tools',
      'Create custom seals and e-sign documents in seconds',
      tz.TZDateTime.from(threeDaysLater, tz.local),
      details,
      payload: 'feature:seal_sign',
      androidScheduleMode: AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );

    await prefs.setBool('feature_discovery_shown', true);
  }

  Future<void> _scheduleWeeklySummary() async {
    final now = DateTime.now();
    final daysUntilMonday = (8 - now.weekday) % 7;
    final nextMonday = DateTime(now.year, now.month, now.day + (daysUntilMonday == 0 ? 7 : daysUntilMonday), 9, 0);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    final iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _notifications.zonedSchedule(
      888888,
      'Weekly Summary',
      'Check your scanning activity this week',
      tz.TZDateTime.from(nextMonday, tz.local),
      details,
      payload: 'feature:weekly_summary',
      androidScheduleMode: AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelAllNotifications() async {
    if (!_initialized) return;
    await _notifications.cancelAll();
  }
}
