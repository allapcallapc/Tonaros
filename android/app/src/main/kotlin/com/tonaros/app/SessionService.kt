package com.tonaros.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
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
 * a long pause doesn't drain the battery. The lock is let go a few seconds
 * after the countdown ends rather than at once, so the cue that starts the
 * paused or waiting phase still gets to play.
 *
 * Started, updated and stopped from Dart over the "com.tonaros/session"
 * channel - see lib/services/background_session.dart.
 */
class SessionService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startPending = false
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
            // Stopped before the system got round to starting it (stop()
            // leaves the service to us then). Still had to call
            // startForeground: skipping it after startForegroundService
            // crashes the app.
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        holdWakeLock(this, if (latest.endsAt > 0) Hold.COUNTING_DOWN else Hold.GRACE)
        // If the system kills the process anyway, don't restart a session
        // nobody is watching.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        // Not resetting [running]: a new session may already have been
        // started. stop() and onTaskRemoved() reset it. Only a grace period
        // on the wake lock: the session's final cue may still be playing.
        holdWakeLock(this, Hold.GRACE)
        super.onDestroy()
    }

    /** The task was swiped away from recents: end the session with it. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        running = false
        holdWakeLock(this, Hold.NONE)
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    /** The notification's content; [endsAt] is 0 when not counting down. */
    private data class Content(val title: String, val text: String, val endsAt: Long, val action: String?)

    private enum class Hold { COUNTING_DOWN, GRACE, NONE }

    /**
     * The notification's Pause/Resume/Continue button. A broadcast rather
     * than a service intent: starting a service from the background is
     * refused on Android 12+, and the service may already have stopped while
     * a stale notification is still up.
     */
    class ActionReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != ACTION_PRIMARY) return
            if (running) {
                // Handled by the running screen in Dart, which then updates
                // the notification.
                onAction?.invoke()
            } else {
                // Left over from a session that has ended: take it down.
                notificationManager(context).cancel(NOTIFICATION_ID)
            }
        }
    }

    companion object {
        private const val CHANNEL_ID = "session"
        private const val NOTIFICATION_ID = 1
        private const val ACTION_PRIMARY = "com.tonaros.app.SESSION_PRIMARY"

        /** Called (on the main thread) when the notification's button is tapped. */
        var onAction: (() -> Unit)? = null

        /** Whether a session is running, i.e. the notification should be up. */
        private var running = false

        /**
         * Whether startForegroundService was called and onStartCommand
         * hasn't run yet. stop() must not stop the service then: stopped
         * before it is created, it never gets to call startForeground, and
         * Android (notably 8.x) kills the app for that.
         */
        private var startPending = false

        /** What the notification shows: the last start or update. */
        private var latest = Content("Tonaros", "", 0L, null)

        private var wakeLock: PowerManager.WakeLock? = null

        /** Created once per process, see [buildNotification]. */
        private var channelCreated = false
        private var openAppIntent: PendingIntent? = null
        private var primaryIntent: PendingIntent? = null

        /** Long enough for a phase's start cue to be played. */
        private const val WAKE_LOCK_GRACE_MS = 5_000L

        /** Safety net: a session never needs more than a few hours. */
        private const val WAKE_LOCK_MAX_MS = 4 * 60 * 60 * 1000L

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
            // After the call, so a start that threw isn't waited on. Both
            // this and onStartCommand run on the main thread.
            startPending = true
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
            notificationManager(context).notify(NOTIFICATION_ID, buildNotification(context, latest))
            holdWakeLock(context, if (endsAt > 0) Hold.COUNTING_DOWN else Hold.GRACE)
        }

        /**
         * Stopping is allowed at any time, foreground or not. The wake lock
         * runs out after a grace period, so the "session complete" cue can
         * still play with the screen off.
         */
        fun stop(context: Context) {
            running = false
            holdWakeLock(context, Hold.GRACE)
            // A start still on its way: onStartCommand sees [running] is
            // false and stops the service once it is in the foreground.
            if (startPending) return
            context.stopService(Intent(context, SessionService::class.java))
        }

        /**
         * Holds the CPU awake while the phase timer is counting down. When
         * the countdown stops (paused, waiting for a tap) the lock is kept
         * for a short grace period instead of released at once: the new
         * phase's cue is sent to the audio and vibration plugins
         * asynchronously, and the device could otherwise sleep before it
         * plays.
         */
        private fun holdWakeLock(context: Context, hold: Hold) {
            when (hold) {
                Hold.COUNTING_DOWN -> {
                    val lock = wakeLock ?: (context.applicationContext
                        .getSystemService(Context.POWER_SERVICE) as PowerManager)
                        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Tonaros:session")
                        .apply { setReferenceCounted(false) }
                        .also { wakeLock = it }
                    // Not reference counted: re-acquiring just replaces the
                    // timeout, e.g. a grace period that was running.
                    lock.acquire(WAKE_LOCK_MAX_MS)
                }
                // Only shortens a lock that is held; never takes a new one.
                Hold.GRACE -> wakeLock?.let { if (it.isHeld) it.acquire(WAKE_LOCK_GRACE_MS) }
                Hold.NONE -> {
                    wakeLock?.let { if (it.isHeld) it.release() }
                    wakeLock = null
                }
            }
        }

        private fun notificationManager(context: Context) =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        private fun buildNotification(context: Context, content: Content): Notification {
            val (title, text, endsAt, action) = content
            val app = context.applicationContext
            if (!channelCreated) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    // A no-op if the channel already exists.
                    notificationManager(app).createNotificationChannel(
                        NotificationChannel(CHANNEL_ID, "Running session", NotificationManager.IMPORTANCE_LOW).apply {
                            description = "Shows the current exercise while a session runs"
                            setShowBadge(false)
                        }
                    )
                }
                channelCreated = true
            }

            val openApp = openAppIntent ?: PendingIntent.getActivity(
                app,
                0,
                Intent(app, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ).also { openAppIntent = it }

            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_session)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(openApp)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setCategory(NotificationCompat.CATEGORY_WORKOUT)
                // Phase, countdown and button on the lock screen too: the
                // point is following the session with the screen off.
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
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
                        val primary = primaryIntent ?: PendingIntent.getBroadcast(
                            app,
                            1,
                            Intent(app, ActionReceiver::class.java).setAction(ACTION_PRIMARY),
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        ).also { primaryIntent = it }
                        addAction(0, action, primary)
                    }
                }
                .build()
        }
    }
}
