package org.photolib.photolib

import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

/**
 * The phone's own text recognition for app/lib/core/ml.dart (ADR-0388): Google ML Kit with its models bundled in the
 * app, so nothing downloads and nothing needs Play services at run time. The Play flavour only: ML Kit is not free
 * software (tools/scan_libre.py), so the libre flavour has the stub of src/libre. What it reads is untrusted text; the
 * data isolate cleans it before it is kept.
 */
object PlatformText {
    const val ENGINE: String = "mlkit"

    // ML Kit has no Cyrillic model: Latin, Chinese and Japanese read here, and the server's PP-OCR reads the rest.
    private val recognisers: List<TextRecognizer> by lazy {
        listOf(
            TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS),
            TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build()),
            TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build()),
        )
    }

    /** Tells [done] the text of [bitmap] as the recogniser surest of it read it, or null when none read any. */
    fun recognise(
        bitmap: Bitmap,
        done: (String?) -> Unit,
    ) {
        val image = InputImage.fromBitmap(bitmap, 0)
        val read = arrayOfNulls<Text>(recognisers.size)
        var pending = recognisers.size
        for ((i, recogniser) in recognisers.withIndex()) {
            recogniser
                .process(image)
                .addOnSuccessListener { read[i] = it }
                .addOnFailureListener { NativeLog.log("warning", "ml", "ML Kit failed", mapOf("error" to "$it")) }
                .addOnCompleteListener {
                    // Listeners run on the main thread, one at a time.
                    if (--pending == 0) done(surest(read.filterNotNull()))
                }
        }
    }

    /** The reading with the most confidence in all, its confidences summed per word: more text read surely wins. */
    private fun surest(readings: List<Text>): String? =
        readings
            .filter { it.text.isNotBlank() }
            .maxByOrNull { reading ->
                reading.textBlocks.sumOf { block ->
                    block.lines.sumOf { line -> line.elements.sumOf { it.confidence.toDouble() } }
                }
            }?.text
}
