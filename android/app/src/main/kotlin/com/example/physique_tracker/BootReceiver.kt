package com.example.physique_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON" ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {

            // Reschedule notifications after boot
            rescheduleNotifications(context)
        }
    }

    private fun rescheduleNotifications(context: Context) {
        val prefs = context.getSharedPreferences("notification_prefs", Context.MODE_PRIVATE)
        val notificationsEnabled = prefs.getBoolean("notifications_enabled", false)

        if (notificationsEnabled) {
            val hour = prefs.getInt("notification_hour", 9)
            val minute = prefs.getInt("notification_minute", 0)

            // Send intent to reschedule the notification
            val scheduleIntent = Intent(context, SnoozeNotificationReceiver::class.java).apply {
                action = "SCHEDULE_DAILY_NOTIFICATION"
                putExtra("hour", hour)
                putExtra("minute", minute)
            }
            context.sendBroadcast(scheduleIntent)

            android.util.Log.d("BootReceiver", "Rescheduled notification for $hour:$minute after boot")
        }
    }
}
