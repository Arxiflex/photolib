package org.photolib.photolib

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ColorSpace
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.util.Size
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * MediaStore's thumbnails for app/lib/features/library/timeline/platform_thumbnails.dart: `loadThumbnail` at the
 * tier on cores − 1 threads, which MediaStore caches and rotates upright, handed over as width, height and sRGB RGBA
 * (ADR-0040). Cancelling a request drops it from the queue or stops its decode.
 */
class ThumbnailChannel(private val resolver: ContentResolver, messenger: BinaryMessenger) {
    private val pool = Executors.newFixedThreadPool(maxOf(1, Runtime.getRuntime().availableProcessors() - 1))
    private val signals = ConcurrentHashMap<Int, CancellationSignal>()
    private val main = Handler(Looper.getMainLooper())

    init {
        MethodChannel(messenger, "org.photolib/thumbnails").setMethodCallHandler { call, result ->
            when (call.method) {
                "load" -> {
                    val (uri, tier, id) = call.arguments as List<*>
                    val signal = CancellationSignal().also { signals[id as Int] = it }
                    pool.execute {
                        val pixels = try {
                            if (signal.isCanceled) null else load(Uri.parse(uri as String), tier as Int, signal)
                        } catch (e: Exception) {
                            if (!signal.isCanceled) {
                                val fields = mapOf("uri" to uri, "error" to "$e")
                                NativeLog.log("warning", "thumbnails", "loadThumbnail failed", fields)
                            }
                            null
                        }
                        signals.remove(id)
                        main.post { result.success(pixels) }
                    }
                }
                "cancel" -> {
                    signals.remove(call.arguments as Int)?.cancel()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun load(uri: Uri, tier: Int, signal: CancellationSignal): List<Any> {
        val thumbnail = resolver.loadThumbnail(uri, Size(tier, tier), signal)
        // Drawing converts a wide-gamut (Display P3, Adobe RGB) or 16-bit thumbnail to what Flutter takes.
        val bitmap = if (thumbnail.config == Bitmap.Config.ARGB_8888 && thumbnail.colorSpace?.isSrgb == true) {
            thumbnail
        } else {
            val srgb = ColorSpace.get(ColorSpace.Named.SRGB)
            Bitmap.createBitmap(thumbnail.width, thumbnail.height, Bitmap.Config.ARGB_8888, thumbnail.hasAlpha(), srgb)
                .also { Canvas(it).drawBitmap(thumbnail, 0f, 0f, null) }
        }
        val pixels = ByteBuffer.allocate(bitmap.width * bitmap.height * 4)
        bitmap.copyPixelsToBuffer(pixels)
        return listOf(bitmap.width, bitmap.height, pixels.array())
    }
}
