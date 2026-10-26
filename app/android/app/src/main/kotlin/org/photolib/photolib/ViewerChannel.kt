package org.photolib.photolib

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.RectF
import android.media.ExifInterface
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * The viewer's side of app/lib/features/viewer/regions.dart: regions of a MediaStore image decoded by a
 * `BitmapRegionDecoder` at a sample size on two threads, in the coordinates and orientation the image is shown in
 * (docs/10 §4.1), handed over as width, height and RGBA; an item's bytes, which an animation plays (animated.dart)
 * and the editor edits (ADR-0331); items shared, set as a wallpaper or contact photo, and an item copied to the
 * clipboard, by URI, or a file of the app's cache shared, as the diagnostic bundle is; a place opened in a maps app;
 * the window's brightness (VIEW-39); and an edited copy saved beside its item.
 */
class ViewerChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    /** A decoder of a file, and the matrix from its stored pixels to the shown ones: EXIF's mirror and turn. */
    private class Opened(
        val file: ParcelFileDescriptor,
        val decoder: BitmapRegionDecoder,
        val shown: Matrix,
    )

    private val pool = Executors.newFixedThreadPool(2)
    private val opened = ConcurrentHashMap<Int, Opened>()
    private val ids = AtomicInteger()
    private val main = Handler(Looper.getMainLooper())

    init {
        MethodChannel(messenger, "org.photolib/viewer").setMethodCallHandler { call, result ->
            fun background(work: () -> Any) =
                pool.execute {
                    val value =
                        try {
                            work()
                        } catch (e: Exception) {
                            NativeLog.log("warning", "viewer", "${call.method} failed", mapOf("error" to "$e"))
                            e
                        }
                    main.post {
                        if (value is Exception) {
                            result.error(
                                "failed",
                                value.message,
                                null,
                            )
                        } else {
                            result.success(value)
                        }
                    }
                }
            when (call.method) {
                "open" -> {
                    background { open(Uri.parse(call.arguments as String)) }
                }

                "read" -> {
                    background {
                        val args = call.arguments as List<*>
                        read(Uri.parse(args[0] as String), args.getOrNull(1) as Int?)
                    }
                }

                "decode" -> {
                    background {
                        val a = (call.arguments as List<*>).map { it as Int }
                        decode(opened.getValue(a[0]), Rect(a[1], a[2], a[3], a[4]), a[5])
                    }
                }

                "close" -> {
                    opened.remove(call.arguments as Int)?.run {
                        decoder.recycle()
                        file.close()
                    }
                    result.success(null)
                }

                "share" -> {
                    val (list, mime) = call.arguments as List<*>
                    // Downloads send a list of MediaStore URIs, the diagnostic bundle one file URI of its own.
                    val uris =
                        ((list as? List<*>) ?: listOf(list)).map {
                            val uri = Uri.parse(it as String)
                            // A file of the app's own goes out through its FileProvider.
                            if (uri.scheme == "file") {
                                FileProvider.getUriForFile(
                                    activity,
                                    "${activity.packageName}.files",
                                    File(requireNotNull(uri.path)),
                                )
                            } else {
                                uri
                            }
                        }
                    val send =
                        if (uris.size == 1) {
                            Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris[0])
                        } else {
                            Intent(Intent.ACTION_SEND_MULTIPLE)
                                .putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
                        }
                    // The clip grants the receiver every URI, not only the first.
                    send.clipData =
                        ClipData
                            .newRawUri(null, uris[0])
                            .apply { uris.drop(1).forEach { addItem(ClipData.Item(it)) } }
                    send.setType(mime as String? ?: "*/*").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    activity.startActivity(Intent.createChooser(send, null))
                    result.success(null)
                }

                // A place, in the maps app the user picks.
                "view" -> {
                    val uri = Uri.parse((call.arguments as List<*>)[0] as String)
                    activity.startActivity(Intent.createChooser(Intent(Intent.ACTION_VIEW, uri), null))
                    result.success(null)
                }

                // A photo, to the apps that set one as a wallpaper or a contact's photo.
                "setAs" -> {
                    val (uri, mime) = call.arguments as List<*>
                    val type = mime as String? ?: "image/*"
                    val attach = Intent(Intent.ACTION_ATTACH_DATA).setDataAndType(Uri.parse(uri as String), type)
                    attach.putExtra("mimeType", type).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    activity.startActivity(Intent.createChooser(attach, null))
                    result.success(null)
                }

                "saveCopy" -> {
                    background { saveCopy(call.arguments as List<*>).toString() }
                }

                "copy" -> {
                    val clip = ClipData.newUri(activity.contentResolver, "", Uri.parse(call.arguments as String))
                    activity.getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
                    result.success(null)
                }

                // The window's brightness, the system's until the viewer sets it.
                "brightness" -> {
                    val window = activity.window.attributes.screenBrightness
                    val resolver = activity.contentResolver
                    val system = Settings.System.getInt(resolver, Settings.System.SCREEN_BRIGHTNESS, 255)
                    result.success(if (window >= 0) window.toDouble() else system / 255.0)
                }

                "setBrightness" -> {
                    val attributes = activity.window.attributes
                    val value = (call.arguments as Double?)?.toFloat()
                    attributes.screenBrightness = value ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    activity.window.attributes = attributes
                    result.success(null)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    /** The first [limit] bytes of the item at [uri], or all of them. */
    private fun read(
        uri: Uri,
        limit: Int?,
    ): ByteArray =
        requireNotNull(activity.contentResolver.openInputStream(uri)).use {
            if (limit == null) {
                it.readBytes()
            } else {
                val bytes = ByteArray(limit)
                var n = 0
                while (n < limit) {
                    val read = it.read(bytes, n, limit - n)
                    if (read < 0) break
                    n += read
                }
                bytes.copyOf(n)
            }
        }

    private fun open(uri: Uri): List<Int> {
        val resolver = activity.contentResolver
        val orientation =
            requireNotNull(resolver.openInputStream(uri)).use {
                ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            }
        // From a descriptor the decoder reads the file as it needs; from a stream it would copy all of it.
        val file = requireNotNull(resolver.openFileDescriptor(uri, "r"))

        @Suppress("DEPRECATION") // newInstance(ParcelFileDescriptor) is API 31.
        val decoder =
            try {
                requireNotNull(BitmapRegionDecoder.newInstance(file.fileDescriptor, false))
            } catch (e: Exception) {
                file.close()
                throw e
            }
        // EXIF's mirrored orientations, then its clockwise turns.
        val shown =
            Matrix().apply {
                if (orientation in listOf(2, 4, 5, 7)) postScale(-1f, 1f)
                postRotate(
                    when (orientation) {
                        3, 4 -> 180f
                        6, 7 -> 90f
                        5, 8 -> 270f
                        else -> 0f
                    },
                )
            }
        val bounds = RectF(0f, 0f, decoder.width.toFloat(), decoder.height.toFloat()).also { shown.mapRect(it) }
        shown.postTranslate(-bounds.left, -bounds.top)
        val id = ids.incrementAndGet()
        opened[id] = Opened(file, decoder, shown)
        return listOf(id, bounds.width().toInt(), bounds.height().toInt())
    }

    /**
     * Inserts an edited copy of an item, the bytes after its URI, as a new JPEG in its folder, `<name>_edit.jpg`
     * (MediaStore numbers a name taken), with its date taken; pending until written, so that no gallery shows half a
     * file. A folder where MediaStore takes no new images, such as Download/, gets it in Pictures/.
     */
    private fun saveCopy(arguments: List<*>): Uri {
        val source = Uri.parse(arguments[0] as String)
        val resolver = activity.contentResolver
        val columns =
            arrayOf(
                MediaStore.MediaColumns.DISPLAY_NAME,
                MediaStore.MediaColumns.RELATIVE_PATH,
                MediaStore.MediaColumns.VOLUME_NAME,
                MediaStore.Images.ImageColumns.DATE_TAKEN,
            )
        val values = ContentValues()
        val cursor = resolver.query(source, columns, null, null, null) ?: error("no item $source")
        val volume = cursor.use { described(it, values) }
        values.put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
        values.put(MediaStore.MediaColumns.IS_PENDING, 1)
        val collection = MediaStore.Images.Media.getContentUri(volume)
        var uri: Uri? = null
        try {
            uri = resolver.insert(collection, values)
        } catch (e: IllegalArgumentException) {
            values.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_PICTURES)
            uri = resolver.insert(collection, values)
        }
        val copy = uri ?: error("MediaStore took no copy of $source")
        try {
            val stream = resolver.openOutputStream(copy) ?: error("cannot write $copy")
            stream.use { it.write(arguments[1] as ByteArray) }
            val written = ContentValues()
            written.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(copy, written, null, null)
        } catch (e: Exception) {
            // deletion-ok: the pending copy this edit inserted
            resolver.delete(copy, null, null)
            throw e
        }
        return copy
    }

    /** The copy's name, folder and date taken from the original's row at [cursor] into [values]; its volume. */
    private fun described(
        cursor: android.database.Cursor,
        values: ContentValues,
    ): String {
        if (!cursor.moveToFirst()) error("no item")
        values.put(MediaStore.MediaColumns.DISPLAY_NAME, "${cursor.getString(0).substringBeforeLast('.')}_edit.jpg")
        values.put(MediaStore.MediaColumns.RELATIVE_PATH, cursor.getString(1))
        if (!cursor.isNull(3)) values.put(MediaStore.Images.ImageColumns.DATE_TAKEN, cursor.getLong(3))
        return cursor.getString(2)
    }

    private fun decode(
        image: Opened,
        region: Rect,
        sample: Int,
    ): List<Any> {
        val stored = RectF(region).also { Matrix().apply { image.shown.invert(this) }.mapRect(it) }
        val options =
            BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
        val bitmap = image.decoder.decodeRegion(Rect().also { stored.round(it) }, options)
        val tile = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, image.shown, false)
        if (tile !== bitmap) bitmap.recycle()
        val pixels = ByteBuffer.allocate(tile.width * tile.height * 4)
        tile.copyPixelsToBuffer(pixels)
        return listOf(tile.width, tile.height, pixels.array())
    }
}
