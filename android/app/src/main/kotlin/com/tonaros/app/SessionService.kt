package com.tonaros.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * Keeps the app process alive and the CPU awake while a session runs, so the
 * Dart timer keeps firing (and cues keep playing) with the app in the
 * background or the screen off. Shows an ongoing notification with the
 * current phase and a countdown; tapping it returns to the app.
 *
 * Started, updated and stopped from Dart over the "com.tonaros/session"
 * channel - see lib/services/background_session.dart.
 */
class SessionService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification(
            this,
            intent?.getStringExtra(EXTRA_TITLE) ?: "Tonaros",
            intent?.getStringExtra(EXTRA_TEXT) ?: "",
            intent?.getLongExtra(EXTRA_ENDS_AT, 0L) ?: 0L,
        )
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            } else {
                0
            },
        )
        acquireWakeLock()
        // If the system kills the process anyway, don't restart a session
        // nobody is watching.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    /** The task was swiped away from recents: end the session with it. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        stop()
        super.onTaskRemoved(rootIntent)
    }

    private fun stop() {
        releaseWakeLock()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Tonaros:session").apply {
            // Safety net: a session never needs more than a few hours.
            acquire(4 * 60 * 60 * 1000L)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    companion object {
        private const val CHANNEL_ID = "session"
        private const val NOTIFICATION_ID = 1
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_ENDS_AT = "endsAt"

        /** Starts the service; call while the app is in the foreground. */
        fun start(context: Context, title: String, text: String, endsAt: Long) {
            val intent = Intent(context, SessionService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
                .putExtra(EXTRA_ENDS_AT, endsAt)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /**
         * Updates the running service's notification. Posts it directly
         * rather than restarting the service: starting a foreground service
         * from the background isn't allowed on Android 12+, and phases change
         * while the app is in the background.
         */
        fun update(context: Context, title: String, text: String, endsAt: Long) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID, buildNotification(context, title, text, endsAt))
        }

        /** Stopping is allowed at any time, foreground or not. */
        fun stop(context: Context) {
            context.stopService(Intent(context, SessionService::class.java))
        }

        private fun buildNotification(
            context: Context,
            title: String,
            text: String,
            endsAt: Long,
        ): Notification {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                manager.getNotificationChannel(CHANNEL_ID) == null
            ) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Running session", NotificationManager.IMPORTANCE_LOW).apply {
                        description = "Shows the current exercise while a session runs"
                        setShowBadge(false)
                    }
                )
            }

            val openApp = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(openApp)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setCategory(NotificationCompat.CATEGORY_WORKOUT)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .apply {
                    if (endsAt > 0) {
                        // A live countdown to the end of the phase, drawn by
                        // the system - no per-second updates needed.
                        setWhen(endsAt)
                        setShowWhen(true)
                        setUsesChronometer(true)
                        setChronometerCountDown(true)
                    } else {
                        setShowWhen(false)
                    }
                }
                .build()
        }
    }
}
