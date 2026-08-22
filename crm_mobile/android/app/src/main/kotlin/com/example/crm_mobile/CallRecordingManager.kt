package com.example.crm_mobile

import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.CallLog
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Calendar
import kotlin.math.abs

class CallRecordingManager(private val context: Context) {

    companion object {
        private const val TAG = "CallRecordingSync"
        private const val MIN_RECORDING_BYTES = 1024L
        private const val MAX_POST_CALL_WINDOW_MS = 3 * 60 * 1000L

        // All supported audio formats (covers every known dialer output)
        private val VALID_EXTENSIONS = setOf("m4a", "mp3", "aac", "wav", "3gp", "amr", "opus", "ogg")

        // All known call recording folder paths across phone brands
        // Samsung, Pixel, Stock Android, MIUI, Poco, Redmi, OnePlus, Oppo, Vivo, Realme,
        // Huawei, LG, Asus, Nothing, Cube ACR, Boldbeast, third-party dialers
        private val CALL_RECORDING_DIRS: List<String> = listOf(
            "Recordings/Call",                           // Samsung, Pixel, Stock Android
            "Call",                                      // Some Samsung variants
            "CallRecordings",                            // OnePlus, Realme
            "call_recordings",                           // Some third-party dialers
            "MIUI/sound_recorder/call_rec",              // Xiaomi MIUI dialer
            "Recordings/sound_recorder/call_rec",        // Newer MIUI
            "Sounds/Call",                               // Some Samsung variants
            "Record/Call",                               // Oppo, ColorOS
            "Record/PhoneRecord",                        // Oppo variants
            "Music/Recordings/Call Recordings",          // Vivo (Funtouch OS)
            "Music/record/call",                         // Vivo variants
            "Recordings",                                // Generic fallback
            "PhoneRecord",                               // Huawei
            "sounds/callrecord",                         // Huawei variants
            "Record/Phone",                              // Realme variants
            "CubeCallRecorder/All",                      // Cube ACR
            "CubeCallRecorder",                          // Cube ACR root
            "BoldBeast",                                 // Boldbeast recorder
            "ACR Recordings",                            // ACR app
            "Download",                                  // Some dialers dump here
            "Music",                                     // Some third-party dialers
            "Audio",                                     // Generic audio folder
        )

        // Date patterns to strip before checking for conflicting phone numbers
        private val DATE_STRIP_PATTERNS = listOf(
            Regex("20\\d{2}[-_./]?\\d{2}[-_./]?\\d{2}"),  // 2026-08-18, 20260818, 2026_08_18
            Regex("\\d{2}[-_./]\\d{2}[-_./]\\d{2,4}"),     // 18-08-2026, 18_08_26
            Regex("\\d{2}[-_./]?\\d{2}[-_./]?\\d{2}"),     // 180818, 18-08-18
            Regex("\\d{1,2}[-_.]\\d{1,2}[-_.]\\d{1,2}"),   // Time patterns: 18-55-30
            Regex("\\b1\\d{12}\\b"),                         // Epoch timestamps
        )
    }

    fun hasStoragePermission(): Boolean = PermissionUtils.hasStoragePermission(context)

    fun openStoragePermissionSettings(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && !Environment.isExternalStorageManager()) {
            try {
                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                    data = Uri.parse("package:${context.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                return
            } catch (e: Exception) {
                val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                runCatching { context.startActivity(intent) }
                return
            }
        }

        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", context.packageName, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        runCatching { context.startActivity(intent) }
    }

    /** Returns the list of directories to scan, resolved from the companion list. */
    private fun getCallRecordingDirs(): List<File> {
        val root = Environment.getExternalStorageDirectory()
        val dirs = CALL_RECORDING_DIRS.map { File(root, it) }.toMutableList()
        dirs.add(root)
        return dirs
    }

    /** Checks if a file is a valid recording candidate. */
    private fun isValidRecording(f: File): Boolean =
        f.isFile && f.canRead() && f.length() >= MIN_RECORDING_BYTES &&
                VALID_EXTENSIONS.contains(f.extension.lowercase())

    /** Extracts clean phone digits from a raw phone string. */
    private fun cleanPhone(phone: String): String = phone.replace("[^0-9]".toRegex(), "")

    /** Checks if a filename contains the target phone number or its 10-digit national number. */
    private fun fileNameContainsPhone(fileName: String, targetPhone: String): Boolean {
        val cleanDigits = cleanPhone(targetPhone)
        if (cleanDigits.isEmpty()) return true
        if (cleanDigits.length < 4) return false

        val digitsInFileName = fileName.replace("[^0-9]".toRegex(), "")
        if (digitsInFileName.contains(cleanDigits)) return true

        if (cleanDigits.length >= 10) {
            val last10 = cleanDigits.takeLast(10)
            if (digitsInFileName.contains(last10)) return true
        }

        return false
    }

    private fun matchesCallLogForPhone(fileName: String, effectiveTime: Long, phone: String): Boolean {
        if (phone.isEmpty() || effectiveTime <= 0L) return false
        val cleanDigits = cleanPhone(phone)
        val last10 = if (cleanDigits.length >= 10) cleanDigits.takeLast(10) else cleanDigits
        if (last10.length < 7) return false

        try {
            val projection = arrayOf(CallLog.Calls.DATE, CallLog.Calls.NUMBER)
            val selection = "${CallLog.Calls.NUMBER} LIKE '%$last10%' AND ${CallLog.Calls.DATE} >= ${effectiveTime - 600000} AND ${CallLog.Calls.DATE} <= ${effectiveTime + 600000}"
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                projection,
                selection,
                null,
                "${CallLog.Calls.DATE} DESC"
            )?.use { c ->
                return c.moveToFirst()
            }
        } catch (_: Exception) {}

        return false
    }

    private fun isRecordingForPhone(file: File, phone: String): Boolean {
        if (phone.isEmpty()) return true
        val cleanDigits = cleanPhone(phone)
        if (fileNameContainsPhone(file.name, cleanDigits)) return true

        val timestamp = parseTimestampFromFileName(file.name) ?: file.lastModified()
        if (matchesCallLogForPhone(file.name, timestamp, cleanDigits)) return true

        // Fallback for call recordings from the last 24 hours
        // as long as filename doesn't contain a conflicting phone number of another contact
        val now = System.currentTimeMillis()
        val fileTime = file.lastModified()
        if (abs(now - fileTime) <= 24 * 60 * 60 * 1000L && !containsConflictingPhone(file.name, cleanDigits)) {
            return true
        }

        return false
    }

    /** Score a file based on phone match + time proximity. Higher = better match. */
    private fun scoreFile(fileName: String, effectiveTime: Long, callTimestamp: Long, cleanPhone: String): Int {
        var score = 0
        val phoneMatch = cleanPhone.length >= 2 && fileName.contains(cleanPhone)
        if (phoneMatch) score += 50
        
        if (callTimestamp <= 0L) {
            score += 10
        } else {
            val timeDiffMs = abs(effectiveTime - callTimestamp)
            score += when {
                timeDiffMs < 15 * 1000L -> 50
                timeDiffMs < 45 * 1000L -> 30
                timeDiffMs < 90 * 1000L -> 15
                else -> 5
            }
        }
        return score
    }

    // ─── Main API: find latest recording for a specific call ───────────────────

    suspend fun findLatestSystemRecording(callTimestamp: Long, phoneNumber: String = ""): String? = withContext(Dispatchers.IO) {
        try {
            val appRecordingsDir = File(context.filesDir, "recordings").apply { mkdirs() }
            val phone = cleanPhone(phoneNumber)

            var bestFile: File? = null
            var bestScore = -1
            var bestTime = -1L

            Log.d(TAG, "Scanning for phone=$phone, callTimestamp=$callTimestamp")

            val minTime = if (callTimestamp > 0L) callTimestamp - 10_000L else 0L
            val maxTime = if (callTimestamp > 0L) callTimestamp + MAX_POST_CALL_WINDOW_MS else Long.MAX_VALUE

            // Phase 1: Direct recursive filesystem scan across all known directories
            if (PermissionUtils.hasStoragePermission(context)) {
                for (dir in getCallRecordingDirs()) {
                    if (!dir.exists() || !dir.isDirectory) continue
                    val files = runCatching {
                        dir.walkTopDown().maxDepth(4).filter { isValidRecording(it) }.toList()
                    }.getOrNull() ?: continue

                    for (file in files) {
                        val effectiveTime = parseTimestampFromFileName(file.name) ?: file.lastModified()
                        if (callTimestamp > 0L && (effectiveTime < minTime || effectiveTime > maxTime)) continue
                        if (phone.isNotEmpty() && containsConflictingPhone(file.name, phone)) continue

                        val score = scoreFile(file.name, effectiveTime, callTimestamp, phone)
                        if (score > bestScore || (score == bestScore && effectiveTime > bestTime)) {
                            Log.d(TAG, "Best match: ${file.absolutePath} (score=$score)")
                            bestScore = score; bestFile = file; bestTime = effectiveTime
                        }
                    }
                    if (bestScore >= 50 && dir.name.equals("Call", ignoreCase = true)) break
                }
            }

            // Phase 2: Fallback to MediaStore if no filesystem match
            if (bestFile == null || bestScore < 20) {
                val mediaStoreFile = findViaMediaStore(callTimestamp, phone)
                if (mediaStoreFile != null) {
                    bestFile = mediaStoreFile
                    bestScore = 20 // Ensure it passes the null check below if found via MediaStore
                }
            }

            if (bestScore < 20) bestFile = null
            val foundFile = bestFile ?: return@withContext null
            val timestamp = parseTimestampFromFileName(foundFile.name) ?: foundFile.lastModified()
            val callType = detectCallType(foundFile.absolutePath, foundFile.name, phone, timestamp)
            val directionTag = if (callType == "inbound") "INCOMING" else "OUTGOING"

            val safeName = foundFile.name.replace(Regex("[^a-zA-Z0-9._-]"), "_")
            val destFile = File(appRecordingsDir, "REC_${directionTag}_${foundFile.absolutePath.hashCode()}_$safeName")

            if (destFile.exists() && destFile.length() >= MIN_RECORDING_BYTES) {
                Log.d(TAG, "Already cached: ${destFile.absolutePath}")
                return@withContext destFile.absolutePath
            }

            if (!copyStreamSafely(foundFile, destFile)) {
                Log.e(TAG, "Copy failed: ${foundFile.absolutePath}")
                destFile.delete()
                return@withContext null
            }

            Log.d(TAG, "Copied to ${destFile.absolutePath}")
            destFile.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "Error finding recording", e)
            null
        }
    }

    // ─── MediaStore fallback (finds files even without MANAGE_EXTERNAL_STORAGE) ──

    private fun copyUriToDestFile(uri: Uri, dst: File): Boolean {
        return try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                dst.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            dst.exists() && dst.length() >= MIN_RECORDING_BYTES
        } catch (e: Exception) {
            Log.e(TAG, "Failed copying Uri $uri to $dst", e)
            dst.delete()
            false
        }
    }

    private fun findViaMediaStore(callTimestamp: Long, cleanPhone: String): File? {
        val appRecordingsDir = File(context.filesDir, "recordings").apply { mkdirs() }
        return try {
            val projection = arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.DATA,
                MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.DATE_MODIFIED,
                MediaStore.Audio.Media.SIZE
            )
            val sortOrder = "${MediaStore.Audio.Media.DATE_MODIFIED} DESC"

            val cursor = context.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, projection, null, null, sortOrder
            ) ?: return null

            val minTime = if (callTimestamp > 0L) callTimestamp - 10_000L else 0L
            val maxTime = if (callTimestamp > 0L) callTimestamp + MAX_POST_CALL_WINDOW_MS else Long.MAX_VALUE

            cursor.use { c ->
                val idIdx = c.getColumnIndex(MediaStore.Audio.Media._ID)
                val dataIdx = c.getColumnIndex(MediaStore.Audio.Media.DATA)
                val nameIdx = c.getColumnIndex(MediaStore.Audio.Media.DISPLAY_NAME)
                val sizeIdx = c.getColumnIndex(MediaStore.Audio.Media.SIZE)
                val dateIdx = c.getColumnIndex(MediaStore.Audio.Media.DATE_MODIFIED)

                while (c.moveToNext()) {
                    val id = if (idIdx >= 0) c.getLong(idIdx) else -1L
                    val path = if (dataIdx >= 0) c.getString(dataIdx) else ""
                    val fileName = if (nameIdx >= 0 && c.getString(nameIdx) != null) c.getString(nameIdx) else File(path).name
                    val size = if (sizeIdx >= 0) c.getLong(sizeIdx) else 0L
                    if (size < MIN_RECORDING_BYTES) continue

                    val ext = fileName.substringAfterLast('.', "").lowercase()
                    if (!VALID_EXTENSIONS.contains(ext)) continue

                    val modDateMs = if (dateIdx >= 0) c.getLong(dateIdx) * 1000L else System.currentTimeMillis()
                    val effectiveTime = parseTimestampFromFileName(fileName) ?: modDateMs
                    if (callTimestamp > 0L && (effectiveTime < minTime || effectiveTime > maxTime)) continue
                    if (cleanPhone.isNotEmpty() && containsConflictingPhone(fileName, cleanPhone)) continue

                    val score = scoreFile(fileName, effectiveTime, callTimestamp, cleanPhone)
                    if (score >= 20 || callTimestamp == 0L) {
                        val safeName = fileName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                        val destFile = File(appRecordingsDir, "REC_${id}_$safeName")
                        if (destFile.exists() && destFile.length() >= MIN_RECORDING_BYTES) return destFile
                        if (id > 0) {
                            val contentUri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
                            if (copyUriToDestFile(contentUri, destFile)) return destFile
                        }
                        val f = File(path)
                        if (f.exists() && f.canRead() && copyStreamSafely(f, destFile)) return destFile
                    }
                }
            }
            null
        } catch (e: Exception) {
            Log.e(TAG, "MediaStore query error", e)
            null
        }
    }

    private fun extractCleanOriginalName(fileName: String): String {
        var clean = fileName
        while (clean.startsWith("REC_")) {
            val parts = clean.split("_")
            if (parts.size >= 4 && (parts[1] == "INCOMING" || parts[1] == "OUTGOING")) {
                clean = parts.drop(3).joinToString("_")
            } else if (parts.size >= 3) {
                clean = parts.drop(2).joinToString("_")
            } else {
                clean = clean.substring(4)
            }
        }
        return clean
    }

    // ─── Get all recordings for a phone number ────────────────────────────────

    suspend fun getAllSystemRecordings(phoneNumber: String = ""): List<Map<String, Any>> = withContext(Dispatchers.IO) {
        val appRecordingsDir = File(context.filesDir, "recordings").apply { mkdirs() }
        val phone = cleanPhone(phoneNumber)
        val uniqueRecordingsMap = LinkedHashMap<String, File>() // key (cleanName) -> File

        fun registerFile(file: File) {
            if (!isValidRecording(file)) return
            val cleanName = extractCleanOriginalName(file.name)
            val key = cleanName
            if (!uniqueRecordingsMap.containsKey(key)) {
                uniqueRecordingsMap[key] = file
            }
        }

        // Check app-internal cache
        runCatching {
            appRecordingsDir.listFiles { f ->
                f.isFile && f.name.startsWith("REC_") && (phone.isEmpty() || isRecordingForPhone(f, phone)) && VALID_EXTENSIONS.contains(f.extension.lowercase())
            }?.forEach { registerFile(it) }
        }

        // Scan all known directories recursively
        if (PermissionUtils.hasStoragePermission(context)) {
            for (dir in getCallRecordingDirs()) {
                if (!dir.exists() || !dir.isDirectory) continue
                val files = runCatching {
                    dir.walkTopDown().maxDepth(4).filter { isValidRecording(it) }.toList()
                }.getOrNull() ?: continue

                for (file in files) {
                    if (phone.isNotEmpty() && !isRecordingForPhone(file, phone)) continue
                    if (phone.isNotEmpty() && containsConflictingPhone(file.name, phone)) continue

                    val timestamp = parseTimestampFromFileName(file.name) ?: file.lastModified()
                    val callType = detectCallType(file.absolutePath, file.name, phone, timestamp)
                    val directionTag = if (callType == "inbound") "INCOMING" else "OUTGOING"

                    val cleanName = extractCleanOriginalName(file.name)
                    val safeName = cleanName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                    val destFile = File(appRecordingsDir, "REC_${directionTag}_${cleanName.hashCode()}_$safeName")
                    if (destFile.exists() || copyStreamSafely(file, destFile)) {
                        registerFile(destFile)
                    } else {
                        registerFile(file)
                    }
                }
            }
        }

        // MediaStore fallback (works across all Android OS versions via ContentResolver)
        try {
            val projection = arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.DATA,
                MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.DATE_MODIFIED,
                MediaStore.Audio.Media.SIZE
            )
            context.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, projection, null, null, "${MediaStore.Audio.Media.DATE_MODIFIED} DESC"
            )?.use { c ->
                val idIdx = c.getColumnIndex(MediaStore.Audio.Media._ID)
                val dataIdx = c.getColumnIndex(MediaStore.Audio.Media.DATA)
                val nameIdx = c.getColumnIndex(MediaStore.Audio.Media.DISPLAY_NAME)
                val sizeIdx = c.getColumnIndex(MediaStore.Audio.Media.SIZE)
                val dateIdx = c.getColumnIndex(MediaStore.Audio.Media.DATE_MODIFIED)

                while (c.moveToNext()) {
                    val id = if (idIdx >= 0) c.getLong(idIdx) else -1L
                    val path = if (dataIdx >= 0) c.getString(dataIdx) else ""
                    val fileName = if (nameIdx >= 0 && c.getString(nameIdx) != null) c.getString(nameIdx) else File(path).name
                    val size = if (sizeIdx >= 0) c.getLong(sizeIdx) else 0L
                    if (size < MIN_RECORDING_BYTES) continue

                    val ext = fileName.substringAfterLast('.', "").lowercase()
                    if (!VALID_EXTENSIONS.contains(ext)) continue

                    val modDateMs = if (dateIdx >= 0) c.getLong(dateIdx) * 1000L else System.currentTimeMillis()
                    val effectiveTime = parseTimestampFromFileName(fileName) ?: modDateMs

                    val fileForMatch = File(path)
                    val isMatch = if (fileForMatch.exists() && fileForMatch.canRead()) {
                        isRecordingForPhone(fileForMatch, phone) && !containsConflictingPhone(fileForMatch.name, phone)
                    } else {
                        (phone.isEmpty() || fileNameContainsPhone(fileName, phone) || abs(System.currentTimeMillis() - modDateMs) <= 24 * 60 * 60 * 1000L) &&
                                !containsConflictingPhone(fileName, phone)
                    }

                    if (!isMatch) continue

                    val callType = detectCallType(path, fileName, phone, effectiveTime)
                    val directionTag = if (callType == "inbound") "INCOMING" else "OUTGOING"

                    val cleanName = extractCleanOriginalName(fileName)
                    val safeName = cleanName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                    val destFile = File(appRecordingsDir, "REC_${directionTag}_${cleanName.hashCode()}_$safeName")

                    if (destFile.exists() && destFile.length() >= MIN_RECORDING_BYTES) {
                        registerFile(destFile)
                    } else if (id > 0) {
                        val contentUri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
                        if (copyUriToDestFile(contentUri, destFile)) {
                            registerFile(destFile)
                        }
                    } else if (fileForMatch.exists() && copyStreamSafely(fileForMatch, destFile)) {
                        registerFile(destFile)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "MediaStore query error in getAllSystemRecordings", e)
        }

        // Sort by timestamp descending, extract duration & call type
        uniqueRecordingsMap.values.sortedByDescending { parseTimestampFromFileName(it.name) ?: it.lastModified() }
            .map { file ->
                val path = file.absolutePath
                val timestamp = parseTimestampFromFileName(file.name) ?: file.lastModified()
                val durationMs = try {
                    android.media.MediaMetadataRetriever().use { mmr ->
                        mmr.setDataSource(file.absolutePath)
                        mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                    }
                } catch (_: Exception) { 0L }

                val callType = detectCallType(file.absolutePath, file.name, phone, timestamp)

                mapOf(
                    "path" to path,
                    "timestamp" to timestamp,
                    "durationMs" to durationMs,
                    "callType" to callType
                )
            }
    }

    private fun detectCallType(filePath: String, fileName: String, phone: String, timestamp: Long): String {
        val lowerName = fileName.lowercase()
        val lowerPath = filePath.lowercase()

        // 1. Path & Filename keyword detection (covers Samsung, Xiaomi, OnePlus, Oppo, Vivo, RealMe, Google Dialer, etc.)
        if (lowerPath.contains("inbound") || lowerPath.contains("incoming") || lowerPath.contains("call_in") || lowerPath.contains("rec_in") || lowerPath.contains("call/in") || lowerPath.contains("sound_recorder/call_rec/in") ||
            lowerName.contains("inbound") || lowerName.contains("incoming") || lowerName.contains("_in_") || lowerName.contains("_inc_") ||
            lowerName.contains("callin") || lowerName.contains("recv") || lowerName.contains("received") || lowerName.contains("(in)") ||
            lowerName.startsWith("in_") || lowerName.startsWith("inc_") || lowerName.startsWith("in-") || lowerName.startsWith("inc-") || lowerName.startsWith("1_")) {
            return "inbound"
        }

        if (lowerPath.contains("outbound") || lowerPath.contains("outgoing") || lowerPath.contains("call_out") || lowerPath.contains("rec_out") || lowerPath.contains("call/out") || lowerPath.contains("sound_recorder/call_rec/out") ||
            lowerName.contains("outbound") || lowerName.contains("outgoing") || lowerName.contains("_out_") || lowerName.contains("_outg_") ||
            lowerName.contains("callout") || lowerName.contains("sent") || lowerName.contains("(out)") ||
            lowerName.startsWith("out_") || lowerName.startsWith("outg_") || lowerName.startsWith("out-") || lowerName.startsWith("outg-") || lowerName.startsWith("2_")) {
            return "outbound"
        }

        // 2. Query Android CallLog content provider matching last 10 digits of phone number
        val cleanDigits = cleanPhone(phone)
        val last10 = if (cleanDigits.length >= 10) cleanDigits.takeLast(10) else cleanDigits

        if (last10.length >= 7) {
            try {
                val projection = arrayOf(CallLog.Calls.TYPE, CallLog.Calls.DATE, CallLog.Calls.NUMBER)
                val selection = "${CallLog.Calls.NUMBER} LIKE '%$last10%'"

                context.contentResolver.query(
                    CallLog.Calls.CONTENT_URI,
                    projection,
                    selection,
                    null,
                    "${CallLog.Calls.DATE} DESC"
                )?.use { c ->
                    val typeIdx = c.getColumnIndex(CallLog.Calls.TYPE)
                    val dateIdx = c.getColumnIndex(CallLog.Calls.DATE)

                    var matchedType: Int? = null
                    var firstType: Int? = null
                    var minTimeDiff = Long.MAX_VALUE

                    while (c.moveToNext()) {
                        if (typeIdx < 0 || dateIdx < 0) continue
                        val callType = c.getInt(typeIdx)
                        val callDate = c.getLong(dateIdx)

                        if (firstType == null) {
                            firstType = callType
                        }

                        if (timestamp > 0L) {
                            val diff = abs(callDate - timestamp)
                            if (diff < minTimeDiff && diff <= 30 * 60 * 1000L) { // within 30 minutes
                                minTimeDiff = diff
                                matchedType = callType
                            }
                        }
                    }

                    val finalType = if (timestamp > 0L) matchedType else firstType
                    if (finalType != null) {
                        if (finalType == CallLog.Calls.INCOMING_TYPE || finalType == CallLog.Calls.MISSED_TYPE || finalType == CallLog.Calls.REJECTED_TYPE) {
                            return "inbound"
                        } else if (finalType == CallLog.Calls.OUTGOING_TYPE) {
                            return "outbound"
                        }
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "CallLog query exception: ${e.message}")
            }
        }

        // 3. Fallback: Query general CallLog ordered by date DESC around timestamp
        if (timestamp > 0L) {
            try {
                val projection = arrayOf(CallLog.Calls.TYPE, CallLog.Calls.DATE)
                val selection = "${CallLog.Calls.DATE} >= ${timestamp - 1800000} AND ${CallLog.Calls.DATE} <= ${timestamp + 1800000}"
                context.contentResolver.query(
                    CallLog.Calls.CONTENT_URI,
                    projection,
                    selection,
                    null,
                    "${CallLog.Calls.DATE} DESC"
                )?.use { c ->
                    if (c.moveToFirst()) {
                        val typeIdx = c.getColumnIndex(CallLog.Calls.TYPE)
                        if (typeIdx >= 0) {
                            val type = c.getInt(typeIdx)
                            if (type == CallLog.Calls.INCOMING_TYPE || type == CallLog.Calls.MISSED_TYPE || type == CallLog.Calls.REJECTED_TYPE) {
                                return "inbound"
                            } else if (type == CallLog.Calls.OUTGOING_TYPE) {
                                return "outbound"
                            }
                        }
                    }
                }
            } catch (_: Exception) {}
        }

        return "outbound"
    }

    // ─── Utilities ────────────────────────────────────────────────────────────

    private fun copyStreamSafely(src: File, dst: File): Boolean {
        return try {
            src.inputStream().use { input -> dst.outputStream().use { output -> input.copyTo(output) } }
            if (dst.exists() && dst.length() >= MIN_RECORDING_BYTES && dst.length() == src.length()) {
                dst.setLastModified(src.lastModified()); true
            } else { dst.delete(); false }
        } catch (e: Exception) {
            Log.e(TAG, "Copy failed: ${src.absolutePath}", e)
            dst.delete(); false
        }
    }

    /**
     * Checks if the filename contains digits for a DIFFERENT phone number.
     * If it has a text name like "romi", this returns false (which is good, it allows the match).
     */
    private fun containsConflictingPhone(fileName: String, targetCleanPhone: String): Boolean {
        if (targetCleanPhone.isBlank()) return false
        
        // Remove date/time patterns so they aren't mistaken for phone numbers
        val sanitizedName = fileName
            .replace(Regex("\\d{6}_\\d{6}"), "")
            .replace(Regex("\\d{8}_\\d{6}"), "")
            .replace(Regex("\\b1\\d{12}\\b"), "")

        // Find remaining long number sequences
        val digitChunks = Regex("\\d+").findAll(sanitizedName).map { it.value }.toList()
        for (chunk in digitChunks) {
            // If a long number is in the filename but doesn't match our target phone, it's a conflict!
            if (chunk.length in 2..11) {
                val matchesTarget = targetCleanPhone.contains(chunk) || chunk.contains(targetCleanPhone)
                if (!matchesTarget) return true 
            }
        }
        return false
    }

    /**
     * Extracts exact time from standard OEM call recording filenames.
     * Handles formats like: 260813_151904, 20260813_151904, or 1786614544000
     */
    private fun parseTimestampFromFileName(fileName: String): Long? {
        try {
            // Pattern 1: YYMMDD_HHMMSS
            Regex("(\\d{2})(\\d{2})(\\d{2})_(\\d{2})(\\d{2})(\\d{2})").find(fileName)?.let { match ->
                val (yy, mm, dd, hh, min, ss) = match.destructured
                val cal = Calendar.getInstance()
                cal.set(2000 + yy.toInt(), mm.toInt() - 1, dd.toInt(), hh.toInt(), min.toInt(), ss.toInt())
                cal.set(Calendar.MILLISECOND, 0)
                return cal.timeInMillis
            }

            // Pattern 2: YYYYMMDD_HHMMSS
            Regex("(\\d{4})(\\d{2})(\\d{2})_?(\\d{2})(\\d{2})(\\d{2})").find(fileName)?.let { match ->
                val (yyyy, mm, dd, hh, min, ss) = match.destructured
                val cal = Calendar.getInstance()
                cal.set(yyyy.toInt(), mm.toInt() - 1, dd.toInt(), hh.toInt(), min.toInt(), ss.toInt())
                cal.set(Calendar.MILLISECOND, 0)
                return cal.timeInMillis
            }

            // Pattern 3: Epoch ms
            return Regex("\\b(1\\d{12})\\b").find(fileName)?.value?.toLongOrNull()
        } catch (e: Exception) {
            return null
        }
    }

    private fun calToMillis(y: Int, m: Int, d: Int, h: Int, mi: Int, s: Int): Long {
        val cal = Calendar.getInstance()
        cal.set(y, m - 1, d, h, mi, s)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    fun playRecording(context: Context, path: String) {
        try {
            val file = File(path)
            val uri = androidx.core.content.FileProvider.getUriForFile(
                context, "${context.packageName}.fileprovider", file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "audio/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Error playing recording", e)
        }
    }
}
