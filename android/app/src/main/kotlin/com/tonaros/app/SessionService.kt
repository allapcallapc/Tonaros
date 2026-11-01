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
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
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
        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                buildNotification(this, latest),
                // The type is required from Android 14; before that, none.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                } else {
                    0
                },
            )
        } catch (e: RuntimeException) {
            // Refused after all, e.g. the app went to the background (Android
            // 12+) before the system got round to this, or the service type
            // isn't accepted. Thrown here, it would crash the app and end the
            // session; without the service the session still runs in the
            // foreground. Updates are ignored from now on, so they can't
            // post a notification with no service behind it, and Dart is
            // told, to start it again once back in the foreground.
            Log.w(TAG, "startForeground refused", e)
            val wasRunning = running
            running = false
            holdWakeLock(this, Hold.GRACE)
            // One an update may already have posted without the service.
            notificationManager(this).cancel(NOTIFICATION_ID)
            // Unlike the stop-before-startForeground case below, startForeground
            // was called. Whether the system still holds the app to it after
            // refusing is up to the system; if it does, it kills the app on its
            // timeout whether the service is stopped or not, so stopping it
            // risks nothing more, and otherwise a refused service isn't left
            // lingering.
            stopSelf()
            // Not for a session that was stopped meanwhile.
            if (wasRunning) onStartFailed?.invoke()
            return START_NOT_STICKY
        }
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
        // A grace period, not released: Dart still has to save the run.
        holdWakeLock(this, Hold.GRACE)
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        // The engine (and the Dart session timer) may outlive the activity
        // (see MainActivity.getCachedEngineId and
        // shouldDestroyEngineWithHost), so stopping the service
        // isn't enough: tell Dart to end the session too, or its cues would
        // carry on with no notification to stop them. Dart saves the run,
        // then calls stop(), which stops the service: until then it keeps
        // the process going (out of the foreground, so the system stops it
        // after a while if that never comes).
        val dismissed = onDismissed
        if (dismissed != null) dismissed() else stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    /** The notification's content; [endsAt] is 0 when not counting down. */
    private data class Content(val title: String, val text: String, val endsAt: Long, val action: String?)

    private enum class Hold { COUNTING_DOWN, GRACE }

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
                // the notification. Passes on the tapped label, so a tap on
                // one that is already out of date does nothing.
                onAction?.invoke(intent.getStringExtra(EXTRA_LABEL))
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
        private const val EXTRA_LABEL = "label"
        private const val TAG = "SessionService"

        /**
         * Called (on the main thread) when the notification's button is
         * tapped, with the label it showed.
         */
        var onAction: ((String?) -> Unit)? = null

        /** Called (on the main thread) when the app is swiped away from recents. */
        var onDismissed: (() -> Unit)? = null

        /**
         * Called (on the main thread) when the system refused the service
         * after start() had returned, so it isn't running.
         */
        var onStartFailed: (() -> Unit)? = null

        /** Whether a session is running, i.e. the notification should be up. */
        private var running = false

        val isRunning: Boolean get() = running

        /**
         * Whether startForegroundService was called and onStartCommand
         * hasn't run yet. stop() must not stop the service then: stopped
         * before it is created, it never gets to call startForeground, and
         * Android (notably 8.x) kills the app for that.
         */
        private var startPending = false

        /** Counts starts, so a stale [START_TIMEOUT_MS] check can tell. */
        private var startCount = 0

        /**
         * How long stop() waits for a pending start's onStartCommand before
         * stopping the service anyway: the system requires startForeground
         * within a few seconds of startForegroundService, so a start that
         * hasn't got there by then has been dropped.
         */
        private const val START_TIMEOUT_MS = 15_000L

        /** What the notification shows: the last start or update. */
        private var latest = Content("Tonaros", "", 0L, null)

        private var wakeLock: PowerManager.WakeLock? = null

        /** Created once per process, see [buildNotification]. */
        private var channelCreated = false
        private var openAppIntent: PendingIntent? = null

        /**
         * One per button label, so each carries its own label: a single
         * PendingIntent updated in place would hand an older notification's
         * button the newest label.
         */
        private val primaryIntents = mutableMapOf<String, PendingIntent>()

        /** Long enough for a phase's start cue to be played. */
        const val WAKE_LOCK_GRACE_MS = 5_000L

        /** Safety net: a session never needs more than a few hours. */
        private const val WAKE_LOCK_MAX_MS = 4 * 60 * 60 * 1000L

        /**
         * Starts the service; call while the app is in the foreground. Throws
         * if the system refuses (e.g. Android 12+ when the app has already
         * gone to the background), leaving nothing running: no service means
         * no notification or wake lock, which update() and stop() could
         * otherwise never take down.
         */
        fun start(context: Context, title: String, text: String, endsAt: Long, action: String?) {
            latest = Content(title, text, endsAt, action)
            // Before the call: onStartCommand checks it, and both run on the
            // main thread, so it can't run in between.
            running = true
            val intent = Intent(context, SessionService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: RuntimeException) {
                running = false
                throw e
            }
            // After the call, so a start that threw isn't waited on.
            startPending = true
            startCount++
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
            // Taken down with the service when it was in the foreground; this
            // covers one posted without it. Harmless for a start still on its
            // way: onStartCommand posts and removes its own.
            notificationManager(context).cancel(NOTIFICATION_ID)
            if (startPending) {
                // A start still on its way: onStartCommand sees [running] is
                // false and stops the service once it is in the foreground.
                // In case it never comes, stop the service later anyway, or
                // [startPending] would keep every later stop() from doing so.
                val app = context.applicationContext
                val start = startCount
                Handler(Looper.getMainLooper()).postDelayed({
                    if (startPending && start == startCount && !running) {
                        startPending = false
                        app.stopService(Intent(app, SessionService::class.java))
                    }
                }, START_TIMEOUT_MS)
                return
            }
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
                        val primary = primaryIntents.getOrPut(action) {
                            PendingIntent.getBroadcast(
                                app,
                                // Distinct request codes keep them distinct
                                // PendingIntents (extras don't count); the
                                // same per label in every process.
                                action.hashCode(),
                                Intent(app, ActionReceiver::class.java)
                                    .setAction(ACTION_PRIMARY)
                                    .putExtra(EXTRA_LABEL, action),
                                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                            )
                        }
                        addAction(0, action, primary)
                    }
                }
                .build()
        }
    }
}
