package com.example.crm_mobile

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.crm_mobile/call_recording"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.READ_CALL_LOG, Manifest.permission.READ_PHONE_STATE), 200)
        }
        
        val callRecordingManager = CallRecordingManager(this)
        val documentDownloader = DocumentDownloader(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasStoragePermission" -> {
                    result.success(callRecordingManager.hasStoragePermission())
                }
                "openStoragePermissionSettings" -> {
                    callRecordingManager.openStoragePermissionSettings(this)
                    result.success(null)
                }
                "findLatestSystemRecording" -> {
                    val callTimestampArg = call.argument<Any>("callTimestamp")
                    val callTimestamp = callTimestampArg?.toString()?.toLongOrNull() ?: 0L
                    val phoneNumber = call.argument<String>("phoneNumber") ?: ""

                    CoroutineScope(Dispatchers.Main).launch {
                        val path = callRecordingManager.findLatestSystemRecording(callTimestamp, phoneNumber)
                        result.success(path)
                    }
                }
                "getAllSystemRecordings" -> {
                    val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                    CoroutineScope(Dispatchers.Main).launch {
                        val paths = callRecordingManager.getAllSystemRecordings(phoneNumber)
                        result.success(paths)
                    }
                }
                "playRecording" -> {
                    val path = call.argument<String>("path") ?: ""
                    callRecordingManager.playRecording(this, path)
                    result.success(null)
                }
                "saveToDownloads" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val fileName = call.argument<String>("fileName") ?: ""
                    val mimeType = call.argument<String>("mimeType")
                    val savedUriOrPath = documentDownloader.saveDocumentToDownloads(filePath, fileName, mimeType)
                    result.success(savedUriOrPath)
                }
                "openFile" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val mimeType = call.argument<String>("mimeType")
                    documentDownloader.openFile(filePath, mimeType)
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
