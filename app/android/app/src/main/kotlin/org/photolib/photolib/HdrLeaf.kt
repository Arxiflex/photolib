package org.photolib.photolib

import android.app.Activity
import android.content.Context
import android.content.pm.ActivityInfo
import android.graphics.ImageDecoder
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.view.Gravity
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.concurrent.Executors

private const val TYPE = "photolib/hdr"

/** Keeps a decoded bitmap under the 100 MB that Android's canvas draws. */
private const val MAX_PIXELS = 24_000_000L
private val decoder = Executors.newSingleThreadExecutor()
private var live = 0

/**
 * The native HDR leaf of docs/10 §4.5 (ADR-0060): an ImageView with the gain-map bitmap, or MediaPlayer on a
 * SurfaceView, while the window is in COLOR_MODE_HDR. Flutter keeps every gesture and draws its SDR frame on top
 * until the leaf reports `rendered`.
 */
class HdrLeafFactory(private var activity: Activity, private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    @RequiresApi(34)
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as Map<*, *>
        return HdrLeaf(
            activity, Uri.parse(params["uri"] as String), params["video"] == true,
            MethodChannel(messenger, "$TYPE/$viewId"),
        )
    }

    companion object {
        /** The factory of the process's one engine, which outlives activities: each new one takes it over. */
        private var registered: HdrLeafFactory? = null

        fun register(activity: Activity, engine: FlutterEngine) {
            val messenger = engine.dartExecutor.binaryMessenger
            val factory = registered ?: HdrLeafFactory(activity, messenger)
            if (factory !== registered) {
                engine.platformViewsController.registry.registerViewFactory(TYPE, factory)
                registered = factory
            }
            factory.activity = activity
            MethodChannel(messenger, TYPE).setMethodCallHandler { call, result ->
                if (call.method == "support") result.success(support(activity)) else result.notImplemented()
            }
        }

        /** ImageDecoder keeps gain maps from Android 14; battery saver shows SDR. */
        private fun support(activity: Activity) = when {
            Build.VERSION.SDK_INT < 34 -> "none"
            activity.getSystemService(PowerManager::class.java)?.isPowerSaveMode == true -> "sdr"
            activity.display?.isHdr == true -> "hdr"
            else -> "sdr"
        }
    }
}

@RequiresApi(34)
private class HdrLeaf(
    private val activity: Activity,
    uri: Uri,
    video: Boolean,
    private val channel: MethodChannel,
) : PlatformView {
    private val root = FrameLayout(activity)
    private val main = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var disposed = false

    init {
        if (live++ == 0) activity.window.colorMode = ActivityInfo.COLOR_MODE_HDR
        if (video) play(uri) else show(uri)
    }

    override fun getView(): View = root

    override fun dispose() {
        disposed = true
        player?.release()
        if (--live == 0) activity.window.colorMode = ActivityInfo.COLOR_MODE_DEFAULT
    }

    private fun report(event: String) {
        main.post { if (!disposed) channel.invokeMethod(event, null) }
    }

    /** A file or MediaStore item. */
    private fun show(uri: Uri) {
        val image = ImageView(activity)
        root.addView(image)
        decoder.execute {
            val bitmap = runCatching {
                val source = ImageDecoder.createSource(activity.contentResolver, uri)
                ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                    var sample = 1
                    while (info.size.width.toLong() * info.size.height > MAX_PIXELS * sample * sample) sample *= 2
                    decoder.setTargetSampleSize(sample)
                }
            }.getOrNull()
            main.post {
                if (disposed) return@post
                if (bitmap == null) return@post report("failed")
                image.setImageBitmap(bitmap)
                root.viewTreeObserver.registerFrameCommitCallback { report("rendered") }
            }
        }
    }

    private fun play(uri: Uri) {
        val surface = SurfaceView(activity)
        root.addView(surface)
        surface.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                player = MediaPlayer().apply {
                    setOnVideoSizeChangedListener { _, width, height -> fit(surface, width, height) }
                    setOnInfoListener { _, what, _ ->
                        if (what == MediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START) report("rendered")
                        false
                    }
                    setOnErrorListener { _, _, _ ->
                        report("failed")
                        true
                    }
                    setOnPreparedListener { it.start() }
                    isLooping = true
                    setDisplay(holder)
                    runCatching { setDataSource(activity, uri); prepareAsync() }.onFailure { report("failed") }
                }
            }

            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = Unit

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                player?.release()
                player = null
            }
        })
    }

    /** Letterboxes the video in the leaf. */
    private fun fit(view: View, width: Int, height: Int) {
        if (width == 0 || height == 0) return
        val scale = minOf(root.width.toFloat() / width, root.height.toFloat() / height)
        view.layoutParams = FrameLayout.LayoutParams((width * scale).toInt(), (height * scale).toInt(), Gravity.CENTER)
    }
}
