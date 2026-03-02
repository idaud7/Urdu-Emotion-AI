package com.example.urdu_emotion_ai

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.urdu_emotion_ai/audio_picker"
    private val PICK_AUDIO_REQUEST = 101
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickAudioFile" -> {
                        pendingResult = result
                        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                            type = "audio/*"
                            addCategory(Intent.CATEGORY_OPENABLE)
                            putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                        }
                        startActivityForResult(
                            Intent.createChooser(intent, "Select Audio File"),
                            PICK_AUDIO_REQUEST
                        )
                    }
                    "saveToDownloads" -> {
                        val sourcePath = call.argument<String>("path")
                        val fileName = call.argument<String>("fileName")
                        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                        if (sourcePath != null && fileName != null) {
                            val saved = saveToDownloads(sourcePath, fileName, mimeType)
                            if (saved) {
                                result.success(true)
                            } else {
                                result.error("SAVE_FAILED", "Could not save to Downloads", null)
                            }
                        } else {
                            result.error("INVALID_ARGS", "Missing path or fileName", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_AUDIO_REQUEST) {
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri: Uri = data.data!!
                val filePath = copyUriToTempFile(uri)
                if (filePath != null) {
                    pendingResult?.success(filePath)
                } else {
                    pendingResult?.error("COPY_FAILED", "Could not read selected file", null)
                }
            } else {
                pendingResult?.success(null) // user cancelled
            }
            pendingResult = null
        }
    }

    /** Saves a file to the public Downloads folder using MediaStore (Android 10+)
     *  or direct file copy (Android 9 and below). */
    private fun saveToDownloads(sourcePath: String, fileName: String, mimeType: String): Boolean {
        return try {
            val sourceFile = File(sourcePath)
            if (!sourceFile.exists()) return false

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+ — use MediaStore (no extra permissions needed)
                val contentValues = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                    put(MediaStore.Downloads.MIME_TYPE, mimeType)
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues
                )
                if (uri != null) {
                    contentResolver.openOutputStream(uri)?.use { output ->
                        sourceFile.inputStream().use { input ->
                            input.copyTo(output)
                        }
                    }
                    contentValues.clear()
                    contentValues.put(MediaStore.Downloads.IS_PENDING, 0)
                    contentResolver.update(uri, contentValues, null, null)
                    true
                } else {
                    false
                }
            } else {
                // Android 9 and below — direct file copy to public Downloads
                @Suppress("DEPRECATION")
                val downloadsDir = Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS
                )
                if (!downloadsDir.exists()) downloadsDir.mkdirs()
                val destFile = File(downloadsDir, fileName)
                sourceFile.copyTo(destFile, overwrite = true)
                true
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    /** Copies a content:// URI to a temp file the app can read, returns its path. */
    private fun copyUriToTempFile(uri: Uri): String? {
        return try {
            val mimeType = contentResolver.getType(uri) ?: "audio/mpeg"
            val ext = when {
                mimeType.contains("wav")  -> "wav"
                mimeType.contains("ogg")  -> "ogg"
                mimeType.contains("mp4") || mimeType.contains("m4a") -> "m4a"
                mimeType.contains("opus") -> "opus"
                else -> "mp3"
            }
            val tmpFile = File(cacheDir, "picked_audio_${System.currentTimeMillis()}.$ext")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(tmpFile).use { output ->
                    input.copyTo(output)
                }
            }
            tmpFile.absolutePath
        } catch (e: Exception) {
            null
        }
    }
}
