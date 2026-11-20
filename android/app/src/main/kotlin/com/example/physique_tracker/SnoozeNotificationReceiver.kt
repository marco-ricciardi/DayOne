package com.example.physique_tracker

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import androidx.core.app.NotificationCompat

class SnoozeNotificationReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_SNOOZE = "com.example.physique_tracker.ACTION_SNOOZE"
        const val EXTRA_SNOOZE_MINUTES = "snooze_minutes"
        const val CHANNEL_ID = "daily_photo_reminder"
        const val NOTIFICATION_ID = 123
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_SNOOZE -> {
                val snoozeMinutes = intent.getIntExtra(EXTRA_SNOOZE_MINUTES, 15)

                // Cancel the current notification
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(NOTIFICATION_ID)

                // Schedule a new notification after snooze duration
                scheduleSnoozeNotification(context, snoozeMinutes)
            }
            "SHOW_NOTIFICATION" -> {
                showNotification(context)
            }
            "SHOW_NOTIFICATION_AND_RESCHEDULE" -> {
                // Show the notification
                showNotification(context)

                // Reschedule for tomorrow at the same time
                val hour = intent.getIntExtra("hour", 9)
                val minute = intent.getIntExtra("minute", 0)
                scheduleDailyNotification(context, hour, minute)
            }
            "SCHEDULE_NOTIFICATION" -> {
                val minutes = intent.getIntExtra("minutes", 0)
                if (minutes == 0) {
                    showNotification(context)
                } else {
                    scheduleSnoozeNotification(context, minutes)
                }
            }
            "SCHEDULE_DAILY_NOTIFICATION" -> {
                val hour = intent.getIntExtra("hour", 9)
                val minute = intent.getIntExtra("minute", 0)
                scheduleDailyNotification(context, hour, minute)
            }
            "CANCEL_DAILY_NOTIFICATION" -> {
                cancelDailyNotification(context)
            }
        }
    }

    private fun scheduleSnoozeNotification(context: Context, minutes: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val intent = Intent(context, SnoozeNotificationReceiver::class.java).apply {
            action = "SHOW_NOTIFICATION"
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            NOTIFICATION_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val triggerTime = System.currentTimeMillis() + (minutes * 60 * 1000L)

        // Use exact alarm for precise timing, with fallback to inexact if not permitted
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (alarmManager.canScheduleExactAlarms()) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerTime,
                    pendingIntent
                )
            } else {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerTime,
                    pendingIntent
                )
            }
        } else {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerTime,
                pendingIntent
            )
        }
    }

    private fun showNotification(context: Context) {
        // Don't show notification if photo already exists for today
        if (photoExistsForToday(context)) {
            return
        }

        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Create notification channel (required for Android 8.0+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Daily Photo Reminder",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Daily reminders to take physique photos"
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        // Create intent to open app on notification tap
        val tapIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("navigate_to", "camera")
        }
        val tapPendingIntent = PendingIntent.getActivity(
            context,
            0,
            tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Create snooze action intents
        val snooze15Intent = createSnoozeIntent(context, 15)
        val snooze30Intent = createSnoozeIntent(context, 30)
        val snooze60Intent = createSnoozeIntent(context, 60)

        // Random motivational messages for notifications
        val messages = listOf(
            Pair("Time to capture your progress! 📸", "Your future self will thank you"),
            Pair("Keep the streak alive! 🔥", "Consistency is key to results"),
            Pair("Progress check time! 💪", "Every photo tells your story"),
            Pair("Your daily snapshot awaits! ✨", "Small steps lead to big changes"),
            Pair("Mirror, mirror on the wall... 🪞", "Time to document your journey"),
            Pair("Rise and grind! 🌅", "Capture today's version of you"),
            Pair("Let's see those gains! 💯", "Your transformation continues"),
            Pair("Photo time! You got this! 🏆", "Champions track their progress"),
            Pair("Document your journey! 📈", "Watch yourself evolve"),
            Pair("Another day, another photo! 🎯", "Stay committed to your goals")
        )
        val (title, subtitle) = messages.random()

        // Build notification with large icon (colored) and small icon (monochrome)
        val largeIcon = BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setLargeIcon(largeIcon)
            .setColor(android.graphics.Color.BLACK) // Black tint for small icon
            .setContentTitle(title)
            .setContentText(subtitle)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(tapPendingIntent)
            .addAction(0, "15 min", snooze15Intent)
            .addAction(0, "30 min", snooze30Intent)
            .addAction(0, "1 hour", snooze60Intent)
            .build()

        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun createSnoozeIntent(context: Context, minutes: Int): PendingIntent {
        val intent = Intent(context, SnoozeNotificationReceiver::class.java).apply {
            action = ACTION_SNOOZE
            putExtra(EXTRA_SNOOZE_MINUTES, minutes)
        }
        return PendingIntent.getBroadcast(
            context,
            minutes, // Use minutes as request code to make each intent unique
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun scheduleDailyNotification(context: Context, hour: Int, minute: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        // First, cancel any existing daily alarm. Only the alarm: this runs
        // right after showNotification() when the alarm fires, so using
        // cancelDailyNotification() here would instantly dismiss the
        // notification we just posted.
        cancelDailyAlarm(context)

        // Save the notification time to SharedPreferences for rescheduling after reboot
        val prefs = context.getSharedPreferences("notification_prefs", Context.MODE_PRIVATE)
        prefs.edit()
            .putInt("notification_hour", hour)
            .putInt("notification_minute", minute)
            .putBoolean("notifications_enabled", true)
            .apply()

        // Create intent that will reschedule itself after firing
        val intent = Intent(context, SnoozeNotificationReceiver::class.java).apply {
            action = "SHOW_NOTIFICATION_AND_RESCHEDULE"
            putExtra("hour", hour)
            putExtra("minute", minute)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            NOTIFICATION_ID + 1000, // Different request code for daily notification
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Calculate the next occurrence of the specified time
        val calendar = java.util.Calendar.getInstance().apply {
            set(java.util.Calendar.HOUR_OF_DAY, hour)
            set(java.util.Calendar.MINUTE, minute)
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)

            // If the time has passed today, schedule for tomorrow
            if (timeInMillis <= System.currentTimeMillis()) {
                add(java.util.Calendar.DAY_OF_YEAR, 1)
            }
        }

        // Use exact alarm for precise timing, with fallback to inexact if not permitted
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (alarmManager.canScheduleExactAlarms()) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    calendar.timeInMillis,
                    pendingIntent
                )
            } else {
                // Fallback to inexact alarm if exact alarms not permitted
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    calendar.timeInMillis,
                    pendingIntent
                )
            }
        } else {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                calendar.timeInMillis,
                pendingIntent
            )
        }
    }

    /** Cancels the scheduled daily alarm only (leaves any visible notification). */
    private fun cancelDailyAlarm(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, SnoozeNotificationReceiver::class.java).apply {
            action = "SHOW_NOTIFICATION_AND_RESCHEDULE"
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            NOTIFICATION_ID + 1000,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        ) ?: return
        alarmManager.cancel(pendingIntent)
        // Also drop the PendingIntent itself, so the debug "Alarm Registered"
        // check (FLAG_NO_CREATE) reports accurately after cancelling.
        pendingIntent.cancel()
    }

    /** Turns daily reminders off: cancels the alarm and any visible reminder. */
    private fun cancelDailyNotification(context: Context) {
        cancelDailyAlarm(context)

        // Also cancel any visible notification
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(NOTIFICATION_ID)

        // Update SharedPreferences
        val prefs = context.getSharedPreferences("notification_prefs", Context.MODE_PRIVATE)
        prefs.edit().putBoolean("notifications_enabled", false).apply()

        android.util.Log.d("NotificationScheduler", "Cancelled daily notification")
    }

    private fun photoExistsForToday(context: Context): Boolean {
        try {
            // Get the app's document directory (matches Flutter's getApplicationDocumentsDirectory)
            // On Android, this is /data/data/<package>/app_flutter/
            val appDir = java.io.File(context.filesDir.parent, "app_flutter")
            val photosDir = java.io.File(appDir, "physique_photos")

            if (!photosDir.exists()) {
                return false
            }

            // Format today's date as YYYYMMDD. Before 5am counts as the
            // previous day, matching AppDateUtils.dayCutoffHour in Flutter.
            val today = java.util.Calendar.getInstance()
            if (today.get(java.util.Calendar.HOUR_OF_DAY) < 5) {
                today.add(java.util.Calendar.DAY_OF_YEAR, -1)
            }
            val dateKey = String.format(
                "%04d%02d%02d",
                today.get(java.util.Calendar.YEAR),
                today.get(java.util.Calendar.MONTH) + 1, // Month is 0-indexed
                today.get(java.util.Calendar.DAY_OF_MONTH)
            )

            // Check if file exists for today
            val photoFile = java.io.File(photosDir, "$dateKey.jpg")
            return photoFile.exists()
        } catch (e: Exception) {
            // If there's any error checking, show the notification to be safe
            return false
        }
    }
}
