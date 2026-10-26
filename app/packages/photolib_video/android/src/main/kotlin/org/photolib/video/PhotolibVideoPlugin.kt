package org.photolib.video

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.Metadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.container.MdtaMetadataEntry
import androidx.media3.container.Mp4LocationData
import androidx.media3.container.Mp4TimestampData
import androidx.media3.effect.FrameDropEffect
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.InAppMp4Muxer
import androidx.media3.transformer.Transformer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.time.Instant

/** Media3 Transformer runs the plans of photolib_video; the planner and its rules are Dart (lib/src/plan.dart). */
@OptIn(UnstableApi::class)
class PhotolibVideoPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "org.photolib.video")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) =
        channel.setMethodCallHandler(null)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "probe" -> result.success(probe(call.arguments as String))
                "execute" -> execute(call.argument("plan")!!, call.argument("paths")!!, call.argument("out")!!, result)
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("video", e.message, null)
        }
    }

    private fun probe(path: String): Map<String, Any?> {
        val extractor = MediaExtractor().apply { setDataSource(path) }
        val retriever = MediaMetadataRetriever().apply { setDataSource(path) }
        try {
            val formats = (0 until extractor.trackCount).map { extractor.getTrackFormat(it) }
            val track = formats.indexOfFirst { it.getString(MediaFormat.KEY_MIME)!!.startsWith("video/") }
            val video = formats[track]
            extractor.selectTrack(track)
            val keyframes = mutableListOf<Long>()
            while (extractor.sampleTime >= 0) {
                if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) keyframes += extractor.sampleTime
                extractor.advance()
            }
            val tags = buildMap {
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DATE)?.let { put("creation_time", iso(it)) }
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_LOCATION)?.let { put("location", it) }
            }
            return mapOf(
                "width" to video.getInteger(MediaFormat.KEY_WIDTH),
                "height" to video.getInteger(MediaFormat.KEY_HEIGHT),
                "rotation" to video.getInteger(MediaFormat.KEY_ROTATION, 0),
                "fps" to "${video.getInteger(MediaFormat.KEY_FRAME_RATE, 30)}/1",
                "transfer" to TRANSFERS[video.getInteger(MediaFormat.KEY_COLOR_TRANSFER, 0)],
                "hasAudio" to formats.any { it.getString(MediaFormat.KEY_MIME)!!.startsWith("audio/") },
                "durationUs" to video.getLong(MediaFormat.KEY_DURATION),
                "keyframesUs" to keyframes,
                "tags" to tags,
            )
        } finally {
            extractor.release()
            retriever.release()
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun execute(plan: Map<String, Any?>, paths: Map<String, String>, out: String, result: MethodChannel.Result) {
        val video = plan["video"] as Map<String, Any?>?
        val items = (plan["cuts"] as List<Map<String, Any?>>).map { cut ->
            val start = (cut["startUs"] as Number).toLong()
            val clipping = MediaItem.ClippingConfiguration.Builder()
                .setStartPositionUs(start)
                .setEndPositionUs(start + (cut["durationUs"] as Number).toLong())
                // A remux starts on a keyframe (the planner snapped it), which lets Transformer copy the samples.
                .setStartsAtKeyFrame(video == null)
                .build()
            val item = MediaItem.Builder().setUri(Uri.fromFile(File(paths[cut["assetId"]]!!)))
                .setClippingConfiguration(clipping).build()
            EditedMediaItem.Builder(item).apply {
                if (video != null) {
                    // Presentation fits the upright frame into the output with letter- or pillarboxing.
                    setEffects(Effects(listOf(), listOf(
                        Presentation.createForWidthAndHeight(
                            video["width"] as Int, video["height"] as Int, Presentation.LAYOUT_SCALE_TO_FIT),
                        FrameDropEffect.createDefaultFrameDropEffect(rate(video["fps"] as String)),
                    )))
                }
            }.build()
        }
        val sequence = EditedMediaItemSequence.Builder(items)
            .experimentalSetForceAudioTrack(video != null && plan["audio"] == true)
            .build()
        val composition = Composition.Builder(sequence).apply {
            if (video != null) {
                setHdrMode(
                    if (video["transfer"] == "bt709") Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL
                    else Composition.HDR_MODE_KEEP_HDR)
            }
        }.build()
        val tags = plan["tags"] as Map<String, String>
        Transformer.Builder(context)
            .setMuxerFactory(InAppMp4Muxer.Factory { entries -> retag(entries, tags) })
            .apply {
                if (video != null) {
                    setVideoMimeType(MIMES[video["codec"] as String]!!)
                    setAudioMimeType(MimeTypes.AUDIO_AAC)
                }
            }
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) =
                    result.success(null)

                override fun onError(composition: Composition, exportResult: ExportResult, e: ExportException) =
                    result.error("video", e.message, null)
            })
            .build()
            .start(composition, out)
    }

    /** Replaces what the muxer copied from the sources with the plan's tags, so no pairing identifier survives. */
    private fun retag(entries: MutableSet<Metadata.Entry>, tags: Map<String, String>) {
        entries.removeAll { it is MdtaMetadataEntry || it is Mp4TimestampData || it is Mp4LocationData }
        tags["creation_time"]?.let {
            val seconds = Mp4TimestampData.unixTimeToMp4TimeSeconds(Instant.parse(it).toEpochMilli())
            entries += Mp4TimestampData(seconds, seconds)
        }
        tags["location"]?.let { iso6709 ->
            val (latitude, longitude) = Regex("""[+-][\d.]+""").findAll(iso6709).map { it.value.toFloat() }.toList()
            entries += Mp4LocationData(latitude, longitude)
        }
        for ((key, value) in tags) {
            if (key.startsWith("com.apple.quicktime.")) {
                entries += MdtaMetadataEntry(key, value.toByteArray(), MdtaMetadataEntry.TYPE_INDICATOR_STRING)
            }
        }
    }

    companion object {
        private val MIMES =
            mapOf("h264" to MimeTypes.VIDEO_H264, "hevc" to MimeTypes.VIDEO_H265, "av1" to MimeTypes.VIDEO_AV1)
        private val TRANSFERS = mapOf(
            MediaFormat.COLOR_TRANSFER_SDR_VIDEO to "bt709",
            MediaFormat.COLOR_TRANSFER_HLG to "arib-std-b67",
            MediaFormat.COLOR_TRANSFER_ST2084 to "smpte2084",
        )

        private fun rate(fps: String) = fps.split("/").let { (num, den) -> num.toFloat() / den.toFloat() }

        /** MediaMetadataRetriever's date, `20211224T173000.000Z`, as FFmpeg's `2021-12-24T17:30:00Z`. */
        private fun iso(date: String) =
            Regex("""(\d{4})(\d\d)(\d\d)T(\d\d)(\d\d)(\d\d).*""").matchEntire(date)?.destructured
                ?.let { (y, mo, d, h, mi, s) -> "$y-$mo-${d}T$h:$mi:${s}Z" } ?: date
    }
}
