package org.photolib.photolib

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The runner's diagnostics for app/lib/core/logging.dart's listenToNativeLog (ADR-0115): records wait, at most 1000,
 * until the app asks with `listen`, which they answer; later ones go one at a time as `log` on the main thread.
 */
object NativeLog {
    private const val MAX_WAITING = 1000
    private val main = Handler(Looper.getMainLooper())
    private val waiting = mutableListOf<List<Any?>>()
    private var channel: MethodChannel? = null

    /** Opens the channel of a new engine, whose app has not listened yet. */
    fun register(messenger: BinaryMessenger) {
        val opened = MethodChannel(messenger, "org.photolib/log")
        synchronized(this) { channel = null }
        opened.setMethodCallHandler { call, result ->
            if (call.method != "listen") return@setMethodCallHandler result.notImplemented()
            synchronized(this) {
                channel = opened
                result.success(waiting.toList())
                waiting.clear()
            }
        }
    }

    /** Logs from any thread; [level] is debug, info, warning or error. */
    fun log(
        level: String,
        logger: String,
        message: String,
        fields: Map<String, Any?> = emptyMap(),
    ) {
        val record = listOf(System.currentTimeMillis(), level, logger, message, fields)
        val live =
            synchronized(this) {
                if (channel == null && waiting.size < MAX_WAITING) waiting.add(record)
                channel
            } ?: return
        main.post { live.invokeMethod("log", record) }
    }
}
