package org.photolib.photolib

import android.graphics.Bitmap

/**
 * No platform text recognition in the libre flavour: Google ML Kit is not free software (tools/scan_libre.py), so
 * the phone offers no switch to read text, and the server's PP-OCR does. See src/play for the Play flavour.
 */
object PlatformText {
    val ENGINE: String? = null

    fun recognise(
        bitmap: Bitmap,
        done: (String?) -> Unit,
    ) = done(null)
}
