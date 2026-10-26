package org.photolib.photolib

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import kotlin.math.roundToInt

/**
 * On-device ML for app/lib/core/ml.dart (ADR-0254): `decode` hands the indexer a MediaStore image upright, in sRGB and
 * straight RGBA, its short side at most `size`, or null; `recognize` hands the same image to the platform's own text
 * recognition ([PlatformText]) and answers its text, `textSupport` its name or null; `schedule` leaves the backlog to WorkManager while charging
 * (design 09 §3.4), which asks for it in [MlWorker], and `cancel` takes it back.
 */
class MlChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    init {
        MethodChannel(messenger, "org.photolib/ml").setMethodCallHandler { call, result ->
            when (call.method) {
                "decode" -> {
                    val id = call.argument<String>("id")
                    val size = call.argument<Int>("size") ?: 0
                    pool.execute {
                        val pixels =
                            try {
                                decode(id?.toLong() ?: error("no id"), size)
                            } catch (e: Exception) {
                                NativeLog.log("warning", "ml", "decode failed", mapOf("id" to id, "error" to "$e"))
                                null
                            }
                        main.post { result.success(pixels) }
                    }
                }

                "textSupport" -> {
                    result.success(PlatformText.ENGINE)
                }

                "recognize" -> {
                    val id = call.argument<String>("id")
                    val size = call.argument<Int>("size") ?: 0
                    pool.execute {
                        val bitmap =
                            try {
                                bitmap(id?.toLong() ?: error("no id"), size)
                            } catch (e: Exception) {
                                NativeLog.log("warning", "ml", "recognize failed", mapOf("id" to id, "error" to "$e"))
                                null
                            }
                        if (bitmap == null) {
                            main.post { result.success(null) }
                        } else {
                            PlatformText.recognise(bitmap) { text ->
                                bitmap.recycle()
                                main.post { result.success(text) }
                            }
                        }
                    }
                }

                "schedule" -> {
                    enqueue(context, ExistingWorkPolicy.KEEP)
                    result.success(null)
                }

                "cancel" -> {
                    WorkManager.getInstance(context).cancelUniqueWork(WORK)
                    result.success(null)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun decode(
        id: Long,
        size: Int,
    ): Map<String, Any> {
        val bitmap = bitmap(id, size)
        val colors = IntArray(bitmap.width * bitmap.height)
        // Straight ARGB in sRGB whatever the bitmap holds (premultiplied, or F16 from a 10-bit HEIF).
        bitmap.getPixels(colors, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        bitmap.recycle()
        for (i in colors.indices) colors[i] = colors[i].rotateLeft(8)
        val rgba = ByteBuffer.allocate(colors.size * 4).apply { asIntBuffer().put(colors) }.array()
        return mapOf("width" to bitmap.width, "height" to bitmap.height, "rgba" to rgba)
    }

    /** The MediaStore image upright and in sRGB, its short side at most [size]. */
    private fun bitmap(
        id: Long,
        size: Int,
    ): Bitmap {
        val uri = ContentUris.withAppendedId(MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL), id)
        val source = ImageDecoder.createSource(context.contentResolver, uri)
        val bitmap =
            ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                // The size is the upright one: ImageDecoder applies the EXIF orientation.
                val scale = minOf(1.0, size.toDouble() / minOf(info.size.width, info.size.height))
                decoder.setTargetSize(
                    maxOf(1, (info.size.width * scale).roundToInt()),
                    maxOf(1, (info.size.height * scale).roundToInt()),
                )
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                decoder.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB))
            }
        return bitmap
    }

    companion object {
        private const val WORK = "photolib-ml"
        private val pool = Executors.newFixedThreadPool(2)
        private val main = Handler(Looper.getMainLooper())

        /** The backlog's one work, kept while it waits or runs ([policy] KEEP), or after it (APPEND_OR_REPLACE). */
        fun enqueue(
            context: Context,
            policy: ExistingWorkPolicy,
        ) {
            val constraints =
                Constraints
                    .Builder()
                    .setRequiresCharging(true)
                    .setRequiresBatteryNotLow(true)
                    .build()
            val work = OneTimeWorkRequestBuilder<MlWorker>().setConstraints(constraints).build()
            WorkManager.getInstance(context).enqueueUniqueWork(WORK, policy, work)
        }
    }
}

/**
 * The backlog in the background, on the process's one engine (docs/10 §1.5), made headless when no activity has: asks
 * the app's Dart for `background` on org.photolib/ml and waits for its answer, then runs again later when it says
 * `more`; when the system stops the work, `stop` gives it [STOP_GRACE_MS] to store what it is doing.
 */
class MlWorker(
    context: Context,
    parameters: WorkerParameters,
) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result =
        withContext(Dispatchers.Main) {
            val engine = PhotolibApplication.engine(applicationContext)
            if (!engine.dartExecutor.isExecutingDart) {
                engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
            }
            // Flutter keeps the call until main() handles the channel.
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "org.photolib/ml")
            val more = CompletableDeferred<Boolean>()
            channel.invokeMethod(
                "background",
                null,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        more.complete((result as? Map<*, *>)?.get("more") == true)
                    }

                    override fun error(
                        code: String,
                        message: String?,
                        details: Any?,
                    ) {
                        NativeLog.log("warning", "ml", "background failed", mapOf("error" to "$code $message"))
                        more.complete(false)
                    }

                    override fun notImplemented() {
                        more.complete(false)
                    }
                },
            )
            try {
                if (more.await()) MlChannel.enqueue(applicationContext, ExistingWorkPolicy.APPEND_OR_REPLACE)
                Result.success()
            } finally {
                if (!more.isCompleted) {
                    withContext(NonCancellable) {
                        channel.invokeMethod("stop", null)
                        withTimeoutOrNull(STOP_GRACE_MS) { more.await() }
                    }
                }
            }
        }

    private companion object {
        const val STOP_GRACE_MS = 5_000L
    }
}
