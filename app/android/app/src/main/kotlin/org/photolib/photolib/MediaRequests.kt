package org.photolib.photolib

import android.app.Activity
import android.app.PendingIntent
import android.content.ContentResolver.QUERY_ARG_SQL_SELECTION
import android.net.Uri
import android.os.Build.VERSION.SDK_INT
import android.os.Bundle
import android.provider.MediaStore
import android.provider.MediaStore.Files.FileColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The platform half of photolib_data's DeletionService and of favourites (docs/10-client-app.md §5.4, ADR-0245):
 * MediaStore's trash, delete and favourite requests for app/lib/core/media_store.dart. A batch is one request, so at
 * most one system dialog, and none once the user let Photolib manage media (MANAGE_MEDIA). tool/deletion_lint.dart
 * allows MediaStore's deletes nowhere else.
 */
class MediaRequests(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val resolver = activity.contentResolver
    private var pending: Pair<MethodChannel.Result, () -> Any?>? = null

    init {
        MethodChannel(messenger, "org.photolib/media_requests").setMethodCallHandler { call, result ->
            val uris = (call.argument<List<String>>("uris") ?: emptyList()).map(Uri::parse)
            val value = call.argument<Boolean>("value") ?: true
            when (call.method) {
                "canManageMedia" -> {
                    result.success(SDK_INT >= 31 && MediaStore.canManageMedia(activity))
                }

                "trash" -> {
                    request(MediaStore.createTrashRequest(resolver, uris, value), result) {
                        if (value) expiries(uris) else null
                    }
                }

                "delete" -> {
                    request(MediaStore.createDeleteRequest(resolver, uris), result) { null }
                }

                "favorite" -> {
                    request(MediaStore.createFavoriteRequest(resolver, uris, value), result) { null }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun request(
        intent: PendingIntent,
        result: MethodChannel.Result,
        done: () -> Any?,
    ) {
        if (pending != null) return result.error("busy", "another request is open", null)
        pending = result to done
        activity.startIntentSenderForResult(intent.intentSender, REQUEST, null, 0, 0, 0)
    }

    /** From MainActivity.onActivityResult: the user's answer, which with MANAGE_MEDIA the system gives at once. */
    fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
    ) {
        if (requestCode != REQUEST) return
        val (result, done) = pending ?: return
        pending = null
        if (resultCode == Activity.RESULT_OK) result.success(done()) else result.error("refused", "refused", null)
    }

    /** When the system deletes each trashed item for good, in milliseconds, in order; one query per volume. */
    private fun expiries(uris: List<Uri>): List<Long?> {
        val found = HashMap<Uri, Long>()
        for ((volume, items) in uris.groupBy { it.pathSegments.first() }) {
            val ids = items.mapNotNull { it.lastPathSegment }.joinToString(",")
            val query =
                Bundle().apply {
                    putString(QUERY_ARG_SQL_SELECTION, "${FileColumns._ID} IN ($ids)")
                    putInt(MediaStore.QUERY_ARG_MATCH_TRASHED, MediaStore.MATCH_INCLUDE)
                }
            val columns = arrayOf(FileColumns._ID, FileColumns.DATE_EXPIRES)
            resolver.query(MediaStore.Files.getContentUri(volume), columns, query, null)?.use { c ->
                while (c.moveToNext()) {
                    val uri = items.firstOrNull { it.lastPathSegment == "${c.getLong(0)}" } ?: continue
                    found[uri] = c.getLong(1) * 1000
                }
            }
        }
        return uris.map { found[it] }
    }

    private companion object {
        const val REQUEST = 4602
    }
}
