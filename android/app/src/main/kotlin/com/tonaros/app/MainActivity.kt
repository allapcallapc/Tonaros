package com.tonaros.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.tonaros/updates"
    private val sessionChannelName = "com.tonaros/session"

    /**
     * The engine - and the Dart session timer with it - outlives this
     * activity: with a session running in the background the system may
     * destroy the activity (memory pressure, "Don't keep activities") while
     * SessionService keeps the process alive, and the session must go on.
     * A recreated activity attaches to the same engine, so the running
     * screen is still there. Destroyed only when the activity is finished
     * for good (see [shouldDestroyEngineWithHost]).
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        engine ?: FlutterEngine(context.applicationContext).also { engine = it }

    override fun shouldDestroyEngineWithHost(): Boolean = isFinishedForGood()

    /** Finished (e.g. swiped away from recents), not just destroyed by the system. */
    private fun isFinishedForGood() = isFinishing && !isChangingConfigurations

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
        SessionService.onAction = { sessionChannel.invokeMethod("action", null) }
        sessionChannel.setMethodCallHandler { call, result ->
            val title = call.argument<String>("title") ?: "Tonaros"
            val text = call.argument<String>("text") ?: ""
            val endsAt = call.argument<Number>("endsAt")?.toLong() ?: 0L
            val action = call.argument<String>("action")
            when (call.method) {
                "start" -> {
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
                    SessionService.stop(appContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Needs this activity (to start the installer), so it is taken off
        // the engine again in cleanUpFlutterEngine.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isInstallPermissionGranted" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        packageManager.canRequestPackageInstalls()
                    } else {
                        true
                    }
                    result.success(granted)
                }
                "openInstallPermissionSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startActivity(
                            Intent(
                                android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )
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
                            this, "$packageName.fileprovider", File(path)
                        )
                        startActivity(Intent(Intent.ACTION_VIEW).apply {
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
        // Its handler holds this activity, which the engine would otherwise
        // keep in memory after the system destroyed it. The next activity
        // sets it again.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler(null)
        // Only destroyed by the system: the engine and the session live on,
        // and the next activity picks them up.
        if (isFinishedForGood()) {
            SessionService.onAction = null
            // The engine (and the Dart session with it) is going away, so the
            // running screen will never stop the service itself: don't leave
            // its notification, dead button and wake lock behind.
            SessionService.stop(applicationContext)
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

        /** Unlikely to collide with the request codes plugins use. */
        const val NOTIFICATION_PERMISSION_REQUEST = 0x7a01
    }
}
