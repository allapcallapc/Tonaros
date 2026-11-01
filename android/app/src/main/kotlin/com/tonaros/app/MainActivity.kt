package com.tonaros.app

import android.Manifest
import android.content.Context
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
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.ref.WeakReference

class MainActivity : FlutterActivity() {
    private val channelName = "com.tonaros/updates"
    private val sessionChannelName = "com.tonaros/session"

    /**
     * While a session runs, the engine - and the Dart session timer with it
     * - outlives this activity: the system may destroy the activity in the
     * background (memory pressure, "Don't keep activities") while
     * SessionService keeps the process alive, and the session must go on.
     * A recreated activity attaches to the same engine, so the running
     * screen is still there. Otherwise the engine goes with the activity, as
     * usual (see [shouldDestroyEngineWithHost]); one left without an
     * activity when the session ends is destroyed then (see "stop").
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        // Here rather than in configureFlutterEngine: a new activity
        // attaching detaches the previous one in between, and the previous
        // one must see the engine is taken.
        host = WeakReference(this)
        return engine ?: FlutterEngine(
            context.applicationContext,
            // As FlutterActivity builds its own engine: with the launch
            // intent's shell args (e.g. from `flutter run`), and state
            // restoration as configured. Plugins are registered here, once
            // per engine: super.configureFlutterEngine skips registering
            // them for an engine provided by the host, as this one is.
            flutterShellArgs.toArray(),
            true,
            shouldRestoreAndSaveState(),
        ).also { engine = it }
    }

    /**
     * Not while a session runs (it goes on in the background), another
     * activity has taken the engine over, or this one is only being
     * recreated for a configuration change (the new one takes it).
     */
    override fun shouldDestroyEngineWithHost(): Boolean =
        !sessionActive && !isChangingConfigurations && host?.get().let { it == null || it === this }

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
        // Called again for each activity attaching to the engine: the
        // handlers below always belong to the current one.
        //
        // The session handler must not reference this activity: the engine
        // keeps it, and may outlive the activity (see provideFlutterEngine),
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
                    sessionActive = true
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
                    sessionActive = false
                    SessionService.stop(appContext)
                    result.success(null)
                    // The session ended with no activity left (the system
                    // destroyed it in the background, or the app was swiped
                    // away): don't keep its isolate and screens for the next
                    // launch. Posted: not from inside the engine's own call.
                    Handler(Looper.getMainLooper()).post {
                        if (!sessionActive && host?.get() == null) destroyRetainedEngine()
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
        // Not when another activity has already taken the engine over.
        if (host?.get() === this) host = null
        // Otherwise the engine (and a running session) live on, and the next
        // activity picks them up.
        if (shouldDestroyEngineWithHost()) {
            clearSessionCallbacks()
            engine = null
        }
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
        /** See [provideFlutterEngine]. */
        var engine: FlutterEngine? = null

        /**
         * The activity using [engine], if any. Weak, so a missed clean-up
         * can't leak it.
         */
        var host: WeakReference<MainActivity>? = null

        /**
         * Between Dart's "start" and "stop": a session is running in
         * [engine], which must outlive the activity until it ends.
         */
        var sessionActive = false

        fun clearSessionCallbacks() {
            SessionService.onAction = null
            SessionService.onDismissed = null
            SessionService.onStartFailed = null
        }

        /** Destroys [engine] while no activity uses it; see "stop". */
        fun destroyRetainedEngine() {
            clearSessionCallbacks()
            engine?.destroy()
            engine = null
        }

        /** Unlikely to collide with the request codes plugins use. */
        const val NOTIFICATION_PERMISSION_REQUEST = 0x7a01
    }
}
