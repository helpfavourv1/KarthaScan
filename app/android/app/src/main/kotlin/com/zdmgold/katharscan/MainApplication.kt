package com.zdmgold.katharscan

import android.content.Context
import io.flutter.app.FlutterApplication
import java.io.File

class MainApplication : FlutterApplication() {
    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        // Force creation of directories WorkManager and WebView expect to exist
        File(noBackupFilesDir.absolutePath).mkdirs()
        File(filesDir.absolutePath).mkdirs()
        File(cacheDir.absolutePath).mkdirs()
        File(filesDir, "app_webview").mkdirs()
    }
}
