package com.tickora.crm

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.content.Context
import android.os.Bundle
import android.telecom.TelecomManager
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
    private val PERMISSION_REQUEST_CODE = 200

    private var pendingPermissionsQueue = mutableListOf<String>()
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val callRecordingManager = CallRecordingManager(this)
        val documentDownloader = DocumentDownloader(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermissionsSequentially" -> {
                    requestPermissionsSequentially(result)
                }
                "hasStoragePermission" -> {
                    result.success(callRecordingManager.hasStoragePermission())
                }
                "openStoragePermissionSettings" -> {
                    callRecordingManager.openStoragePermissionSettings(this)
                    result.success(null)
                }
                "requestAllFilesAccess" -> {
                    result.success(true)
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
                    val callTimestampArg = call.argument<Any>("callTimestamp")
                    val callTimestamp = callTimestampArg?.toString()?.toLongOrNull() ?: 0L
                    CoroutineScope(Dispatchers.Main).launch {
                        val paths = callRecordingManager.getAllSystemRecordings(phoneNumber, callTimestamp)
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
                "getAudioDuration" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val durationMs = try {
                        val file = java.io.File(filePath)
                        if (file.exists()) {
                            android.media.MediaMetadataRetriever().use { mmr ->
                                mmr.setDataSource(file.absolutePath)
                                mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                            }
                        } else { 0L }
                    } catch (_: Exception) { 0L }
                    result.success(durationMs)
                }
                "detectCallType" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val fileName = call.argument<String>("fileName") ?: ""
                    val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                    val timestampArg = call.argument<Any>("timestamp")
                    val timestamp = timestampArg?.toString()?.toLongOrNull() ?: 0L
                    val callTimestampArg = call.argument<Any>("callTimestamp")
                    val callTimestamp = callTimestampArg?.toString()?.toLongOrNull() ?: 0L
                    val callType = callRecordingManager.detectCallType(filePath, fileName, phoneNumber, timestamp, callTimestamp)
                    result.success(callType)
                }
                "playNativeAudio" -> {
                    val path = call.argument<String>("path") ?: ""
                    val res = callRecordingManager.startNativeAudio(this, path)
                    result.success(res)
                }
                "forceLoudspeaker" -> {
                    callRecordingManager.forceLoudspeaker(this)
                    result.success(null)
                }
                "startNativeAudio" -> {
                    val path = call.argument<String>("path") ?: ""
                    val res = callRecordingManager.startNativeAudio(this, path)
                    result.success(res)
                }
                "pauseNativeAudio" -> {
                    callRecordingManager.pauseNativeAudio()
                    result.success(null)
                }
                "resumeNativeAudio" -> {
                    callRecordingManager.resumeNativeAudio(this)
                    result.success(null)
                }
                "stopNativeAudio" -> {
                    callRecordingManager.stopNativeAudio()
                    result.success(null)
                }
                "seekNativeAudio" -> {
                    val pos = call.argument<Int>("positionMs") ?: 0
                    callRecordingManager.seekNativeAudio(pos)
                    result.success(null)
                }
                "getNativeAudioState" -> {
                    val res = callRecordingManager.getNativeAudioState()
                    result.success(res)
                }
                "getLatestCallDetails" -> {
                    val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                    val callTimestampArg = call.argument<Any>("callTimestamp")
                    val callTimestamp = callTimestampArg?.toString()?.toLongOrNull() ?: 0L
                    val details = callRecordingManager.getLatestCallDetails(phoneNumber, callTimestamp)
                    result.success(details)
                }
                "getSystemCallLogs" -> {
                    val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                    val logs = callRecordingManager.getSystemCallLogs(phoneNumber)
                    result.success(logs)
                }
                "makeDirectCall" -> {
                    val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                    val success = makeDirectCall(phoneNumber)
                    result.success(success)
                }
                "getDevicePhoneNumber" -> {
                    val phone = callRecordingManager.getDevicePhoneNumber()
                    result.success(phone)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun makeDirectCall(phoneNumber: String): Boolean {
        if (phoneNumber.isBlank()) return false
        return try {
            var cleanNumber = phoneNumber.replace("#", "%23")
            if (!cleanNumber.startsWith("tel:")) {
                cleanNumber = "tel:$cleanNumber"
            }
            val uri = Uri.parse(cleanNumber)

            if (ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CALL_PHONE), PERMISSION_REQUEST_CODE)
                return false
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val telecomManager = getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                if (telecomManager != null) {
                    val extras = Bundle()
                    telecomManager.placeCall(uri, extras)
                    return true
                }
            }

            val intent = Intent(Intent.ACTION_CALL, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            try {
                var cleanNumber = phoneNumber.replace("#", "%23")
                if (!cleanNumber.startsWith("tel:")) {
                    cleanNumber = "tel:$cleanNumber"
                }
                val uri = Uri.parse(cleanNumber)
                val intent = Intent(Intent.ACTION_CALL, uri).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                true
            } catch (ex: Exception) {
                ex.printStackTrace()
                false
            }
        }
    }

    private fun requestPermissionsSequentially(result: MethodChannel.Result) {
        val permissionsNeeded = mutableListOf(
            Manifest.permission.CALL_PHONE,
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.RECORD_AUDIO
        )
        if (Build.VERSION.SDK_INT >= 33) {
            permissionsNeeded.add("android.permission.READ_MEDIA_AUDIO")
            permissionsNeeded.add(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            permissionsNeeded.add(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            permissionsNeeded.add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        }

        val missing = permissionsNeeded.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }.toMutableList()

        if (missing.isEmpty()) {
            result.success(true)
            return
        }

        pendingPermissionsQueue = missing
        pendingResult = result
        requestNextPermission()
    }

    private fun requestNextPermission() {
        if (pendingPermissionsQueue.isNotEmpty()) {
            val nextPermission = pendingPermissionsQueue.removeAt(0)
            ActivityCompat.requestPermissions(this, arrayOf(nextPermission), PERMISSION_REQUEST_CODE)
        } else {
            pendingResult?.success(true)
            pendingResult = null
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            requestNextPermission()
        }
    }
}
