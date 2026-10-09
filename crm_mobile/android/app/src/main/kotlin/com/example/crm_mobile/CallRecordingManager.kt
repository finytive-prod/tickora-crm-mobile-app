package com.tickora.crm

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
import android.telephony.TelephonyManager
import android.telephony.SubscriptionManager
import java.io.File
import java.io.FileInputStream
import java.util.Calendar
import kotlin.math.abs

class CallRecordingManager(private val context: Context) {

    companion object {
        private const val TAG = "CallRecordingSync"
        private const val MIN_RECORDING_BYTES = 100L
        private const val MAX_POST_CALL_WINDOW_MS = 3 * 60 * 1000L
        val appOutboundCalls = java.util.concurrent.ConcurrentHashMap<String, Long>()

        // All supported audio formats (covers every known dialer output)
        private val VALID_EXTENSIONS = setOf("m4a", "mp3", "aac", "wav", "3gp", "amr", "opus", "ogg")

        // All known call recording folder paths across phone brands
        private val CALL_RECORDING_DIRS: List<String> = listOf(
            "Recordings/call/2026/09",                    // Explicit year/month recording folder
            "Recordings/call",                           // Year/Month nested recording directory base
            "Recordings/Call",                           // Samsung, Pixel, Stock Android
            "Recordings/sound_recorder/call_rec",        // User device path
            "sound_recorder/call_rec",                   // Direct relative path
            "Call",                                      // Some Samsung variants
            "CallRecordings",                            // OnePlus, Realme
            "call_recordings",                           // Some third-party dialers
            "MIUI/sound_recorder/call_rec",              // Xiaomi MIUI dialer
            "sound_recorder",                            // Generic sound recorder
            "Recordings/sound_recorder",                 // Sound recorder parent
            "Recordings/call_rec",                       // Additional fallback
            "Sounds/Call",                               // Some Samsung variants
            "Record/Call",                               // Oppo, ColorOS
            "Record/PhoneRecord",                        // Oppo variants
            "Music/Recordings/Call Recordings",          // Vivo (Funtouch OS)
            "Music/Recordings/call_rec",                 // Google Dialer variations
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
            Regex("(?:^|[^0-9])20[2-3]\\d[-_./]?(?:0[1-9]|1[0-2])[-_./]?(?:0[1-9]|[12]\\d|3[01])(?:$|[^0-9])"),  // 2026-08-18, 20260818
            Regex("(?:^|[^0-9])20[2-3]\\d(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\\d|3[01])(?:[01]\\d|2[0-3])[0-5]\\d[0-5]\\d(?:$|[^0-9])"), // 20260918150726 (14 digits)
            Regex("(?:^|[^0-9])20[2-3]\\d{10}(?:$|[^0-9])"),                     // 14-digit YYYYMMDD... timestamps
            Regex("(?:^|[^0-9])(?:0[1-9]|[12]\\d|3[01])[-_./](?:0[1-9]|1[0-2])[-_./](?:20[2-3]\\d|\\d{2})(?:$|[^0-9])"), // 18-08-2026, 18_08_26
            Regex("(?:^|[^0-9])(?:[01]\\d|2[0-3])[-_./][0-5]\\d[-_./][0-5]\\d(?:$|[^0-9])"),   // Time patterns: 18-55-30
            Regex("(?:^|[^0-9])1\\d{12}(?:$|[^0-9])"),                         // Epoch ms timestamps
            Regex("(?:^|[^0-9])1[5-9]\\d{8}(?:$|[^0-9])"),                       // 10-digit Epoch seconds timestamps
        )
    }

    fun hasStoragePermission(): Boolean = PermissionUtils.hasStoragePermission(context)

    fun openStoragePermissionSettings(context: Context) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", context.packageName, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        runCatching { context.startActivity(intent) }
    }

    /** Returns the list of directories to scan, resolved recursively to handle nested YYYY/MM folders. */
    private fun getCallRecordingDirs(): List<File> {
        val root = Environment.getExternalStorageDirectory()
        val dirs = mutableSetOf<File>()

        fun addSubDirsRecursively(dir: File, depth: Int = 0) {
            if (depth > 3 || !dir.exists() || !dir.isDirectory) return
            dirs.add(dir)
            try {
                dir.listFiles()?.filter { it.isDirectory }?.forEach { sub ->
                    addSubDirsRecursively(sub, depth + 1)
                }
            } catch (_: Exception) {}
        }

        for (relativePath in CALL_RECORDING_DIRS) {
            val f = File(root, relativePath)
            if (f.exists() && f.isDirectory) {
                addSubDirsRecursively(f)
            }
        }

        val publicNames = listOf(
            Environment.DIRECTORY_RECORDINGS,
            Environment.DIRECTORY_DOWNLOADS,
            Environment.DIRECTORY_MUSIC,
            Environment.DIRECTORY_DOCUMENTS
        )
        for (name in publicNames) {
            val pubDir = Environment.getExternalStoragePublicDirectory(name)
            if (pubDir != null && pubDir.exists() && pubDir.isDirectory) {
                addSubDirsRecursively(pubDir)
            }
        }

        listOf("Recordings", "MIUI", "Call", "sound_recorder", "Record").forEach { folderName ->
            val base = File(root, folderName)
            if (base.exists() && base.isDirectory) {
                addSubDirsRecursively(base)
            }
        }

        dirs.add(root)
        return dirs.toList()
    }

    private fun isCallOngoing(): Boolean {
        return try {
            val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            if (tm != null) {
                val state = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    tm.callState
                } else {
                    @Suppress("DEPRECATION")
                    tm.callState
                }
                state != TelephonyManager.CALL_STATE_IDLE
            } else {
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun isFileActivelyBeingRecorded(f: File): Boolean {
        if (!f.exists()) return false
        val now = System.currentTimeMillis()
        val lastMod = f.lastModified()
        val ageMs = now - lastMod

        // Only check if file is actively growing right now (length increases over 200ms)
        if (ageMs <= 10000L) {
            val len1 = f.length()
            try {
                Thread.sleep(200)
            } catch (_: Exception) {}
            val len2 = f.length()
            if (len2 > len1) {
                Log.d(TAG, "File ${f.name} is actively growing ($len1 -> $len2 bytes). Skipping.")
                return true
            }
        }
        return false
    }

    private fun isValidRecording(f: File): Boolean =
        f.isFile && f.canRead() && f.length() >= MIN_RECORDING_BYTES &&
                getAudioExtension(f.name) != null &&
                !isFileActivelyBeingRecorded(f)

    /** Extracts clean phone digits from a raw phone string. */
    private fun cleanPhone(phone: String): String = phone.replace("[^0-9]".toRegex(), "")

    /** Checks if a filename contains the target phone number or its 10-digit national number. */
    private fun fileNameContainsPhone(fileName: String, targetPhone: String): Boolean {
        val cleanDigits = cleanPhone(targetPhone)
        if (cleanDigits.isEmpty()) return false
        val last10 = if (cleanDigits.length >= 10) cleanDigits.takeLast(10) else cleanDigits
        if (last10.length < 7) return false

        val chunks = Regex("\\d{7,15}").findAll(fileName).map { it.value }.toList()
        for (chunk in chunks) {
            // Skip 14-digit date timestamps like 20260918163153
            if (chunk.length == 14 && chunk.startsWith("202")) continue
            // Skip 13-digit epoch ms timestamps
            if (chunk.length == 13 && chunk.startsWith("1")) continue

            val chunkLast10 = if (chunk.length >= 10) chunk.takeLast(10) else chunk
            if (chunkLast10 == last10 || chunk.contains(last10) || last10.contains(chunkLast10)) {
                return true
            }
        }

        val digitsInFileName = fileName.replace("[^0-9]".toRegex(), "")
        if (digitsInFileName.contains(cleanDigits) || digitsInFileName.contains(last10)) return true

        return false
    }

    data class CachedCallLog(
        val rawNumber: String,
        val cleanNumber: String,
        val last10: String,
        val callStart: Long,
        val callDurSec: Long,
        val callEnd: Long,
        val rawType: Int
    )

    private fun fetchCallLogsCache(minTime: Long = 0L): List<CachedCallLog> {
        val list = mutableListOf<CachedCallLog>()
        try {
            val projection = arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.DATE, CallLog.Calls.DURATION, CallLog.Calls.TYPE)
            val queryMinTime = if (minTime > 0L) minTime - (24 * 60 * 60 * 1000L) else 0L
            val selection = if (queryMinTime > 0L) "${CallLog.Calls.DATE} >= $queryMinTime" else null
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI, projection, selection, null, "${CallLog.Calls.DATE} DESC"
            )?.use { c ->
                val numIdx = c.getColumnIndex(CallLog.Calls.NUMBER)
                val dateIdx = c.getColumnIndex(CallLog.Calls.DATE)
                val durIdx = c.getColumnIndex(CallLog.Calls.DURATION)
                val typeIdx = c.getColumnIndex(CallLog.Calls.TYPE)
                var count = 0
                while (c.moveToNext() && count < 1000) {
                    val rawNum = if (numIdx >= 0) c.getString(numIdx) ?: "" else ""
                    val cleanNum = cleanPhone(rawNum)
                    val last10 = if (cleanNum.length >= 10) cleanNum.takeLast(10) else cleanNum
                    val start = if (dateIdx >= 0) c.getLong(dateIdx) else 0L
                    val durSec = if (durIdx >= 0) c.getLong(durIdx) else 0L
                    val end = start + (durSec * 1000L)
                    val rawType = if (typeIdx >= 0) c.getInt(typeIdx) else CallLog.Calls.INCOMING_TYPE

                    if (last10.isNotEmpty()) {
                        list.add(CachedCallLog(rawNum, cleanNum, last10, start, durSec, end, rawType))
                    }
                    count++
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error fetching call logs cache: ${e.message}")
        }
        return list
    }

    private fun matchesCallLogForPhone(
        fileName: String,
        effectiveTime: Long,
        phone: String,
        cachedLogs: List<CachedCallLog>? = null
    ): Boolean {
        if (phone.isEmpty() || effectiveTime <= 0L) return false
        val cleanDigits = cleanPhone(phone)
        val last10 = if (cleanDigits.length >= 10) cleanDigits.takeLast(10) else cleanDigits
        if (last10.length < 7) return false

        // 1. Reject if filename contains digits for a different phone number
        if (containsConflictingPhone(fileName, cleanDigits)) return false

        val maxMarginMs = 5 * 60 * 1000L

        if (cachedLogs != null) {
            for (entry in cachedLogs) {
                if (entry.last10.length >= 7 && (entry.last10 == last10 || entry.cleanNumber.contains(last10) || last10.contains(entry.last10))) {
                    val timeDiffMs = abs(effectiveTime - entry.callStart)
                    val endDiffMs = abs(effectiveTime - entry.callEnd)
                    if (effectiveTime in (entry.callStart - maxMarginMs)..(entry.callEnd + maxMarginMs) ||
                        timeDiffMs <= maxMarginMs || endDiffMs <= maxMarginMs) {
                        return true
                    }
                }
            }
            return false
        }

        try {
            val projection = arrayOf(CallLog.Calls.DATE, CallLog.Calls.DURATION, CallLog.Calls.NUMBER)
            val minDate = effectiveTime - (60 * 60 * 1000L)
            val maxDate = effectiveTime + (5 * 60 * 1000L)
            val selection = "${CallLog.Calls.DATE} >= $minDate AND ${CallLog.Calls.DATE} <= $maxDate"
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                projection,
                selection,
                null,
                "${CallLog.Calls.DATE} DESC"
            )?.use { c ->
                val dateIdx = c.getColumnIndex(CallLog.Calls.DATE)
                val durIdx = c.getColumnIndex(CallLog.Calls.DURATION)
                val numIdx = c.getColumnIndex(CallLog.Calls.NUMBER)
                while (c.moveToNext()) {
                    val rawNum = if (numIdx >= 0) c.getString(numIdx) ?: "" else ""
                    val cleanCallNum = cleanPhone(rawNum)
                    val callLast10 = if (cleanCallNum.length >= 10) cleanCallNum.takeLast(10) else cleanCallNum

                    if (callLast10.length >= 7 && (callLast10 == last10 || cleanCallNum.contains(last10) || last10.contains(callLast10))) {
                        val callStart = if (dateIdx >= 0) c.getLong(dateIdx) else 0L
                        val callDurSec = if (durIdx >= 0) c.getLong(durIdx) else 0L
                        val callEnd = callStart + (callDurSec * 1000L)

                        val timeDiffMs = abs(effectiveTime - callStart)
                        val endDiffMs = abs(effectiveTime - callEnd)

                        if (effectiveTime in (callStart - maxMarginMs)..(callEnd + maxMarginMs) ||
                            timeDiffMs <= maxMarginMs || endDiffMs <= maxMarginMs) {
                            return true
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        return false
    }

    private fun matchesCallLogForDifferentPhone(
        fileName: String,
        effectiveTime: Long,
        targetCleanPhone: String,
        cachedLogs: List<CachedCallLog>? = null
    ): Boolean {
        if (effectiveTime <= 0L) return false
        val targetLast10 = if (targetCleanPhone.length >= 10) targetCleanPhone.takeLast(10) else targetCleanPhone

        if (cachedLogs != null) {
            for (entry in cachedLogs) {
                if (entry.last10.length >= 7) {
                    val isSamePhone = (entry.last10 == targetLast10 || entry.cleanNumber.contains(targetCleanPhone) || targetLast10.contains(entry.last10))
                    if (!isSamePhone) {
                        if (effectiveTime in (entry.callStart - 5 * 60 * 1000L)..(entry.callEnd + 5 * 60 * 1000L)) {
                            Log.d(TAG, "Recording $fileName at $effectiveTime matches a DIFFERENT phone call log (${entry.rawNumber}), rejecting match for $targetCleanPhone")
                            return true
                        }
                    }
                }
            }
            return false
        }

        try {
            val projection = arrayOf(CallLog.Calls.DATE, CallLog.Calls.DURATION, CallLog.Calls.NUMBER)
            val minDate = effectiveTime - (60 * 60 * 1000L)
            val maxDate = effectiveTime + (5 * 60 * 1000L)
            val selection = "${CallLog.Calls.DATE} >= $minDate AND ${CallLog.Calls.DATE} <= $maxDate"
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                projection,
                selection,
                null,
                "${CallLog.Calls.DATE} DESC"
            )?.use { c ->
                val dateIdx = c.getColumnIndex(CallLog.Calls.DATE)
                val durIdx = c.getColumnIndex(CallLog.Calls.DURATION)
                val numIdx = c.getColumnIndex(CallLog.Calls.NUMBER)
                while (c.moveToNext()) {
                    val rawNum = if (numIdx >= 0) c.getString(numIdx) ?: "" else ""
                    val cleanCallNum = cleanPhone(rawNum)
                    val callLast10 = if (cleanCallNum.length >= 10) cleanCallNum.takeLast(10) else cleanCallNum

                    if (callLast10.length >= 7) {
                        val isSamePhone = (callLast10 == targetLast10 || cleanCallNum.contains(targetLast10) || targetLast10.contains(callLast10))
                        if (!isSamePhone) {
                            val callStart = if (dateIdx >= 0) c.getLong(dateIdx) else 0L
                            val callDurSec = if (durIdx >= 0) c.getLong(durIdx) else 0L
                            val callEnd = callStart + (callDurSec * 1000L)

                            if (effectiveTime in (callStart - 5 * 60 * 1000L)..(callEnd + 5 * 60 * 1000L)) {
                                Log.d(TAG, "Recording $fileName at $effectiveTime matches a DIFFERENT phone call log ($rawNum), rejecting match for $targetCleanPhone")
                                return true
                            }
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        return false
    }

    private fun isRecordingForPhone(
        file: File,
        phone: String,
        callTimestamp: Long = 0L,
        cachedLogs: List<CachedCallLog>? = null
    ): Boolean {
        if (phone.isEmpty()) return false
        val cleanDigits = cleanPhone(phone)
        val last10 = if (cleanDigits.length >= 10) cleanDigits.takeLast(10) else cleanDigits
        if (last10.length < 7) return false

        // 1. Direct filename match with lead phone number (highest confidence)
        if (fileNameContainsPhone(file.name, cleanDigits)) {
            return true
        }

        // Reject if filename contains digits for a different phone number
        if (containsConflictingPhone(file.name, cleanDigits)) return false

        val timestamp = parseTimestampFromFileName(file.name) ?: file.lastModified()

        // Reject if recording matches a call log entry for a DIFFERENT phone number
        if (matchesCallLogForDifferentPhone(file.name, timestamp, cleanDigits, cachedLogs)) {
            return false
        }

        // 2. CallLog match for this lead's phone number
        if (matchesCallLogForPhone(file.name, timestamp, cleanDigits, cachedLogs)) {
            return true
        }

        // 3. Strict call timestamp window match (within 1 minute of explicit call) ONLY if not conflicting with another phone
        if (callTimestamp > 0L) {
            val timeDiffMs = abs(timestamp - callTimestamp)
            if (timeDiffMs <= 60 * 1000L) {
                if (!matchesCallLogForDifferentPhone(file.name, timestamp, cleanDigits, cachedLogs)) {
                    return true
                }
            }
        }

        return false
    }

    /** Score a file based on phone match + time proximity. Higher = better match. */
    private fun scoreFile(fileName: String, effectiveTime: Long, callTimestamp: Long, cleanPhone: String): Int {
        var score = 10
        val targetLast10 = if (cleanPhone.length >= 10) cleanPhone.takeLast(10) else cleanPhone
        val phoneMatch = targetLast10.length >= 7 && fileNameContainsPhone(fileName, targetLast10)
        
        if (phoneMatch) score += 50
        
        if (callTimestamp > 0L) {
            val timeDiffMs = abs(effectiveTime - callTimestamp)
            score += when {
                timeDiffMs < 15 * 1000L -> 100
                timeDiffMs < 35 * 1000L -> 60
                timeDiffMs < 90 * 1000L -> 30
                timeDiffMs < 180 * 1000L -> 10
                else -> -50
            }
            score -= (timeDiffMs / 1000L).toInt()
        }
        return score
    }

    /**
     * Checks if the filename contains digits for a DIFFERENT phone number.
     * If it has a text name like "romi", this returns false (which is good, it allows the match).
     */
    private fun containsConflictingPhone(fileName: String, targetCleanPhone: String): Boolean {
        if (targetCleanPhone.isBlank()) return false
        val targetLast10 = if (targetCleanPhone.length >= 10) targetCleanPhone.takeLast(10) else targetCleanPhone
        if (targetLast10.length < 7) return false

        // If the filename already explicitly contains the target phone, it cannot be a conflict!
        if (fileNameContainsPhone(fileName, targetCleanPhone)) {
            return false
        }

        // Extract all digit sequences attached to pending prefix so they aren't treated as conflicting numbers
        val pendingDigits = Regex("\\.?pending[-_]?(\\d+)", RegexOption.IGNORE_CASE)
            .findAll(fileName)
            .flatMap { listOf(it.groupValues[1], it.value.replace("[^0-9]".toRegex(), "")) }
            .toSet()

        var sanitizedName = extractCleanOriginalName(fileName)
            .replace(Regex("\\.?pending[-_]?[a-zA-Z0-9]*[-_]?", RegexOption.IGNORE_CASE), "")

        for (pattern in DATE_STRIP_PATTERNS) {
            sanitizedName = sanitizedName.replace(pattern, "")
        }

        // Additional date timestamp removals (14-digit YYYYMMDDHHMMSS, 13-digit epoch ms)
        sanitizedName = sanitizedName.replace(Regex("(?:^|[^0-9])20[2-3]\\d{10}(?:$|[^0-9])"), "")
        sanitizedName = sanitizedName.replace(Regex("(?:^|[^0-9])1[6-9]\\d{11,12}(?:$|[^0-9])"), "")

        // Find remaining phone-length digit sequences (10 to 15 digits)
        val digitChunks = Regex("\\d{10,15}").findAll(sanitizedName).map { it.value }.toList()
        for (chunk in digitChunks) {
            if (pendingDigits.contains(chunk)) continue
            // Skip 14-digit date timestamps starting with 202x/203x (e.g. 20260918163153)
            if (chunk.length == 14 && chunk.startsWith("202")) continue
            // Skip 13-digit epoch ms timestamps starting with 1
            if (chunk.length == 13 && chunk.startsWith("1")) continue

            val chunkLast10 = if (chunk.length >= 10) chunk.takeLast(10) else chunk
            val matchesTarget = targetLast10 == chunkLast10 || targetLast10.contains(chunkLast10) || chunkLast10.contains(targetLast10)
            if (!matchesTarget) {
                return true // Conflicting phone number of a different contact found in filename
            }
        }
        return false
    }

    // ─── Main API: find latest recording for a specific call ───────────────────

    private fun clearInternalRecordings() {
        try {
            val now = System.currentTimeMillis()
            val sixHoursMs = 6 * 60 * 60 * 1000L
            val appRecordingsDir = File(context.filesDir, "recordings")
            if (appRecordingsDir.exists()) {
                appRecordingsDir.listFiles()?.forEach { if (now - it.lastModified() > sixHoursMs) it.delete() }
            }
            val cacheRecordingsDir = File(context.cacheDir, "recordings")
            if (cacheRecordingsDir.exists()) {
                cacheRecordingsDir.listFiles()?.forEach { if (now - it.lastModified() > sixHoursMs) it.delete() }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error clearing internal recordings cache", e)
        }
    }

    // ─── Main API: find latest recording for a specific call ───────────────────

    suspend fun findLatestSystemRecording(callTimestamp: Long, phoneNumber: String = ""): String? = withContext(Dispatchers.IO) {
        try {
            clearInternalRecordings()
            val phone = cleanPhone(phoneNumber)
            val minTime = if (callTimestamp > 0L) callTimestamp - (10 * 60 * 1000L) else 0L

            var bestFile: File? = null
            var bestScore = -1
            var bestTime = -1L

            Log.d(TAG, "Scanning MediaStore for phone=$phone, callTimestamp=$callTimestamp")
            val cachedLogs = fetchCallLogsCache(minTime)

            val maxTime = if (callTimestamp > 0L) callTimestamp + (20 * 60 * 1000L) else Long.MAX_VALUE

            // Phase 1: MediaStore search as PRIMARY discovery mechanism (Fast OS Index)
            val mediaStoreFile = findViaMediaStore(callTimestamp, phone, cachedLogs)
            if (mediaStoreFile != null && mediaStoreFile.exists()) {
                bestFile = mediaStoreFile
                bestTime = parseTimestampFromFileName(mediaStoreFile.name) ?: mediaStoreFile.lastModified()
                bestScore = scoreFile(mediaStoreFile.name, bestTime, callTimestamp, phone)

                // Fast Early Return: If strong match found in MediaStore, skip heavy disk folder scanning!
                if (bestScore >= 50) {
                    val cleanName = extractCleanOriginalName(bestFile.name)
                    val safeName = cleanName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                    val filePrefix = if (phone.isNotEmpty()) "${phone}_" else ""
                    val cacheDir = File(context.cacheDir, "recordings").apply { mkdirs() }
                    val destFile = File(cacheDir, "$filePrefix$safeName")
                    if (copyStreamSafely(bestFile, destFile)) {
                        Log.d(TAG, "Fast MediaStore match tagged: ${destFile.absolutePath}")
                        return@withContext destFile.absolutePath
                    }
                    return@withContext bestFile.absolutePath
                }
            }

            // Phase 2: Direct accessible directory check fallback (only if MediaStore did not find score >= 50)
            if ((bestFile == null || bestScore < 10) && PermissionUtils.hasStoragePermission(context)) {
                for (dir in getCallRecordingDirs()) {
                    if (!dir.exists() || !dir.isDirectory) continue
                    val files = runCatching {
                        dir.listFiles()?.filter { isValidRecording(it) } ?: emptyList()
                    }.getOrNull() ?: continue

                    for (file in files) {
                        if (!file.exists()) continue
                        val effectiveTime = parseTimestampFromFileName(file.name) ?: file.lastModified()
                        if (callTimestamp > 0L && (effectiveTime < minTime || effectiveTime > maxTime)) continue
                        if (!isRecordingForPhone(file, phone, callTimestamp, cachedLogs)) continue

                        val score = scoreFile(file.name, effectiveTime, callTimestamp, phone)
                        if (score > bestScore || (score == bestScore && effectiveTime > bestTime)) {
                            Log.d(TAG, "Best match: ${file.absolutePath} (score=$score)")
                            bestScore = score; bestFile = file; bestTime = effectiveTime
                        }
                    }
                    if (bestScore >= 50 && dir.name.equals("Call", ignoreCase = true)) break
                }
            }

            val foundFile = bestFile ?: return@withContext null
            if (!foundFile.exists()) return@withContext null

            val cleanName = extractCleanOriginalName(foundFile.name)
            val safeName = cleanName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
            val filePrefix = if (phone.isNotEmpty()) "${phone}_" else ""

            val cacheDir = File(context.cacheDir, "recordings").apply { mkdirs() }
            val destFile = File(cacheDir, "$filePrefix$safeName")
            if (copyStreamSafely(foundFile, destFile)) {
                Log.d(TAG, "Tagged live recording: ${destFile.absolutePath}")
                return@withContext destFile.absolutePath
            }

            Log.d(TAG, "Returning live system recording: ${foundFile.absolutePath}")
            foundFile.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "Error finding recording", e)
            null
        }
    }

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

    private fun findViaMediaStore(callTimestamp: Long, cleanPhone: String, cachedLogs: List<CachedCallLog>? = null): File? {
        val cacheRecordingsDir = File(context.cacheDir, "recordings").apply { mkdirs() }
        return try {
            val projectionList = mutableListOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.DATA,
                MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.DATE_MODIFIED,
                MediaStore.Audio.Media.SIZE
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                projectionList.add(MediaStore.Audio.Media.RELATIVE_PATH)
            }
            val projection = projectionList.toTypedArray()
            val sortOrder = "${MediaStore.Audio.Media.DATE_MODIFIED} DESC"

            val queryUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.setIncludePending(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI)
            } else {
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            }

            val cursor = context.contentResolver.query(
                queryUri, projection, null, null, sortOrder
            ) ?: return null

            val minTime = if (callTimestamp > 0L) callTimestamp - (10 * 60 * 1000L) else 0L
            val maxTime = if (callTimestamp > 0L) callTimestamp + (20 * 60 * 1000L) else Long.MAX_VALUE
            val logsCache = cachedLogs ?: fetchCallLogsCache(minTime)

            var bestCandidateFile: File? = null
            var highestScore = -1
            var newestTime = -1L

            cursor.use { c ->
                val idIdx = c.getColumnIndex(MediaStore.Audio.Media._ID)
                val dataIdx = c.getColumnIndex(MediaStore.Audio.Media.DATA)
                val nameIdx = c.getColumnIndex(MediaStore.Audio.Media.DISPLAY_NAME)
                val sizeIdx = c.getColumnIndex(MediaStore.Audio.Media.SIZE)
                val dateIdx = c.getColumnIndex(MediaStore.Audio.Media.DATE_MODIFIED)

                while (c.moveToNext()) {
                    val id = if (idIdx >= 0) c.getLong(idIdx) else -1L
                    val path = if (dataIdx >= 0 && c.getString(dataIdx) != null) c.getString(dataIdx) else ""
                    val fileName = if (nameIdx >= 0 && c.getString(nameIdx) != null) c.getString(nameIdx) else File(path).name
                    val size = if (sizeIdx >= 0) c.getLong(sizeIdx) else 0L
                    if (size < MIN_RECORDING_BYTES) continue

                    val audioExt = getAudioExtension(fileName)
                    if (audioExt == null) continue

                    val modDateMs = if (dateIdx >= 0) c.getLong(dateIdx) * 1000L else System.currentTimeMillis()
                    val effectiveTime = parseTimestampFromFileName(fileName) ?: modDateMs
                    if (callTimestamp > 0L && (effectiveTime < minTime || effectiveTime > maxTime)) continue
                    if (cleanPhone.isNotEmpty() && containsConflictingPhone(fileName, cleanPhone)) continue

                    val fileForCheck = File(path)
                    if (cleanPhone.isNotEmpty() && !isRecordingForPhone(fileForCheck, cleanPhone, callTimestamp, logsCache) && !fileNameContainsPhone(fileName, cleanPhone) && !matchesCallLogForPhone(fileName, effectiveTime, cleanPhone, logsCache)) {
                        continue
                    }

                    val score = scoreFile(fileName, effectiveTime, callTimestamp, cleanPhone)
                    if (score > highestScore || (score == highestScore && effectiveTime > newestTime)) {
                        val fileForUse = File(path)
                        val cleanName = extractCleanOriginalName(fileName)
                        val safeName = cleanName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                        val destFile = File(cacheRecordingsDir, "REC_${id}_$safeName")
                        val contentUri = if (id > 0) ContentUris.withAppendedId(queryUri, id) else null

                        if (copyToCache(fileForUse, contentUri, destFile)) {
                            bestCandidateFile = destFile
                            highestScore = score
                            newestTime = effectiveTime
                        } else if (fileForUse.exists() && fileForUse.canRead()) {
                            bestCandidateFile = fileForUse
                            highestScore = score
                            newestTime = effectiveTime
                        }
                    }
                }
            }
            bestCandidateFile
        } catch (e: Exception) {
            Log.e(TAG, "MediaStore query error", e)
            null
        }
    }

    private fun extractCleanOriginalName(fileName: String): String {
        var clean = fileName
        while (true) {
            val old = clean
            // Strip .pending prefix variations
            clean = clean.replace(Regex("^\\.?pending[-_]?[a-zA-Z0-9]*[-_]?", RegexOption.IGNORE_CASE), "")
            clean = clean.replace(Regex("^\\.?pending", RegexOption.IGNORE_CASE), "")
            clean = clean.replace(Regex("^\\.?trashed[-_]?[a-zA-Z0-9]*[-_]?", RegexOption.IGNORE_CASE), "")
            
            while (clean.startsWith(".")) {
                clean = clean.substring(1)
            }
            clean = clean
                .replace(Regex("^REC_\\d+_", RegexOption.IGNORE_CASE), "")
                .replace(Regex("^REC_", RegexOption.IGNORE_CASE), "")
                .replace(Regex("^INBOUND_", RegexOption.IGNORE_CASE), "")
                .replace(Regex("^OUTBOUND_", RegexOption.IGNORE_CASE), "")
                .replace(Regex("^INCOMING_", RegexOption.IGNORE_CASE), "")
                .replace(Regex("^OUTGOING_", RegexOption.IGNORE_CASE), "")
                .replace(Regex("^Call_", RegexOption.IGNORE_CASE), "")
            if (clean == old) break
        }
        if (clean.isBlank()) return fileName
        return clean
    }

    private fun getAudioExtension(fileName: String): String? {
        val cleanName = extractCleanOriginalName(fileName)
        val ext = cleanName.substringAfterLast('.', "").lowercase()
        if (VALID_EXTENSIONS.contains(ext)) return ext
        for (validExt in VALID_EXTENSIONS) {
            if (cleanName.lowercase().contains(".$validExt")) {
                return validExt
            }
        }
        return null
    }

    // ─── Get all recordings for a phone number ────────────────────────────────

    suspend fun getAllSystemRecordings(phoneNumber: String = "", callTimestamp: Long = 0L): List<Map<String, Any>> = withContext(Dispatchers.IO) {
        clearInternalRecordings()
        val phone = cleanPhone(phoneNumber)
        val uniqueRecordingsMap = LinkedHashMap<String, File>() // key (cleanBaseName) -> File
        val fileDurations = HashMap<String, Long>() // file path -> durationMs
        val registeredCleanNames = mutableSetOf<String>()
        val cachedLogs = fetchCallLogsCache(if (callTimestamp > 0L) callTimestamp - (10 * 60 * 1000L) else 0L)

        fun registerFile(file: File, durMs: Long = 0L) {
            if (!file.exists() || !file.isFile || !file.canRead() || file.length() < MIN_RECORDING_BYTES) return
            val fileKey = file.absolutePath

            if (!registeredCleanNames.contains(fileKey)) {
                registeredCleanNames.add(fileKey)
                uniqueRecordingsMap[fileKey] = file
                if (durMs > 0L) {
                    fileDurations[file.absolutePath] = durMs
                }
            }
        }

        // Phase 1: MediaStore query as PRIMARY mechanism
        try {
            val projectionList = mutableListOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.DATA,
                MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.DATE_MODIFIED,
                MediaStore.Audio.Media.SIZE,
                MediaStore.Audio.Media.DURATION
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                projectionList.add(MediaStore.Audio.Media.RELATIVE_PATH)
            }
            val queryUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.setIncludePending(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI)
            } else {
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            }
            context.contentResolver.query(
                queryUri, projectionList.toTypedArray(), null, null, "${MediaStore.Audio.Media.DATE_MODIFIED} DESC"
            )?.use { c ->
                val idIdx = c.getColumnIndex(MediaStore.Audio.Media._ID)
                val dataIdx = c.getColumnIndex(MediaStore.Audio.Media.DATA)
                val nameIdx = c.getColumnIndex(MediaStore.Audio.Media.DISPLAY_NAME)
                val sizeIdx = c.getColumnIndex(MediaStore.Audio.Media.SIZE)
                val dateIdx = c.getColumnIndex(MediaStore.Audio.Media.DATE_MODIFIED)
                val durIdx = c.getColumnIndex(MediaStore.Audio.Media.DURATION)

                while (c.moveToNext()) {
                    val id = if (idIdx >= 0) c.getLong(idIdx) else -1L
                    val path = if (dataIdx >= 0 && c.getString(dataIdx) != null) c.getString(dataIdx) else ""
                    val fileName = if (nameIdx >= 0 && c.getString(nameIdx) != null) c.getString(nameIdx) else File(path).name
                    val size = if (sizeIdx >= 0) c.getLong(sizeIdx) else 0L
                    val mediaStoreDur = if (durIdx >= 0) c.getLong(durIdx) else 0L
                    if (size < MIN_RECORDING_BYTES) continue

                    val audioExt = getAudioExtension(fileName)
                    if (audioExt == null) continue

                    val modDateMs = if (dateIdx >= 0) c.getLong(dateIdx) * 1000L else System.currentTimeMillis()
                    val effectiveTime = parseTimestampFromFileName(fileName) ?: modDateMs

                    val fileForMatch = File(path)
                    val isMatch = if (phone.isEmpty()) {
                        true
                    } else {
                        isRecordingForPhone(fileForMatch, phone, callTimestamp, cachedLogs) ||
                        (fileNameContainsPhone(fileName, phone) || matchesCallLogForPhone(fileName, effectiveTime, phone, cachedLogs))
                    } && !containsConflictingPhone(fileName, phone)

                    if (!isMatch) continue

                    val cleanName = extractCleanOriginalName(fileName)
                    val safeName = cleanName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                    val filePrefix = if (phone.isNotEmpty()) "${phone}_" else ""

                    val cacheDir = File(context.cacheDir, "recordings").apply { mkdirs() }
                    val destFile = File(cacheDir, "$filePrefix$safeName")
                    val contentUri = if (id > 0) ContentUris.withAppendedId(queryUri, id) else null
                    if (copyToCache(fileForMatch, contentUri, destFile)) {
                        registerFile(destFile, mediaStoreDur)
                    } else if (fileForMatch.exists() && fileForMatch.canRead()) {
                        registerFile(fileForMatch, mediaStoreDur)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "MediaStore query error in getAllSystemRecordings", e)
        }

        // Phase 2: Direct accessible directory scan fallback (always scan when permission granted)
        if (PermissionUtils.hasStoragePermission(context)) {
            for (dir in getCallRecordingDirs()) {
                if (!dir.exists() || !dir.isDirectory) continue
                val files = runCatching {
                    dir.listFiles()?.filter { isValidRecording(it) } ?: emptyList()
                }.getOrNull() ?: continue

                for (file in files) {
                    if (!file.exists()) continue
                    if (phone.isNotEmpty() && !isRecordingForPhone(file, phone, callTimestamp, cachedLogs)) continue
                    if (phone.isNotEmpty() && containsConflictingPhone(file.name, phone)) continue

                    val cleanName = extractCleanOriginalName(file.name)
                    val safeName = cleanName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                    val filePrefix = if (phone.isNotEmpty()) "${phone}_" else ""

                    val cacheDir = File(context.cacheDir, "recordings").apply { mkdirs() }
                    val destFile = File(cacheDir, "$filePrefix$safeName")
                    if (copyToCache(file, null, destFile)) {
                        registerFile(destFile)
                    } else if (file.canRead()) {
                        registerFile(file)
                    }
                }
            }
        }

        // Sort by timestamp descending, extract duration & call type
        uniqueRecordingsMap.values.filter { it.exists() }.sortedByDescending { parseTimestampFromFileName(it.name) ?: it.lastModified() }
            .map { file ->
                val path = file.absolutePath
                val timestamp = parseTimestampFromFileName(file.name) ?: file.lastModified()
                val cachedDur = fileDurations[path] ?: 0L
                val durationMs = if (cachedDur > 0L) cachedDur else try {
                    android.media.MediaMetadataRetriever().use { mmr ->
                        mmr.setDataSource(file.absolutePath)
                        mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                    }
                } catch (_: Exception) { 0L }

                val callType = detectCallType(file.absolutePath, file.name, phone, timestamp, callTimestamp, cachedLogs)

                mapOf(
                    "path" to path,
                    "timestamp" to timestamp,
                    "durationMs" to durationMs,
                    "callType" to callType,
                    "fileSize" to file.length()
                )
            }
    }

    fun detectCallType(
        filePath: String,
        fileName: String,
        phone: String,
        timestamp: Long,
        callTimestamp: Long = 0L,
        cachedLogs: List<CachedCallLog>? = null
    ): String {
        val lowerName = fileName.lowercase()

        // 1. Explicit direction keywords check in filename FIRST (highest priority)
        if (lowerName.contains("outgoing") || lowerName.contains("outbound") || lowerName.contains("call_out") || lowerName.contains("_outg_") || lowerName.contains("(out)") || lowerName.contains("sent")) {
            return "outbound"
        }
        if (lowerName.contains("incoming") || lowerName.contains("inbound") || lowerName.contains("call_in") || lowerName.contains("_inc_") || lowerName.contains("(in)") || lowerName.contains("recv") || lowerName.contains("received")) {
            return "inbound"
        }

        val cleanDigits = cleanPhone(phone)
        val last10 = if (cleanDigits.length >= 10) cleanDigits.takeLast(10) else cleanDigits
        val effectiveTime = if (timestamp > 0L) timestamp else (File(filePath).let { if (it.exists()) it.lastModified() else System.currentTimeMillis() })

        // 2. Check explicit appOutboundCalls using normalized phone matching FIRST
        if (last10.isNotEmpty()) {
            for ((key, registeredTs) in appOutboundCalls) {
                val keyClean = cleanPhone(key)
                val keyLast10 = if (keyClean.length >= 10) keyClean.takeLast(10) else keyClean
                if (keyLast10 == last10 || keyClean.contains(last10) || last10.contains(keyLast10)) {
                    val diff = abs(effectiveTime - registeredTs)
                    if (diff <= 300 * 1000L) {
                        Log.d(TAG, "Explicit appOutboundCalls match for $last10 ($diff ms) -> outbound")
                        return "outbound"
                    }
                }
            }
        }

        // 3. Query System CallLog (using cachedLogs if provided)
        if (effectiveTime > 0L) {
            if (cachedLogs != null) {
                var bestCallType: String? = null
                var minDiff = Long.MAX_VALUE
                for (entry in cachedLogs) {
                    val isPhoneMatch = last10.isEmpty() || (entry.last10.length >= 7 && (entry.last10 == last10 || entry.cleanNumber.contains(last10) || last10.contains(entry.last10)))
                    if (isPhoneMatch) {
                        val diffStart = abs(entry.callStart - effectiveTime)
                        val diffEnd = abs(entry.callEnd - effectiveTime)
                        val diff = minOf(diffStart, diffEnd)
                        if (diff <= 300 * 1000L && diff < minDiff) {
                            minDiff = diff
                            bestCallType = if (entry.rawType == CallLog.Calls.OUTGOING_TYPE) "outbound" else "inbound"
                        }
                    }
                }
                if (bestCallType != null) {
                    return bestCallType
                }
            } else {
                try {
                    val projection = arrayOf(CallLog.Calls.TYPE, CallLog.Calls.NUMBER, CallLog.Calls.DATE, CallLog.Calls.DURATION)
                    context.contentResolver.query(
                        CallLog.Calls.CONTENT_URI, projection, null, null, "${CallLog.Calls.DATE} DESC"
                    )?.use { c ->
                        val typeIdx = c.getColumnIndex(CallLog.Calls.TYPE)
                        val numIdx = c.getColumnIndex(CallLog.Calls.NUMBER)
                        val dateIdx = c.getColumnIndex(CallLog.Calls.DATE)
                        val durIdx = c.getColumnIndex(CallLog.Calls.DURATION)

                        var bestCallType: String? = null
                        var minDiff = Long.MAX_VALUE

                        while (c.moveToNext()) {
                            val num = if (numIdx >= 0) c.getString(numIdx) ?: "" else ""
                            val cleanNum = cleanPhone(num)
                            val callLast10 = if (cleanNum.length >= 10) cleanNum.takeLast(10) else cleanNum
                            val isPhoneMatch = last10.isEmpty() || (callLast10.length >= 7 && (callLast10 == last10 || cleanNum.contains(last10) || last10.contains(callLast10)))

                            if (isPhoneMatch) {
                                val callStart = if (dateIdx >= 0) c.getLong(dateIdx) else 0L
                                val callDurSec = if (durIdx >= 0) c.getLong(durIdx) else 0L
                                val callEnd = callStart + (callDurSec * 1000L)
                                val rawType = if (typeIdx >= 0) c.getInt(typeIdx) else CallLog.Calls.INCOMING_TYPE

                                val diffStart = abs(callStart - effectiveTime)
                                val diffEnd = abs(callEnd - effectiveTime)
                                val diff = minOf(diffStart, diffEnd)

                                if (diff <= 300 * 1000L && diff < minDiff) {
                                    minDiff = diff
                                    bestCallType = if (rawType == CallLog.Calls.OUTGOING_TYPE) {
                                        "outbound"
                                    } else {
                                        "inbound"
                                    }
                                }
                            }
                        }
                        if (bestCallType != null) {
                            Log.d(TAG, "CallLog direction match for $last10: $bestCallType (diff=$minDiff ms)")
                            return bestCallType
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "CallLog query error in detectCallType", e)
                }
            }
        }

        // 4. Default fallback: If callTimestamp was explicitly set (>0), this is an outbound lead call
        if (callTimestamp > 0L) {
            Log.d(TAG, "Defaulting to outbound for explicit callTimestamp=$callTimestamp for $last10")
            return "outbound"
        }

        // 5. Default fallback when unclassified (e.g. background scan for incoming calls)
        return "inbound"
    }

    // ─── Utilities ────────────────────────────────────────────────────────────

    private fun copyStreamSafely(src: File, dst: File): Boolean {
        return copyToCache(src, null, dst)
    }

    private fun copyToCache(file: File, uri: Uri?, destFile: File): Boolean {
        val srcTimestamp = parseTimestampFromFileName(file.name) ?: (if (file.exists()) file.lastModified() else System.currentTimeMillis())

        if (destFile.exists() && destFile.length() >= MIN_RECORDING_BYTES) {
            destFile.setLastModified(srcTimestamp)
            return true
        }
        val cacheDir = destFile.parentFile
        if (cacheDir != null && !cacheDir.exists()) {
            cacheDir.mkdirs()
        }

        // Try 1: Copy via ContentResolver Uri if provided
        if (uri != null) {
            try {
                context.contentResolver.openInputStream(uri)?.use { input ->
                    destFile.outputStream().use { output ->
                        input.copyTo(output)
                        output.flush()
                    }
                }
                if (destFile.exists() && destFile.length() >= MIN_RECORDING_BYTES) {
                    destFile.setLastModified(srcTimestamp)
                    Log.d(TAG, "Successfully copied recording via Uri to cache: ${destFile.absolutePath}")
                    return true
                }
            } catch (e: Exception) {
                Log.w(TAG, "Copy via Uri failed for $uri: ${e.message}")
            }
        }

        // Try 2: Copy via File inputStream
        try {
            if (file.exists() && file.canRead()) {
                file.inputStream().use { input ->
                    destFile.outputStream().use { output ->
                        input.copyTo(output)
                        output.flush()
                    }
                }
                if (destFile.exists() && destFile.length() >= MIN_RECORDING_BYTES) {
                    destFile.setLastModified(srcTimestamp)
                    Log.d(TAG, "Successfully copied recording via File to cache: ${destFile.absolutePath}")
                    return true
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Copy via File failed for ${file.absolutePath}: ${e.message}")
        }

        destFile.delete()
        return false
    }

    /**
     * Extracts exact time from standard OEM call recording filenames.
     * Handles formats like: 260813_151904, 20260813_151904, or 1786614544000
     */
    private fun parseTimestampFromFileName(fileName: String): Long? {
        try {
            val cleanName = extractCleanOriginalName(fileName)

            // Pattern 1: YYYYMMDD_HHMMSS or YYYYMMDDHHMMSS (e.g. 20260911_110844, 20260911110844)
            Regex("(?:^|[^0-9])(20[2-3]\\d)[-_]?(\\d{2})[-_]?(\\d{2})[-_._]?(\\d{2})[-_.]?(\\d{2})[-_.]?(\\d{2})(?:$|[^0-9])").find(cleanName)?.let { match ->
                val (yyyy, mm, dd, hh, min, ss) = match.destructured
                val m = mm.toInt()
                val d = dd.toInt()
                val h = hh.toInt()
                val mi = min.toInt()
                val s = ss.toInt()
                if (m in 1..12 && d in 1..31 && h in 0..23 && mi in 0..59 && s in 0..59) {
                    val cal = Calendar.getInstance()
                    cal.set(yyyy.toInt(), m - 1, d, h, mi, s)
                    cal.set(Calendar.MILLISECOND, 0)
                    return cal.timeInMillis
                }
            }

            // Pattern 2: Epoch timestamp (ms or 10-digit seconds)
            Regex("(?:^|[^0-9])(1\\d{12})(?:$|[^0-9])").find(cleanName)?.groupValues?.get(1)?.toLongOrNull()?.let {
                if (it > 1500000000000L && it < 2500000000000L) return it
            }
            Regex("(?:^|[^0-9])(1[5-9]\\d{8})(?:$|[^0-9])").find(cleanName)?.groupValues?.get(1)?.toLongOrNull()?.let {
                val ms = it * 1000L
                if (ms > 1500000000000L && ms < 2500000000000L) return ms
            }

            // Pattern 3: YYMMDD_HHMMSS (e.g. 260911_110844) - Strict boundary & component validation
            Regex("(?:^|[^0-9])(\\d{2})(\\d{2})(\\d{2})[-_]?(\\d{2})(\\d{2})(\\d{2})(?:$|[^0-9])").find(cleanName)?.let { match ->
                val (yy, mm, dd, hh, min, ss) = match.destructured
                val y = 2000 + yy.toInt()
                val m = mm.toInt()
                val d = dd.toInt()
                val h = hh.toInt()
                val mi = min.toInt()
                val s = ss.toInt()
                if (y in 2020..2040 && m in 1..12 && d in 1..31 && h in 0..23 && mi in 0..59 && s in 0..59) {
                    val cal = Calendar.getInstance()
                    cal.set(y, m - 1, d, h, mi, s)
                    cal.set(Calendar.MILLISECOND, 0)
                    return cal.timeInMillis
                }
            }

            return null
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
            forceLoudspeaker(context)
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

    fun forceLoudspeaker(context: Context) {
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            audioManager.mode = android.media.AudioManager.MODE_NORMAL
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = true
            val maxVol = audioManager.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC)
            val currentVol = audioManager.getStreamVolume(android.media.AudioManager.STREAM_MUSIC)
            if (currentVol < maxVol / 2) {
                audioManager.setStreamVolume(android.media.AudioManager.STREAM_MUSIC, (maxVol * 0.85).toInt(), 0)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error forcing loudspeaker", e)
        }
    }

    private var nativeMediaPlayer: android.media.MediaPlayer? = null
    private var nativeFileInputStream: java.io.FileInputStream? = null

    fun startNativeAudio(context: Context, path: String): Map<String, Any> {
        stopNativeAudio()
        try {
            forceLoudspeaker(context)

            val cleanPath = if (path.startsWith("file://")) path.substring(7) else path

            val player = android.media.MediaPlayer().apply {
                setAudioAttributes(
                    android.media.AudioAttributes.Builder()
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC)
                        .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                        .build()
                )
                setVolume(1.0f, 1.0f)
                if (cleanPath.startsWith("content://") || cleanPath.startsWith("http://") || cleanPath.startsWith("https://")) {
                    setDataSource(context, Uri.parse(cleanPath))
                } else {
                    val file = File(cleanPath)
                    if (file.exists()) {
                        try {
                            setDataSource(file.absolutePath)
                        } catch (_: Exception) {
                            val fis = java.io.FileInputStream(file)
                            nativeFileInputStream = fis
                            setDataSource(fis.fd)
                        }
                    } else {
                        setDataSource(cleanPath)
                    }
                }
                prepare()
                start()
            }
            nativeMediaPlayer = player

            return mapOf(
                "success" to true,
                "durationMs" to player.duration
            )
        } catch (e: Exception) {
            Log.e(TAG, "Native audio playback error for path: $path", e)
            return mapOf(
                "success" to false,
                "error" to (e.message ?: "Playback failed")
            )
        }
    }

    fun pauseNativeAudio() {
        try {
            nativeMediaPlayer?.pause()
        } catch (_: Exception) {}
    }

    fun resumeNativeAudio(context: Context) {
        try {
            forceLoudspeaker(context)
            nativeMediaPlayer?.setVolume(1.0f, 1.0f)
            nativeMediaPlayer?.start()
        } catch (_: Exception) {}
    }

    fun stopNativeAudio() {
        try {
            nativeMediaPlayer?.stop()
            nativeMediaPlayer?.release()
        } catch (_: Exception) {}
        nativeMediaPlayer = null

        try {
            nativeFileInputStream?.close()
        } catch (_: Exception) {}
        nativeFileInputStream = null
    }

    fun seekNativeAudio(positionMs: Int) {
        try {
            nativeMediaPlayer?.seekTo(positionMs)
        } catch (_: Exception) {}
    }

    fun getNativeAudioState(): Map<String, Any> {
        val player = nativeMediaPlayer ?: return mapOf("isPlaying" to false, "positionMs" to 0, "durationMs" to 0)
        return try {
            mapOf(
                "isPlaying" to player.isPlaying,
                "positionMs" to player.currentPosition,
                "durationMs" to player.duration
            )
        } catch (_: Exception) {
            mapOf("isPlaying" to false, "positionMs" to 0, "durationMs" to 0)
        }
    }

    fun getLatestCallDetails(phoneNumber: String, callTimestamp: Long): Map<String, Any>? {
        val cleanDigits = cleanPhone(phoneNumber)
        val last10 = if (cleanDigits.length >= 10) cleanDigits.takeLast(10) else cleanDigits
        val searchTime = if (callTimestamp > 0L) callTimestamp else System.currentTimeMillis()
        val devicePhone = getDevicePhoneNumber()

        try {
            val projection = arrayOf(
                CallLog.Calls._ID,
                CallLog.Calls.NUMBER,
                CallLog.Calls.CACHED_NAME,
                CallLog.Calls.TYPE,
                CallLog.Calls.DATE,
                CallLog.Calls.DURATION
            )
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI, projection, null, null, "${CallLog.Calls.DATE} DESC"
            )?.use { c ->
                val numIdx = c.getColumnIndex(CallLog.Calls.NUMBER)
                val nameIdx = c.getColumnIndex(CallLog.Calls.CACHED_NAME)
                val typeIdx = c.getColumnIndex(CallLog.Calls.TYPE)
                val dateIdx = c.getColumnIndex(CallLog.Calls.DATE)
                val durIdx = c.getColumnIndex(CallLog.Calls.DURATION)

                while (c.moveToNext()) {
                    val num = if (numIdx >= 0) c.getString(numIdx) ?: "" else ""
                    val cleanNum = cleanPhone(num)
                    val callLast10 = if (cleanNum.length >= 10) cleanNum.takeLast(10) else cleanNum

                    if (last10.isEmpty() || callLast10 == last10 || cleanNum.contains(last10) || last10.contains(callLast10)) {
                        val startTime = if (dateIdx >= 0) c.getLong(dateIdx) else 0L
                        val durationSec = if (durIdx >= 0) c.getLong(durIdx) else 0L
                        val endTime = startTime + (durationSec * 1000L)
                        val rawType = if (typeIdx >= 0) c.getInt(typeIdx) else CallLog.Calls.OUTGOING_TYPE
                        val isIncoming = rawType == CallLog.Calls.INCOMING_TYPE || rawType == CallLog.Calls.MISSED_TYPE || rawType == CallLog.Calls.REJECTED_TYPE
                        val typeStr = if (isIncoming) "INCOMING" else "OUTGOING"
                        val contactName = if (nameIdx >= 0) c.getString(nameIdx) ?: "" else ""
                        val isMissedOrRejected = rawType == CallLog.Calls.MISSED_TYPE || rawType == CallLog.Calls.REJECTED_TYPE
                        val callStatusStr = when {
                            isMissedOrRejected -> "MISSED"
                            durationSec > 0 -> "ANSWERED"
                            isIncoming -> "MISSED"
                            else -> "NOT_CONNECTED"
                        }
                        val effDurationSec = if (callStatusStr == "MISSED" || callStatusStr == "NOT_CONNECTED") 0L else durationSec

                        val fromNum = if (isIncoming) num else devicePhone
                        val toNum = if (isIncoming) devicePhone else num

                        val maxDiff = 60 * 1000L
                        val diff = abs(startTime - searchTime)
                        if (diff <= maxDiff) {
                            return mapOf(
                                "phoneNumber" to num,
                                "fromNumber" to fromNum,
                                "toNumber" to toNum,
                                "contactName" to contactName,
                                "startTime" to startTime,
                                "endTime" to endTime,
                                "durationSeconds" to effDurationSec,
                                "callType" to typeStr,
                                "callStatus" to callStatusStr
                            )
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error querying system CallLog details", e)
        }
        return null
    }

    fun getSystemCallLogs(phoneNumber: String): List<Map<String, Any>> {
        val cleanDigits = cleanPhone(phoneNumber)
        val last10 = if (cleanDigits.length >= 10) cleanDigits.takeLast(10) else cleanDigits
        val result = mutableListOf<Map<String, Any>>()
        val devicePhone = getDevicePhoneNumber()

        try {
            val projection = arrayOf(
                CallLog.Calls._ID,
                CallLog.Calls.NUMBER,
                CallLog.Calls.CACHED_NAME,
                CallLog.Calls.TYPE,
                CallLog.Calls.DATE,
                CallLog.Calls.DURATION
            )
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI, projection, null, null, "${CallLog.Calls.DATE} DESC"
            )?.use { c ->
                val numIdx = c.getColumnIndex(CallLog.Calls.NUMBER)
                val nameIdx = c.getColumnIndex(CallLog.Calls.CACHED_NAME)
                val typeIdx = c.getColumnIndex(CallLog.Calls.TYPE)
                val dateIdx = c.getColumnIndex(CallLog.Calls.DATE)
                val durIdx = c.getColumnIndex(CallLog.Calls.DURATION)

                while (c.moveToNext()) {
                    val num = if (numIdx >= 0) c.getString(numIdx) ?: "" else ""
                    val cleanNum = cleanPhone(num)
                    val callLast10 = if (cleanNum.length >= 10) cleanNum.takeLast(10) else cleanNum

                    if (last10.isEmpty() || callLast10 == last10 || cleanNum.contains(last10) || last10.contains(callLast10)) {
                        val startTime = if (dateIdx >= 0) c.getLong(dateIdx) else 0L
                        val durationSec = if (durIdx >= 0) c.getLong(durIdx) else 0L
                        val endTime = startTime + (durationSec * 1000L)
                        val rawType = if (typeIdx >= 0) c.getInt(typeIdx) else CallLog.Calls.OUTGOING_TYPE
                        val isIncoming = rawType == CallLog.Calls.INCOMING_TYPE || rawType == CallLog.Calls.MISSED_TYPE || rawType == CallLog.Calls.REJECTED_TYPE
                        val typeStr = if (isIncoming) "INCOMING" else "OUTGOING"
                        val contactName = if (nameIdx >= 0) c.getString(nameIdx) ?: "" else ""
                        val isMissedOrRejected = rawType == CallLog.Calls.MISSED_TYPE || rawType == CallLog.Calls.REJECTED_TYPE
                        val callStatusStr = when {
                            isMissedOrRejected -> "MISSED"
                            durationSec > 0 -> "ANSWERED"
                            isIncoming -> "MISSED"
                            else -> "NOT_CONNECTED"
                        }
                        val effDurationSec = if (callStatusStr == "MISSED" || callStatusStr == "NOT_CONNECTED") 0L else durationSec

                        val fromNum = if (isIncoming) num else devicePhone
                        val toNum = if (isIncoming) devicePhone else num

                        result.add(mapOf(
                            "id" to (if (dateIdx >= 0) c.getLong(dateIdx).toString() else System.currentTimeMillis().toString()),
                            "phoneNumber" to num,
                            "fromNumber" to fromNum,
                            "toNumber" to toNum,
                            "contactName" to contactName,
                            "startTime" to startTime,
                            "endTime" to endTime,
                            "durationSeconds" to effDurationSec,
                            "callType" to typeStr,
                            "callStatus" to callStatusStr
                        ))
                        if (result.size >= 50) break
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error querying system CallLogs", e)
        }
        return result
    }

    /**
     * Tries to get the device's own phone number from SIM / call log.
     * Returns the phone number string, or empty string if unavailable.
     */
    @Suppress("DEPRECATION", "MissingPermission")
    fun getDevicePhoneNumber(): String {
        try {
            // 1. Try TelephonyManager.getLine1Number()
            val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            if (tm != null) {
                try {
                    val line1 = tm.line1Number
                    if (!line1.isNullOrBlank() && line1.length >= 10) {
                        Log.d(TAG, "Got device phone from TelephonyManager: $line1")
                        return cleanPhone(line1)
                    }
                } catch (e: SecurityException) {
                    Log.w(TAG, "SecurityException getting line1Number", e)
                }
            }

            // 2. Try SubscriptionManager (API 22+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                try {
                    val sm = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
                    if (sm != null) {
                        val subList = sm.activeSubscriptionInfoList
                        if (subList != null && subList.isNotEmpty()) {
                            for (sub in subList) {
                                val num = sub.number
                                if (!num.isNullOrBlank() && num.length >= 10) {
                                    Log.d(TAG, "Got device phone from SubscriptionManager: $num")
                                    return cleanPhone(num)
                                }
                            }
                        }
                    }
                } catch (e: SecurityException) {
                    Log.w(TAG, "SecurityException getting subscription info", e)
                }
            }

            // 3. Try PHONE_ACCOUNT_ID from recent call logs (often contains SIM phone number)
            try {
                val projection = arrayOf(
                    "PHONE_ACCOUNT_ID"
                )
                context.contentResolver.query(
                    CallLog.Calls.CONTENT_URI, projection, null, null, "${CallLog.Calls.DATE} DESC"
                )?.use { c ->
                    val accountIdx = c.getColumnIndex("PHONE_ACCOUNT_ID")
                    if (accountIdx >= 0) {
                        val seen = mutableSetOf<String>()
                        var count = 0
                        while (c.moveToNext() && count < 20) {
                            val accountId = c.getString(accountIdx) ?: ""
                            val cleaned = cleanPhone(accountId)
                            if (cleaned.length >= 10 && !seen.contains(cleaned)) {
                                seen.add(cleaned)
                                // Check this looks like a phone number (starts with digit, not a UUID/hash)
                                if (cleaned.all { it.isDigit() }) {
                                    Log.d(TAG, "Got device phone from PHONE_ACCOUNT_ID: $cleaned")
                                    return cleaned
                                }
                            }
                            count++
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error reading PHONE_ACCOUNT_ID from call log", e)
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error getting device phone number", e)
        }
        return ""
    }
}
