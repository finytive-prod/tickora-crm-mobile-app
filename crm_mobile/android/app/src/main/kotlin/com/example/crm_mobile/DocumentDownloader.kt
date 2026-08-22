package com.example.crm_mobile

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import java.io.File

import android.content.Intent
import android.net.Uri
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider

class DocumentDownloader(private val context: Context) {

    fun saveDocumentToDownloads(filePath: String, fileName: String, mimeType: String?): String? {
        val srcFile = File(filePath)
        if (!srcFile.exists()) return null

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = context.contentResolver
                val contentValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    if (!mimeType.isNullOrEmpty()) {
                        put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    }
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }

                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                if (uri != null) {
                    resolver.openOutputStream(uri)?.use { output ->
                        srcFile.inputStream().use { input ->
                            input.copyTo(output)
                        }
                    }
                    contentValues.clear()
                    contentValues.put(MediaStore.MediaColumns.IS_PENDING, 0)
                    resolver.update(uri, contentValues, null, null)

                    Log.d("DocumentDownloader", "Successfully saved via MediaStore: $uri")
                    return uri.toString()
                }
            }

            @Suppress("DEPRECATION")
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!downloadsDir.exists()) {
                downloadsDir.mkdirs()
            }
            val destFile = File(downloadsDir, fileName)
            srcFile.copyTo(destFile, overwrite = true)

            MediaScannerConnection.scanFile(
                context,
                arrayOf(destFile.absolutePath),
                arrayOf(mimeType ?: "*/*")
            ) { path, uri ->
                Log.d("DocumentDownloader", "MediaScanner scanned $path -> $uri")
            }

            Log.d("DocumentDownloader", "Successfully saved to File: ${destFile.absolutePath}")
            return destFile.absolutePath
        } catch (e: Exception) {
            Log.e("DocumentDownloader", "Failed to save document to Downloads", e)
        }
        return null
    }

    fun openFile(filePath: String, mimeType: String?) {
        try {
            val file = File(filePath)
            if (!file.exists()) {
                Log.e("DocumentDownloader", "File does not exist: $filePath")
                return
            }

            val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.fileprovider",
                    file
                )
            } else {
                Uri.fromFile(file)
            }

            var type = mimeType
            if (type.isNullOrEmpty() || type == "*/*") {
                val extension = MimeTypeMap.getFileExtensionFromUrl(filePath)
                if (!extension.isNullOrEmpty()) {
                    type = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension.lowercase())
                }
            }

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, type ?: "*/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            val chooser = Intent.createChooser(intent, "Open File").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(chooser)
        } catch (e: Exception) {
            Log.e("DocumentDownloader", "Failed to open file: $filePath", e)
        }
    }
}
