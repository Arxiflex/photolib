package org.photolib.photolib

import android.Manifest.permission.READ_EXTERNAL_STORAGE
import android.Manifest.permission.READ_MEDIA_IMAGES
import android.Manifest.permission.READ_MEDIA_VIDEO
import android.Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED
import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.content.pm.PackageManager.PERMISSION_GRANTED
import android.database.ContentObserver
import android.database.Cursor
import android.net.Uri
import android.os.Build.VERSION.SDK_INT
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.storage.StorageManager
import android.provider.MediaStore
import android.provider.MediaStore.Files.FileColumns
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.util.UUID

/**
 * MediaStore for app/lib/core/media_store.dart: queries on a background task queue, never the platform thread, and
 * finalised items only (MediaStore leaves `IS_PENDING` rows out), trashed ones included.
 */
class MediaStoreChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val resolver = activity.contentResolver
    private var pending: MethodChannel.Result? = null
    private var blocked = false

    init {
        MethodChannel(messenger, "org.photolib/media_store", StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue())
            .setMethodCallHandler { call, result ->
                val volume = call.arguments as? String
                when (call.method) {
                    "access" -> result.success(access())
                    "requestAccess" -> activity.runOnUiThread { request(result) }
                    "installId" -> result.success(installId())
                    "volumes" -> result.success(MediaStore.getExternalVolumeNames(activity).toList())
                    "root" -> result.success(root(volume!!))
                    "version" -> result.success(MediaStore.getVersion(activity, volume!!))
                    "generation" -> result.success(MediaStore.getGeneration(activity, volume!!))
                    "count" -> result.success(query(volume!!, arrayOf(FileColumns._ID)).use { it?.count ?: 0 })
                    "ids" -> result.success(query(volume!!, arrayOf(FileColumns._ID)).use { c ->
                        LongArray(c?.count ?: 0) { c!!.moveToPosition(it); c.getLong(0) }
                    })
                    "items" -> {
                        val (name, since, after, limit) = call.arguments as List<*>
                        result.success(items(name as String, (since as Number).toLong(), (after as Number).toLong(), limit as Int))
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(messenger, "org.photolib/media_store/changes").setStreamHandler(object : EventChannel.StreamHandler {
            private var observer: ContentObserver? = null

            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
                    override fun onChange(selfChange: Boolean) = events.success(null)
                }.also { resolver.registerContentObserver(MediaStore.AUTHORITY_URI, true, it) }
            }

            override fun onCancel(arguments: Any?) {
                observer?.let(resolver::unregisterContentObserver)
                observer = null
            }
        })
    }

    private fun query(volume: String, projection: Array<String>, since: Long = 0, after: Long = 0, limit: Int? = null): Cursor? =
        resolver.query(MediaStore.Files.getContentUri(volume), projection, Bundle().apply {
            putString(
                ContentResolver.QUERY_ARG_SQL_SELECTION,
                "${FileColumns.MEDIA_TYPE} IN (${FileColumns.MEDIA_TYPE_IMAGE}, ${FileColumns.MEDIA_TYPE_VIDEO}) " +
                    "AND ${FileColumns.GENERATION_MODIFIED} > ? AND ${FileColumns._ID} > ?",
            )
            putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, arrayOf("$since", "$after"))
            putString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER, FileColumns._ID)
            limit?.let { putInt(ContentResolver.QUERY_ARG_LIMIT, it) }
            putInt(MediaStore.QUERY_ARG_MATCH_TRASHED, MediaStore.MATCH_INCLUDE)
        }, null)

    /** One flat list, in the order media_store.dart reads it. */
    private fun items(volume: String, since: Long, after: Long, limit: Int): List<Any?> {
        val page = ArrayList<Any?>()
        query(volume, COLUMNS, since, after, limit)?.use { c ->
            fun long(i: Int) = if (c.isNull(i)) null else c.getLong(i)
            fun string(i: Int) = if (c.isNull(i)) null else c.getString(i)
            while (c.moveToNext()) {
                page.add(c.getLong(0))
                page.add(c.getLong(1))
                page.add(c.getLong(2))
                page.add(c.getLong(3) * 1000)
                for (i in 4..8) page.add(string(i))
                for (i in 9..13) page.add(long(i))
                page.add(c.getInt(14) != 0)
                page.add(c.getInt(15) != 0)
                page.add(long(16)?.times(1000))
            }
        }
        return page
    }

    /** Where [volume] is mounted, under which its items' files are readable by path; null once it is gone. */
    private fun root(volume: String) = runCatching {
        activity.getSystemService(StorageManager::class.java)
            .getStorageVolume(MediaStore.Files.getContentUri(volume)).directory?.path
    }.getOrNull()

    private fun granted(permission: String) = activity.checkSelfPermission(permission) == PERMISSION_GRANTED

    private fun access() = when {
        if (SDK_INT >= 33) granted(READ_MEDIA_IMAGES) && granted(READ_MEDIA_VIDEO) else granted(READ_EXTERNAL_STORAGE) -> "full"
        SDK_INT >= 34 && granted(READ_MEDIA_VISUAL_USER_SELECTED) -> "partial"
        else -> "none"
    }

    private fun permissions() = when {
        SDK_INT >= 34 -> arrayOf(READ_MEDIA_IMAGES, READ_MEDIA_VIDEO, READ_MEDIA_VISUAL_USER_SELECTED)
        SDK_INT >= 33 -> arrayOf(READ_MEDIA_IMAGES, READ_MEDIA_VIDEO)
        else -> arrayOf(READ_EXTERNAL_STORAGE)
    }

    /** Once the user asked not to be asked again, only the app's settings can grant access; resuming re-reads it. */
    private fun request(result: MethodChannel.Result) {
        if (pending != null) return result.success(access())
        if (blocked) {
            activity.startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", activity.packageName, null)),
            )
            return result.success(access())
        }
        pending = result
        activity.requestPermissions(permissions(), REQUEST)
    }

    /** From MainActivity.onRequestPermissionsResult. */
    fun onPermissionsResult(requestCode: Int) {
        if (requestCode != REQUEST) return
        val access = access()
        blocked = access == "none" && !activity.shouldShowRequestPermissionRationale(permissions()[0])
        pending?.success(access)
        pending = null
    }

    /** A random id in the directory backups and device transfers leave out, so restored app data meets a new one. */
    private fun installId(): String {
        val file = File(activity.noBackupFilesDir, "install_id")
        if (!file.exists()) file.writeText(UUID.randomUUID().toString())
        return file.readText()
    }

    private companion object {
        const val REQUEST = 4601
        val COLUMNS = arrayOf(
            FileColumns._ID, FileColumns.GENERATION_ADDED, FileColumns.SIZE, FileColumns.DATE_MODIFIED,
            FileColumns.DISPLAY_NAME, FileColumns.MIME_TYPE, FileColumns.RELATIVE_PATH, FileColumns.BUCKET_ID,
            FileColumns.BUCKET_DISPLAY_NAME, FileColumns.DATE_TAKEN, FileColumns.WIDTH, FileColumns.HEIGHT,
            FileColumns.ORIENTATION, FileColumns.DURATION, FileColumns.IS_FAVORITE, FileColumns.IS_TRASHED,
            FileColumns.DATE_EXPIRES,
        )
    }
}
