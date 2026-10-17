package com.zdmgold.katharscan

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.android.gms.common.api.OptionalModuleApi
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.zdmgold.katharscan/downloads"
    private val OCR_CHANNEL = "com.zdmgold.katharscan/ocr_models"
    private val TESS_CHANNEL = "com.zdmgold.katharscan/tess_ocr"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Asks Google Play services to download an OCR language pack and reports
        // whether it is ready. Without this request the pack may never arrive.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OCR_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "ensure") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val script = call.argument<String>("script")
            val install = call.argument<Boolean>("install") ?: true
            val api: OptionalModuleApi? = when (script) {
                "chinese" -> TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
                "japanese" -> TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
                "korean" -> TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
                "devanagari" -> TextRecognition.getClient(DevanagariTextRecognizerOptions.Builder().build())
                else -> null
            }
            if (api == null) {
                result.error("UNKNOWN_SCRIPT", "No pack for $script", null)
                return@setMethodCallHandler
            }
            val client = ModuleInstall.getClient(this)
            client.areModulesAvailable(api)
                .addOnSuccessListener { available ->
                    if (available.areModulesAvailable()) {
                        result.success("ready")
                    } else if (!install) {
                        result.success("missing")
                    } else {
                        client.installModules(ModuleInstallRequest.newBuilder().addApi(api).build())
                            .addOnSuccessListener { r ->
                                result.success(if (r.areModulesAlreadyInstalled()) "ready" else "downloading")
                            }
                            .addOnFailureListener { e -> result.error("INSTALL_FAILED", e.message, null) }
                    }
                }
                .addOnFailureListener { e -> result.error("CHECK_FAILED", e.message, null) }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TESS_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "extract") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val imagePath = call.argument<String>("imagePath")
            val dataPath = call.argument<String>("dataPath")
            val language = call.argument<String>("language")
            if (imagePath == null || dataPath == null || language == null) {
                result.error("INVALID_ARGS", "Missing arguments", null)
                return@setMethodCallHandler
            }
            Thread {
                try {
                    val out = TessOcr.run(imagePath, dataPath, language)
                    runOnUiThread { result.success(out) }
                } catch (e: Throwable) {
                    runOnUiThread { result.error("TESS_FAILED", e.message, null) }
                }
            }.start()
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "saveToDownloads") {
                val bytes = call.argument<ByteArray>("bytes")
                val fileName = call.argument<String>("fileName")
                val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"

                if (bytes == null || fileName == null) {
                    result.error("INVALID_ARGS", "Missing bytes or fileName", null)
                    return@setMethodCallHandler
                }

                try {
                    val savedPath = saveFileToDownloads(bytes, fileName, mimeType)
                    result.success(savedPath)
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun saveFileToDownloads(bytes: ByteArray, fileName: String, mimeType: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }

            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw Exception("Failed to create MediaStore entry")

            resolver.openOutputStream(uri)?.use { out ->
                out.write(bytes)
            } ?: throw Exception("Failed to open output stream")

            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)

            return uri.toString()
        } else {
            // Fallback for older Android versions (pre-Android 10)
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!downloadsDir.exists()) downloadsDir.mkdirs()
            val file = File(downloadsDir, fileName)
            file.writeBytes(bytes)
            return file.absolutePath
        }
    }
}
