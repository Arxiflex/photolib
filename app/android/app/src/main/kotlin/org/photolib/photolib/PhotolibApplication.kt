package org.photolib.photolib

import android.app.Application
import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

/**
 * The host of the process's one Flutter engine (docs/10 §1.5): made on the main thread when the activity or background
 * work first asks for it, with the channels that need no activity, and kept in FlutterEngineCache past every activity,
 * so that main() and the data isolate are the same in the foreground and in the background. MainActivity runs main()
 * with its launch intent's route, MlWorker headless when no activity has.
 */
class PhotolibApplication : Application() {
    companion object {
        private const val ENGINE = "photolib"

        fun engine(context: Context): FlutterEngine {
            val cache = FlutterEngineCache.getInstance()
            cache.get(ENGINE)?.let { return it }
            val application = context.applicationContext
            val engine = FlutterEngine(application)
            val messenger = engine.dartExecutor.binaryMessenger
            NativeLog.register(messenger)
            ThumbnailChannel(application.contentResolver, messenger)
            DeviceHealth.register(application, messenger)
            MlChannel(application, messenger)
            cache.put(ENGINE, engine)
            return engine
        }
    }
}
