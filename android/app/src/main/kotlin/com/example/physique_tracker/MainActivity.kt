package com.example.physique_tracker

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "physique_tracker/notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Reschedule notifications on app start (in case they were lost)
        rescheduleNotificationsIfNeeded()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showNativeNotification" -> {
                    val receiver = SnoozeNotificationReceiver()
                    val intent = Intent(this, SnoozeNotificationReceiver::class.java).apply {
                        action = "SHOW_NOTIFICATION"
                    }
                    receiver.onReceive(applicationContext, intent)
                    result.success(true)
                }
                "scheduleNativeNotification" -> {
                    val minutes = call.argument<Int>("minutes") ?: 0
                    val receiver = SnoozeNotificationReceiver()
                    val intent = Intent(this, SnoozeNotificationReceiver::class.java).apply {
                        action = "SCHEDULE_NOTIFICATION"
                        putExtra("minutes", minutes)
                    }
                    receiver.onReceive(applicationContext, intent)
                    result.success(true)
                }
                "scheduleDailyNotification" -> {
                    val hour = call.argument<Int>("hour") ?: 9
                    val minute = call.argument<Int>("minute") ?: 0
                    val receiver = SnoozeNotificationReceiver()
                    val intent = Intent(this, SnoozeNotificationReceiver::class.java).apply {
                        action = "SCHEDULE_DAILY_NOTIFICATION"
                        putExtra("hour", hour)
                        putExtra("minute", minute)
                    }
                    receiver.onReceive(applicationContext, intent)
                    result.success(true)
                }
                "cancelDailyNotification" -> {
                    val receiver = SnoozeNotificationReceiver()
                    val intent = Intent(this, SnoozeNotificationReceiver::class.java).apply {
                        action = "CANCEL_DAILY_NOTIFICATION"
                    }
                    receiver.onReceive(applicationContext, intent)
                    result.success(true)
                }
                "getNotificationDebugInfo" -> {
                    val debugInfo = getNotificationDebugInfo()
                    result.success(debugInfo)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Check if we should navigate to camera
        if (intent.getStringExtra("navigate_to") == "camera") {
            // Send message to Flutter to navigate to camera
            flutterEngine?.let { engine ->
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("navigateToCamera", null)
            }
        }
    }

    private fun rescheduleNotificationsIfNeeded() {
        val prefs = getSharedPreferences("notification_prefs", MODE_PRIVATE)
        val notificationsEnabled = prefs.getBoolean("notifications_enabled", false)

        if (notificationsEnabled) {
            val hour = prefs.getInt("notification_hour", 9)
            val minute = prefs.getInt("notification_minute", 0)

            // Reschedule the notification
            val receiver = SnoozeNotificationReceiver()
            val intent = Intent(this, SnoozeNotificationReceiver::class.java).apply {
                action = "SCHEDULE_DAILY_NOTIFICATION"
                putExtra("hour", hour)
                putExtra("minute", minute)
            }
            receiver.onReceive(applicationContext, intent)

            android.util.Log.d("MainActivity", "Rescheduled notification for $hour:$minute on app start")
        }
    }

    private fun getNotificationDebugInfo(): Map<String, Any?> {
        val prefs = getSharedPreferences("notification_prefs", MODE_PRIVATE)
        val notificationsEnabled = prefs.getBoolean("notifications_enabled", false)
        val hour = prefs.getInt("notification_hour", -1)
        val minute = prefs.getInt("notification_minute", -1)

        // Check if alarm is actually scheduled
        val alarmManager = getSystemService(ALARM_SERVICE) as android.app.AlarmManager
        val intent = Intent(this, SnoozeNotificationReceiver::class.java).apply {
            action = "SHOW_NOTIFICATION_AND_RESCHEDULE"
        }
        val pendingIntent = android.app.PendingIntent.getBroadcast(
            this,
            SnoozeNotificationReceiver.NOTIFICATION_ID + 1000,
            intent,
            android.app.PendingIntent.FLAG_NO_CREATE or android.app.PendingIntent.FLAG_IMMUTABLE
        )
        val alarmScheduled = pendingIntent != null

        // Calculate next trigger time
        var nextTriggerTime: String? = null
        if (notificationsEnabled && hour >= 0 && minute >= 0) {
            val calendar = java.util.Calendar.getInstance().apply {
                set(java.util.Calendar.HOUR_OF_DAY, hour)
                set(java.util.Calendar.MINUTE, minute)
                set(java.util.Calendar.SECOND, 0)
                set(java.util.Calendar.MILLISECOND, 0)

                if (timeInMillis <= System.currentTimeMillis()) {
                    add(java.util.Calendar.DAY_OF_YEAR, 1)
                }
            }
            val formatter = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())
            nextTriggerTime = formatter.format(calendar.time)
        }

        // Check exact alarm permission (Android 12+)
        var canScheduleExact = true
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            canScheduleExact = alarmManager.canScheduleExactAlarms()
        }

        return mapOf(
            "enabled" to notificationsEnabled,
            "hour" to hour,
            "minute" to minute,
            "alarmScheduled" to alarmScheduled,
            "nextTriggerTime" to nextTriggerTime,
            "canScheduleExactAlarms" to canScheduleExact,
            "currentTime" to java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date())
        )
    }
}
