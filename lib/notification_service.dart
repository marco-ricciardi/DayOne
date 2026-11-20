import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';

// Top-level function for background notification handling
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  final actionId = response.actionId;
  final notificationId = response.id;

  // Handle snooze actions
  if (actionId == NotificationService.snooze15Action) {
    await NotificationService().scheduleSnoozeNotification(15);
    await NotificationService()._notifications.cancel(notificationId ?? 0);
  } else if (actionId == NotificationService.snooze30Action) {
    await NotificationService().scheduleSnoozeNotification(30);
    await NotificationService()._notifications.cancel(notificationId ?? 0);
  } else if (actionId == NotificationService.snooze60Action) {
    await NotificationService().scheduleSnoozeNotification(60);
    await NotificationService()._notifications.cancel(notificationId ?? 0);
  } else if (actionId == NotificationService.snooze10SecAction) {
    // TEST ONLY - 10 second snooze
    await NotificationService().scheduleTestSnoozeNotification(10);
    await NotificationService()._notifications.cancel(notificationId ?? 0);
  } else {
    await NotificationService()._notifications.cancel(notificationId ?? 0);
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // Method channel for native notification handling
  static const MethodChannel _channel = MethodChannel('physique_tracker/notifications');

  // Stream controller for navigation events
  static final StreamController<String> _navigationController =
      StreamController<String>.broadcast();
  static Stream<String> get navigationStream => _navigationController.stream;

  // Notification IDs
  static const int dailyNotificationId = 0;
  static const int snoozeNotificationId = 1;

  // Action IDs for notification buttons
  static const String snooze15Action = 'snooze_15';
  static const String snooze30Action = 'snooze_30';
  static const String snooze60Action = 'snooze_60';
  static const String snooze10SecAction = 'snooze_10sec'; // TEST ONLY

  Future<void> initialize() async {
    // Initialize timezone data
    tz.initializeTimeZones();

    // Get local timezone (you may want to make this configurable)
    final String locationName = 'America/New_York'; // Default timezone
    tz.setLocalLocation(tz.getLocation(locationName));

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // Request notification permissions
    await _requestPermissions();

    // Set up method channel handler for native navigation events
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'navigateToCamera') {
        _navigationController.add('camera');
      }
    });
  }

  Future<void> _requestPermissions() async {
    final androidPlugin =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.requestNotificationsPermission();

    // Request exact alarm permission for Android 12+
    await androidPlugin?.requestExactAlarmsPermission();

    final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    await iosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  // Handle notification tap
  @pragma('vm:entry-point')
  static void _onNotificationTap(NotificationResponse response) async {
    final actionId = response.actionId;
    final notificationId = response.id;

    // Handle snooze actions
    if (actionId == snooze15Action) {
      await NotificationService().scheduleSnoozeNotification(15);
      await NotificationService()._notifications.cancel(notificationId ?? 0);
    } else if (actionId == snooze30Action) {
      await NotificationService().scheduleSnoozeNotification(30);
      await NotificationService()._notifications.cancel(notificationId ?? 0);
    } else if (actionId == snooze60Action) {
      await NotificationService().scheduleSnoozeNotification(60);
      await NotificationService()._notifications.cancel(notificationId ?? 0);
    } else if (actionId == snooze10SecAction) {
      // TEST ONLY - 10 second snooze
      await NotificationService().scheduleTestSnoozeNotification(10);
      await NotificationService()._notifications.cancel(notificationId ?? 0);
    } else {
      // Cancel the notification
      await NotificationService()._notifications.cancel(notificationId ?? 0);
      // Send navigation event to open camera page
      NotificationService._navigationController.add('camera');
    }
  }

  // Schedule daily notification
  Future<void> scheduleDailyNotification(TimeOfDay time) async {
    // Cancel existing daily notification
    await _notifications.cancel(dailyNotificationId);

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    // If the scheduled time has passed today, schedule for tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      'daily_reminder',
      'Daily Photo Reminder',
      channelDescription: 'Daily reminder to take your physique photo',
      importance: Importance.high,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          snooze15Action,
          '15 min',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          snooze30Action,
          '30 min',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          snooze60Action,
          '1 hour',
          showsUserInterface: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      categoryIdentifier: 'daily_reminder',
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.zonedSchedule(
      dailyNotificationId,
      'Time to take your photo!',
      'Tap to open camera and take today\'s progress photo',
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    // Save notification time to preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notification_hour', time.hour);
    await prefs.setInt('notification_minute', time.minute);
    await prefs.setBool('notifications_enabled', true);
  }

  // Schedule snooze notification
  Future<void> scheduleSnoozeNotification(int minutes) async {
    // Cancel existing snooze notification
    await _notifications.cancel(snoozeNotificationId);

    final now = tz.TZDateTime.now(tz.local);
    final scheduledDate = now.add(Duration(minutes: minutes));

    const androidDetails = AndroidNotificationDetails(
      'snooze_reminder',
      'Snooze Reminder',
      channelDescription: 'Snoozed photo reminder',
      importance: Importance.high,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          snooze15Action,
          '15 min',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          snooze30Action,
          '30 min',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          snooze60Action,
          '1 hour',
          showsUserInterface: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      categoryIdentifier: 'snooze_reminder',
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.zonedSchedule(
      snoozeNotificationId,
      'Time to take your photo!',
      'Tap to open camera and take today\'s progress photo',
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  // Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();

    // Update preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', false);
  }

  // Cancel daily notification only
  Future<void> cancelDailyNotification() async {
    await _notifications.cancel(dailyNotificationId);

    // Update preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', false);
  }

  // Load saved notification settings
  Future<TimeOfDay?> getSavedNotificationTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt('notification_hour');
    final minute = prefs.getInt('notification_minute');

    if (hour != null && minute != null) {
      return TimeOfDay(hour: hour, minute: minute);
    }
    return null;
  }

  // Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('notifications_enabled') ?? false;
  }

  // Call native notification
  Future<void> showNativeNotification() async {
    await _channel.invokeMethod('showNativeNotification');
  }

  // Schedule native daily notification
  Future<void> scheduleNativeDailyNotification(TimeOfDay time) async {
    await _channel.invokeMethod('scheduleDailyNotification', {
      'hour': time.hour,
      'minute': time.minute,
    });

    // Save to preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notification_hour', time.hour);
    await prefs.setInt('notification_minute', time.minute);
    await prefs.setBool('notifications_enabled', true);
  }

  // Cancel native daily notification
  Future<void> cancelNativeDailyNotification() async {
    await _channel.invokeMethod('cancelDailyNotification');

    // Update preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', false);
  }

  // TEST ONLY - Send immediate notification
  Future<void> sendTestNotification() async {
    await showNativeNotification();
  }

  // TEST ONLY - Flutter-based test notification (for development)
  Future<void> sendTestNotificationFlutter() async {
    const androidDetails = AndroidNotificationDetails(
      'test_notification',
      'Test Notifications',
      channelDescription: 'Test notifications for development',
      importance: Importance.high,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          snooze15Action,
          '15 min',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          snooze30Action,
          '30 min',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          snooze60Action,
          '1 hour',
          showsUserInterface: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      categoryIdentifier: 'test_notification',
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      999, // Test notification ID
      'Time to take your photo!',
      'Tap to open camera and take today\'s progress photo',
      details,
      payload: 'camera',
    );
  }

  // Get notification debug info from native side
  Future<Map<String, dynamic>> getNotificationDebugInfo() async {
    try {
      final result = await _channel.invokeMethod('getNotificationDebugInfo');
      if (result == null) {
        return await _getDebugInfoFromPrefs();
      }
      return Map<String, dynamic>.from(result);
    } catch (e) {
      // Fall back to reading from SharedPreferences directly
      return await _getDebugInfoFromPrefs();
    }
  }

  // Fallback: get debug info from Flutter SharedPreferences
  Future<Map<String, dynamic>> _getDebugInfoFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('notifications_enabled') ?? false;
      final hour = prefs.getInt('notification_hour') ?? -1;
      final minute = prefs.getInt('notification_minute') ?? -1;

      return {
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        'alarmScheduled': enabled, // Assume scheduled if enabled
        'nextTriggerTime': enabled && hour >= 0 && minute >= 0
            ? _calculateNextTriggerTime(hour, minute)
            : null,
        'canScheduleExactAlarms': true, // Can't check from Flutter
        'currentTime': DateTime.now().toString().substring(0, 19),
        'source': 'flutter_prefs', // Indicate this is from Flutter side
      };
    } catch (e) {
      return {
        'error': 'Failed to read preferences',
        'enabled': false,
      };
    }
  }

  String _calculateNextTriggerTime(int hour, int minute) {
    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled.toString().substring(0, 19);
  }

  // TEST ONLY - Schedule notification with seconds
  Future<void> scheduleTestSnoozeNotification(int seconds) async {
    await _notifications.cancel(snoozeNotificationId);

    final now = tz.TZDateTime.now(tz.local);
    final scheduledDate = now.add(Duration(seconds: seconds));

    const androidDetails = AndroidNotificationDetails(
      'test_snooze',
      'Test Snooze',
      channelDescription: 'Test snooze notifications',
      importance: Importance.high,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          snooze15Action,
          '15 min',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          snooze30Action,
          '30 min',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          snooze60Action,
          '1 hour',
          showsUserInterface: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      categoryIdentifier: 'test_snooze',
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.zonedSchedule(
      snoozeNotificationId,
      'Time to take your photo!',
      'Tap to open camera and take today\'s progress photo',
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }
}
