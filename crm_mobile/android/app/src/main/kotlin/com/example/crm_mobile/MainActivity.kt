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
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity: FlutterActivity() {
    companion object {
        var methodChannelInstance: MethodChannel? = null
    }

    private val CHANNEL = "com.example.crm_mobile/call_recording"
    private val PERMISSION_REQUEST_CODE = 200
    private val ROLE_REQUEST_CODE = 301

    private var pendingPermissionsQueue = mutableListOf<String>()
    private var pendingResult: MethodChannel.Result? = null
    private var methodChannel: MethodChannel? = null
    private var initialOverlayAction: String? = null
    private var initialOverlayPhone: String? = null
    private var initialOverlayLeadId: String? = null

    override fun onDestroy() {
        if (methodChannelInstance == methodChannel) {
            methodChannelInstance = null
        }
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleOverlayIntent(intent)
        registerPhoneStateListener()
    }

    override fun onResume() {
        super.onResume()
        registerPhoneStateListener()
    }

    private var phoneStateListener: android.telephony.PhoneStateListener? = null

    private fun registerPhoneStateListener() {
        if (phoneStateListener != null) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED) {
            try {
                val tm = getSystemService(Context.TELEPHONY_SERVICE) as? android.telephony.TelephonyManager ?: return
                phoneStateListener = object : android.telephony.PhoneStateListener() {
                    @Deprecated("Deprecated in Java")
                    override fun onCallStateChanged(state: Int, incomingNumber: String?) {
                        super.onCallStateChanged(state, incomingNumber)
                        val num = incomingNumber?.trim().orEmpty()
                        if (num.isNotBlank() && !num.equals("Unknown Number", ignoreCase = true)) {
                            Log.d("MainActivity", "PhoneStateListener detected incoming: $num")
                            CallReceiver.startNewCall(num, isOutgoing = false)
                            if (FloatingOverlayManager.isShowing &&
                                (FloatingOverlayManager.currentPhoneNumber.isBlank() || FloatingOverlayManager.currentPhoneNumber == "Unknown Number")) {
                                FloatingOverlayManager.show(this@MainActivity, num)
                            }
                        }
                    }
                }
                @Suppress("DEPRECATION")
                tm.listen(phoneStateListener, android.telephony.PhoneStateListener.LISTEN_CALL_STATE)
                Log.d("MainActivity", "PhoneStateListener registered successfully")
            } catch (e: Exception) {
                Log.e("MainActivity", "Failed to register PhoneStateListener", e)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleOverlayIntent(intent)
    }

    private fun handleOverlayIntent(intent: Intent?) {
        val action = intent?.action
        val phone = intent?.getStringExtra("EXTRA_PHONE_NUMBER")
        val leadId = intent?.getStringExtra("EXTRA_LEAD_ID") ?: ""
        if (!phone.isNullOrBlank() && (action == "ACTION_VIEW_DETAILS" || action == "ACTION_ADD_LEAD")) {
            intent.action = null
            intent.removeExtra("EXTRA_PHONE_NUMBER")
            intent.removeExtra("EXTRA_LEAD_ID")
            val channel = methodChannel
            if (channel != null) {
                initialOverlayAction = null
                initialOverlayPhone = null
                initialOverlayLeadId = null
                channel.invokeMethod("onFloatingCardAction", mapOf(
                    "action" to action,
                    "phoneNumber" to phone,
                    "leadId" to leadId
                ))
            } else {
                initialOverlayAction = action
                initialOverlayPhone = phone
                initialOverlayLeadId = leadId
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val callRecordingManager = CallRecordingManager(this)
        val documentDownloader = DocumentDownloader(this)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel
        methodChannelInstance = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateFloatingCardLeadInfo" -> {
                    val phone = call.argument<String>("phoneNumber") ?: ""
                    val name = call.argument<String>("leadName") ?: ""
                    val leadId = call.argument<String>("leadId") ?: ""
                    val isExisting = call.argument<Boolean>("isExisting") ?: false
                    val badgeMessage = call.argument<String>("badgeMessage") ?: ""
                    val assignedToName = call.argument<String>("assignedToName") ?: ""
                    val isAssignedToOther = call.argument<Boolean>("isAssignedToOther") ?: false
                    val isAssignedToMe = call.argument<Boolean>("isAssignedToMe") ?: false
                    FloatingOverlayManager.updateLeadInfo(
                        phoneNumber = phone,
                        leadName = name,
                        leadId = leadId,
                        isExisting = isExisting,
                        badgeMessage = badgeMessage,
                        assignedToName = assignedToName,
                        isAssignedToOther = isAssignedToOther,
                        isAssignedToMe = isAssignedToMe
                    )
                    result.success(true)
                }
                "hasOverlayPermission" -> {
                    val hasPerm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    result.success(hasPerm)
                }
                "requestOverlayPermission" -> {
                    var opened = false
                    try {
                        val miuiIntent = Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                            setClassName("com.miui.securitycenter", "com.miui.permcenter.permissions.PermissionsEditorActivity")
                            putExtra("extra_pkgname", packageName)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(miuiIntent)
                        opened = true
                    } catch (_: Exception) {}

                    if (!opened && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                        try {
                            val overlayIntent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                            startActivity(overlayIntent)
                            opened = true
                        } catch (e: Exception) {
                            try {
                                val genericIntent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(genericIntent)
                                opened = true
                            } catch (_: Exception) {}
                        }
                    }

                    if (!opened) {
                        try {
                            val appDetailsIntent = Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$packageName")
                            ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                            startActivity(appDetailsIntent)
                        } catch (_: Exception) {}
                    }
                    result.success(null)
                }
                "hasCallScreeningRole" -> {
                    val held = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val roleManager = getSystemService(android.app.role.RoleManager::class.java)
                        roleManager != null && roleManager.isRoleHeld(android.app.role.RoleManager.ROLE_CALL_SCREENING)
                    } else {
                        true
                    }
                    result.success(held)
                }
                "requestCallScreeningRole" -> {
                    var launched = false
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        try {
                            val roleManager = getSystemService(android.app.role.RoleManager::class.java)
                            if (roleManager != null && roleManager.isRoleAvailable(android.app.role.RoleManager.ROLE_CALL_SCREENING)) {
                                if (!roleManager.isRoleHeld(android.app.role.RoleManager.ROLE_CALL_SCREENING)) {
                                    val roleIntent = roleManager.createRequestRoleIntent(android.app.role.RoleManager.ROLE_CALL_SCREENING)
                                    startActivityForResult(roleIntent, ROLE_REQUEST_CODE)
                                    launched = true
                                } else {
                                    launched = true
                                }
                            }
                        } catch (e: Exception) {
                            Log.e("MainActivity", "Error requesting ROLE_CALL_SCREENING via RoleManager", e)
                        }
                    }

                    if (!launched) {
                        try {
                            val defaultAppsIntent = Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(defaultAppsIntent)
                            launched = true
                        } catch (_: Exception) {}
                    }

                    if (!launched) {
                        try {
                            val appDetailsIntent = Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$packageName")
                            ).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(appDetailsIntent)
                        } catch (_: Exception) {}
                    }
                    result.success(null)
                }
                "getInitialOverlayAction" -> {
                    if (initialOverlayPhone != null) {
                        val data = mapOf(
                            "action" to (initialOverlayAction ?: ""),
                            "phoneNumber" to (initialOverlayPhone ?: ""),
                            "leadId" to (initialOverlayLeadId ?: "")
                        )
                        initialOverlayAction = null
                        initialOverlayPhone = null
                        initialOverlayLeadId = null
                        result.success(data)
                    } else {
                        result.success(null)
                    }
                }
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
                "isCallOngoing" -> {
                    result.success(callRecordingManager.isCallOngoing())
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
                    var durationMs = 0L
                    try {
                        val file = java.io.File(filePath)
                        if (file.exists() && file.length() > 0) {
                            try {
                                android.media.MediaMetadataRetriever().use { mmr ->
                                    try {
                                        mmr.setDataSource(file.absolutePath)
                                    } catch (_: Exception) {
                                        mmr.setDataSource(context, android.net.Uri.fromFile(file))
                                    }
                                    val durStr = mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
                                    durationMs = durStr?.toLongOrNull() ?: 0L
                                }
                            } catch (_: Exception) {}

                            if (durationMs <= 0L) {
                                try {
                                    val mp = android.media.MediaPlayer()
                                    try {
                                        mp.setDataSource(file.absolutePath)
                                    } catch (_: Exception) {
                                        mp.setDataSource(context, android.net.Uri.fromFile(file))
                                    }
                                    mp.prepare()
                                    durationMs = mp.duration.toLong()
                                    mp.release()
                                } catch (_: Exception) {}
                            }
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "Error getting audio duration for $filePath: ${e.message}")
                    }
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
                "openOAuthWebView" -> {
                    val url = call.argument<String>("url") ?: ""
                    val redirectUri = call.argument<String>("redirectUri") ?: ""
                    if (url.isBlank()) {
                        result.error("INVALID_ARGS", "OAuth URL cannot be empty", null)
                        return@setMethodCallHandler
                    }
                    OAuthWebViewManager.open(this, url, redirectUri) { callbackUrl ->
                        result.success(callbackUrl)
                    }
                }
                "closeOAuthWebView" -> {
                    OAuthWebViewManager.dismiss()
                    result.success(true)
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
            val cleanNumber = "tel:${phoneNumber.trim().replace("#", "%23").removePrefix("tel:")}"
            val uri = Uri.parse(cleanNumber)
            val intent = Intent(Intent.ACTION_DIAL, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e("DirectCall", "Error in makeDirectCall", e)
            false
        }
    }

    private fun requestPermissionsSequentially(result: MethodChannel.Result) {
        val permissionsNeeded = mutableListOf(
            Manifest.permission.CALL_PHONE,
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.READ_CONTACTS
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == ROLE_REQUEST_CODE) {
            Log.d("MainActivity", "Role request finished with resultCode=$resultCode")
        }
    }
}
