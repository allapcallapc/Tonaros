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
 * Keeps the app process alive while a session runs, so the Dart timer keeps
 * firing (and cues keep playing) with the app in the background or the
 * screen off. Shows an ongoing notification with the current phase, a
 * countdown and a Pause/Resume/Continue button; tapping it returns to the
 * app.
 *
 * The CPU is only held awake (partial wake lock) while the timer is actually
 * counting down: while paused or waiting for a tap nothing needs to fire, so
 * a long pause doesn't drain the battery.
 *
 * Started, updated and stopped from Dart over the "com.tonaros/session"
 * channel - see lib/services/background_session.dart.
 */
class SessionService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_PRIMARY) {
            // The notification's button: handled by the running screen in
            // Dart, which then updates the notification.
            if (running) onAction?.invoke() else stopSelf()
            return START_NOT_STICKY
        }
        // The latest content, not the start intent's: an update may have
        // arrived before the service got going.
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            buildNotification(this, latest),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            } else {
                0
            },
        )
        if (!running) {
            // Stopped before the system got round to starting it. Still had
            // to call startForeground: skipping it after startForegroundService
            // crashes the app.
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        holdWakeLock(this, latest.endsAt > 0)
        // If the system kills the process anyway, don't restart a session
        // nobody is watching.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        // Not resetting [running]: a new session may already have been
        // started. stop() and onTaskRemoved() reset it.
        holdWakeLock(this, false)
        super.onDestroy()
    }

    /** The task was swiped away from recents: end the session with it. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        running = false
        holdWakeLock(this, false)
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    /** The notification's content; [endsAt] is 0 when not counting down. */
    private data class Content(val title: String, val text: String, val endsAt: Long, val action: String?)

    companion object {
        private const val CHANNEL_ID = "session"
        private const val NOTIFICATION_ID = 1
        private const val ACTION_PRIMARY = "com.tonaros.app.SESSION_PRIMARY"

        /** Called (on the main thread) when the notification's button is tapped. */
        var onAction: (() -> Unit)? = null

        /** Whether a session is running, i.e. the notification should be up. */
        private var running = false

        /** What the notification shows: the last start or update. */
        private var latest = Content("Tonaros", "", 0L, null)

        private var wakeLock: PowerManager.WakeLock? = null

        /** Starts the service; call while the app is in the foreground. */
        fun start(context: Context, title: String, text: String, endsAt: Long, action: String?) {
            latest = Content(title, text, endsAt, action)
            running = true
            val intent = Intent(context, SessionService::class.java)
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
         * while the app is in the background. Does nothing once the service
         * has stopped, so a late update can't leave a stray notification.
         */
        fun update(context: Context, title: String, text: String, endsAt: Long, action: String?) {
            if (!running) return
            latest = Content(title, text, endsAt, action)
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID, buildNotification(context, latest))
            holdWakeLock(context, endsAt > 0)
        }

        /** Stopping is allowed at any time, foreground or not. */
        fun stop(context: Context) {
            running = false
            holdWakeLock(context, false)
            context.stopService(Intent(context, SessionService::class.java))
        }

        /** Holds the CPU awake only while the phase timer is counting down. */
        private fun holdWakeLock(context: Context, hold: Boolean) {
            if (hold) {
                if (wakeLock?.isHeld == true) return
                val pm = context.applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Tonaros:session").apply {
                    setReferenceCounted(false)
                    // Safety net: a session never needs more than a few hours.
                    acquire(4 * 60 * 60 * 1000L)
                }
            } else {
                wakeLock?.let { if (it.isHeld) it.release() }
                wakeLock = null
            }
        }

        private fun buildNotification(context: Context, content: Content): Notification {
            val (title, text, endsAt, action) = content
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
                .setSmallIcon(R.drawable.ic_stat_session)
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
                    if (action != null) {
                        val primary = PendingIntent.getService(
                            context,
                            1,
                            Intent(context, SessionService::class.java).setAction(ACTION_PRIMARY),
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        )
                        addAction(0, action, primary)
                    }
                }
                .build()
        }
    }
}
