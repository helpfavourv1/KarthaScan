package com.zdmgold.katharscan

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.googlecode.tesseract.android.ResultIterator
import com.googlecode.tesseract.android.TessBaseAPI

/** Runs Tesseract on an image file. Call from a background thread. */
object TessOcr {
    private const val MAX_SIDE = 3000

    fun run(imagePath: String, dataPath: String, language: String): Map<String, Any> {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(imagePath, bounds)
        var sample = 1
        while (bounds.outWidth / sample > MAX_SIDE * 2 || bounds.outHeight / sample > MAX_SIDE * 2) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        val bitmap: Bitmap = BitmapFactory.decodeFile(imagePath, opts)
            ?: throw IllegalArgumentException("Cannot read image")

        val api = TessBaseAPI()
        try {
            if (!api.init(dataPath, language)) throw IllegalStateException("Tesseract init failed for $language")
            api.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
            api.setImage(bitmap)
            val text = api.utf8Text ?: ""
            val lines = ArrayList<Map<String, Any>>()
            val it: ResultIterator? = api.resultIterator
            if (it != null) {
                it.begin()
                do {
                    val t = it.getUTF8Text(TessBaseAPI.PageIteratorLevel.RIL_TEXTLINE) ?: ""
                    if (t.isNotBlank()) {
                        val r = it.getBoundingRect(TessBaseAPI.PageIteratorLevel.RIL_TEXTLINE)
                        lines.add(mapOf(
                            "text" to t,
                            "left" to (r.left * sample).toDouble(),
                            "top" to (r.top * sample).toDouble(),
                            "width" to (r.width() * sample).toDouble(),
                            "height" to (r.height() * sample).toDouble(),
                            "confidence" to it.confidence(TessBaseAPI.PageIteratorLevel.RIL_TEXTLINE).toDouble()
                        ))
                    }
                } while (it.next(TessBaseAPI.PageIteratorLevel.RIL_TEXTLINE))
                it.delete()
            }
            return mapOf("text" to text, "lines" to lines)
        } finally {
            api.recycle()
            bitmap.recycle()
        }
    }
}
