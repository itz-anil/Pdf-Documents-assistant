package com.docmind.docmind

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException

// FragmentActivity is required for the biometric prompt used by App Lock.
class MainActivity : FlutterFragmentActivity() {
    private var pendingSave: (() -> Unit)? = null
    private var pendingDenied: (() -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "docmind/storage")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveToPublic") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")!!
                val name = call.argument<String>("name")!!
                val mime = call.argument<String>("mime")!!
                val run = {
                    try {
                        result.success(saveToPublic(path, name, mime))
                    } catch (e: Exception) {
                        result.error("save_failed", e.message ?: "Could not save the file", null)
                    }
                }
                if (Build.VERSION.SDK_INT < 29 &&
                    checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
                ) {
                    pendingSave = run
                    pendingDenied = { result.error("permission", "Storage permission was denied", null) }
                    requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 4711)
                } else {
                    run()
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 4711) return
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) pendingSave?.invoke() else pendingDenied?.invoke()
        pendingSave = null
        pendingDenied = null
    }

    /** Copies [path] into Downloads/DocMind (or Pictures/DocMind for images). Returns a readable location. */
    private fun saveToPublic(path: String, name: String, mime: String): String {
        val image = mime.startsWith("image/")
        if (Build.VERSION.SDK_INT >= 29) {
            val collection = if (image) {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            }
            val folder = (if (image) Environment.DIRECTORY_PICTURES else Environment.DIRECTORY_DOWNLOADS) + "/DocMind"
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(collection, values) ?: throw IOException("Could not create the file")
            try {
                contentResolver.openOutputStream(uri).use { out ->
                    if (out == null) throw IOException("Could not open the file")
                    FileInputStream(path).use { it.copyTo(out) }
                }
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            } catch (e: Exception) {
                contentResolver.delete(uri, null, null)
                throw e
            }
            return "$folder/$name"
        }
        @Suppress("DEPRECATION")
        val root = Environment.getExternalStoragePublicDirectory(
            if (image) Environment.DIRECTORY_PICTURES else Environment.DIRECTORY_DOWNLOADS
        )
        val dir = File(root, "DocMind").apply { mkdirs() }
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var target = File(dir, name)
        var n = 2
        while (target.exists()) {
            target = File(dir, "$base ($n)$ext")
            n++
        }
        FileInputStream(path).use { input -> FileOutputStream(target).use { input.copyTo(it) } }
        MediaScannerConnection.scanFile(this, arrayOf(target.absolutePath), arrayOf(mime), null)
        return (if (image) "Pictures" else "Download") + "/DocMind/${target.name}"
    }
}
