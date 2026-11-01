package com.tonaros.app

import android.Manifest
import android.content.pm.PackageManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.tonaros/updates"
    private val sessionChannelName = "com.tonaros/session"

    /**
     * While a session runs, the engine - and the Dart session timer with it
     * - outlives this activity: the system may destroy the activity in the
     * background (memory pressure, "Don't keep activities") while
     * SessionService keeps the process alive, and the session must go on.
     * So between Dart's "start" and "stop" the engine sits in
     * [FlutterEngineCache], and a recreated activity attaches to it, with the
     * running screen still there. Otherwise there is no cached engine and the
     * activity builds and destroys its own, as usual.
     */
    override fun getCachedEngineId(): String? =
        ENGINE_ID.takeIf { FlutterEngineCache.getInstance().contains(it) }

    /** Not while the engine is cached: a session is running in it. */
    override fun shouldDestroyEngineWithHost(): Boolean =
        !FlutterEngineCache.getInstance().contains(ENGINE_ID)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // On a fresh launch, on the sessions list - not when a session
        // starts, where the dialog would cover the "get ready" countdown -
        // and not in an activity recreated while a session runs.
        if (savedInstanceState == null && !SessionService.isRunning) {
            requestNotificationPermission()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        attachedHosts++
        // Called again for each activity attaching to the engine: the
        // handlers below always belong to the current one.
        //
        // The session handler must not reference this activity: the engine
        // keeps it, and may outlive the activity (see getCachedEngineId),
        // so only the application context is used.
        val appContext = applicationContext

        // Keeps a running session alive in the background - see SessionService
        // and lib/services/background_session.dart.
        val sessionChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, sessionChannelName)
        // The notification's Pause/Resume/Continue button.
        SessionService.onAction = { label -> sessionChannel.invokeMethod("action", label) }
        // Swiped away from recents: end the Dart session with the service.
        // Dart saves the run, then calls "stop", which lets the engine go if
        // no activity is left - not before, or the run would be lost.
        SessionService.onDismissed = { sessionChannel.invokeMethod("dismissed", null) }
        // The service was refused after "start" had already succeeded: Dart
        // retries once the app is back in the foreground.
        SessionService.onStartFailed = { sessionChannel.invokeMethod("startFailed", null) }
        sessionChannel.setMethodCallHandler { call, result ->
            val title = call.argument<String>("title") ?: "Tonaros"
            val text = call.argument<String>("text") ?: ""
            val endsAt = call.argument<Number>("endsAt")?.toLong() ?: 0L
            val action = call.argument<String>("action")
            when (call.method) {
                "start" -> {
                    // Dart calls "stop" when the session ends, even if the
                    // service is refused here.
                    FlutterEngineCache.getInstance().put(ENGINE_ID, flutterEngine)
                    try {
                        SessionService.start(appContext, title, text, endsAt, action)
                        result.success(null)
                    } catch (e: RuntimeException) {
                        result.error("START_FAILED", e.message, null)
                    }
                }
                "update" -> {
                    SessionService.update(appContext, title, text, endsAt, action)
                    result.success(null)
                }
                "stop" -> {
                    // From now on the engine goes with its activity again.
                    FlutterEngineCache.getInstance().remove(ENGINE_ID)
                    SessionService.stop(appContext)
                    result.success(null)
                    // The session ended with no activity left (the system
                    // destroyed it in the background, or the app was swiped
                    // away): don't keep its isolate and screens for the next
                    // launch. Decided now - no activity can attach to it any
                    // more - but done after the wake lock's grace period:
                    // the "session complete" cue, sent to the audio and
                    // vibration plugins as the session ended, must get to
                    // play before they go with the engine.
                    if (attachedHosts == 0) {
                        clearSessionCallbacks()
                        Handler(Looper.getMainLooper()).postDelayed(
                            { flutterEngine.destroy() },
                            SessionService.WAKE_LOCK_GRACE_MS,
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Only the application context, like the session handler: the engine
        // may outlive this activity, and a session running in the background
        // must not find the handler gone.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isInstallPermissionGranted" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        appContext.packageManager.canRequestPackageInstalls()
                    } else {
                        true
                    }
                    result.success(granted)
                }
                "openInstallPermissionSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        appContext.startActivity(
                            Intent(
                                android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${appContext.packageName}")
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                    }
                    result.success(null)
                }
                "installApk" -> {
                    val path = call.argument<String>("filePath")
                    if (path == null) {
                        result.error("NO_PATH", "filePath is required", null)
                    } else {
                        val uri = FileProvider.getUriForFile(
                            appContext, "${appContext.packageName}.fileprovider", File(path)
                        )
                        appContext.startActivity(Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                        })
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        attachedHosts--
        // The engine is about to be destroyed with this activity.
        if (shouldDestroyEngineWithHost()) clearSessionCallbacks()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /**
     * Android 13+ hides the session notification unless notifications are
     * allowed. Asks on launch while they aren't, so a dismissed prompt comes
     * back next time. Android itself stops showing it once the user has
     * denied it twice; they can still allow it in the system settings.
     * Sessions run either way, so the result needs no handling.
     */
    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            == PackageManager.PERMISSION_GRANTED
        ) return
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    private companion object {
        /** The [FlutterEngineCache] id of the engine a session runs in. */
        const val ENGINE_ID = "session"

        /**
         * Activities attached to the engine: from [configureFlutterEngine]
         * to [cleanUpFlutterEngine]. Can briefly be 2 while a new activity
         * takes the cached engine over from an old one.
         */
        var attachedHosts = 0

        fun clearSessionCallbacks() {
            SessionService.onAction = null
            SessionService.onDismissed = null
            SessionService.onStartFailed = null
        }

        /** Unlikely to collide with the request codes plugins use. */
        const val NOTIFICATION_PERMISSION_REQUEST = 0x7a01
    }
}
