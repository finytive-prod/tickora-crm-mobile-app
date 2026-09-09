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
import java.io.File
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
            "Recordings/sound_recorder/call_rec",        // User device path in screenshot
            "sound_recorder/call_rec",                   // Direct relative path
            "Recordings/Call",                           // Samsung, Pixel, Stock Android
            "Call",                                      // Some Samsung variants
            "CallRecordings",                            // OnePlus, Realme
            "call_recordings",                           // Some third-party dialers
            "MIUI/sound_recorder/call_rec",              // Xiaomi MIUI dialer
            "sound_recorder",                            // Generic sound recorder
            "Recordings/sound_recorder",                 // Sound recorder parent
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

        // 1. If TelephonyManager confirms an active phone call (OFFHOOK / RINGING) and file was modified within 15 minutes:
        if (isCallOngoing() && ageMs <= 15 * 60 * 1000L) {
            Log.d(TAG, "Active call in progress (OFFHOOK/RINGING). Skipping live call recording file ${f.name} until call ends.")
            return true
        }

        // 2. File modification window check for active writes:
        if (ageMs <= 5000L) {
            val len1 = f.length()
            try {
                Thread.sleep(250)
            } catch (_: Exception) {}
            val len2 = f.length()
            if (len1 != len2 || isCallOngoing()) {
                Log.d(TAG, "File ${f.name} is actively growing ($len1 -> $len2 bytes). Live call ongoing, skipping.")
                return true
            }
        }

        return false
    }

    /** Checks if a file is a valid recording candidate. */
    private fun isValidRecording(f: File): Boolean =
        f.isFile && f.canRead() && f.length() >= MIN_RECORDING_BYTES &&
                VALID_EXTENSIONS.contains(f.extension.lowercase()) &&
                !isFileActivelyBeingRecorded(f)

    /** Extracts clean phone digits from a raw phone string. */
    private fun cleanPhone(phone: String): String = phone.replace("[^0-9]".toRegex(), "")

    /** Checks if a filename contains the target phone number or its 10-digit national number. */
    private fun fileNameContainsPhone(fileName: String, targetPhone: String): Boolean {
        val cleanDigits = cleanPhone(targetPhone)
        if (cleanDigits.isEmpty()) return false
        val last10 = if (cleanDigits.length >= 10) cleanDigits.takeLast(10) else cleanDigits
        if (last10.length < 7) return false

        val digitsInFileName = fileName.replace("[^0-9]".toRegex(), "")
        if (digitsInFileName.contains(cleanDigits) || digitsInFileName.contains(last10)) return true

        return false
    }

    private fun matchesCallLogForPhone(fileName: String, effectiveTime: Long, phone: String): Boolean {
        if (phone.isEmpty() || effectiveTime <= 0L) return false
        val cleanDigits = cleanPhone(phone)
        val last10 = if (cleanDigits.length >= 10) cleanDigits.takeLast(10) else cleanDigits
        if (last10.length < 7) return false

        // 1. Reject if filename contains digits for a different phone number
        if (containsConflictingPhone(fileName, cleanDigits)) return false

        try {
            val projection = arrayOf(CallLog.Calls.DATE, CallLog.Calls.DURATION, CallLog.Calls.NUMBER)
            val minDate = effectiveTime - (15 * 60 * 1000L)
            val maxDate = effectiveTime + (15 * 60 * 1000L)
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

                        // 15-minute time window matching (recording created near call time)
                        if (timeDiffMs <= 15 * 60 * 1000L || endDiffMs <= 15 * 60 * 1000L || (effectiveTime in callStart..callEnd)) {
                            return true
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        return false
    }

    private fun isRecordingForPhone(file: File, phone: String, callTimestamp: Long = 0L): Boolean {
        if (phone.isEmpty()) return false
        val cleanDigits = cleanPhone(phone)
        val last10 = if (cleanDigits.length >= 10) cleanDigits.takeLast(10) else cleanDigits
        if (last10.length < 7) return false

        // Reject if filename contains digits for a different phone number
        if (containsConflictingPhone(file.name, cleanDigits)) return false

        // 1. Direct filename match with lead phone number
        if (fileNameContainsPhone(file.name, cleanDigits)) {
            return true
        }

        // 2. CallLog match for this lead's phone number
        val timestamp = parseTimestampFromFileName(file.name) ?: file.lastModified()
        if (matchesCallLogForPhone(file.name, timestamp, cleanDigits)) {
            return true
        }

        // 3. Exact call timestamp window match (within 15 minutes of explicit call)
        if (callTimestamp > 0L) {
            val timeDiffMs = abs(timestamp - callTimestamp)
            if (timeDiffMs <= 15 * 60 * 1000L) {
                return true
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
                timeDiffMs < 30 * 1000L -> 50
                timeDiffMs < 90 * 1000L -> 30
                timeDiffMs < 300 * 1000L -> 15
                else -> 10
            }
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

        // Remove date and time patterns completely before looking for phone numbers
        var sanitizedName = fileName
            .replace(Regex("\\d{14}"), "") // YYYYMMDDHHMMSS
            .replace(Regex("\\d{12}"), "") // YYMMDDHHMMSS
            .replace(Regex("\\d{8}_\\d{6}"), "")
            .replace(Regex("\\d{6}_\\d{6}"), "")
            .replace(Regex("1\\d{12}"), "") // Epoch ms timestamp

        for (pattern in DATE_STRIP_PATTERNS) {
            sanitizedName = sanitizedName.replace(pattern, "")
        }

        // Find remaining phone-length digit sequences (10 to 13 digits)
        val digitChunks = Regex("\\d{10,13}").findAll(sanitizedName).map { it.value }.toList()
        for (chunk in digitChunks) {
            // Ignore timestamps starting with 202, 203, 260, 250, 240, 17, etc.
            if (chunk.startsWith("202") || chunk.startsWith("203") || chunk.startsWith("260") || chunk.startsWith("250") || chunk.startsWith("240") || chunk.startsWith("17")) continue
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
            val appRecordingsDir = File(context.filesDir, "recordings")
            if (appRecordingsDir.exists()) {
                appRecordingsDir.listFiles()?.forEach { it.delete() }
            }
            val cacheRecordingsDir = File(context.cacheDir, "recordings")
            if (cacheRecordingsDir.exists()) {
                cacheRecordingsDir.listFiles()?.forEach { it.delete() }
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

            var bestFile: File? = null
            var bestScore = -1
            var bestTime = -1L

            Log.d(TAG, "Scanning MediaStore for phone=$phone, callTimestamp=$callTimestamp")

            val minTime = if (callTimestamp > 0L) callTimestamp - 300_000L else 0L
            val maxTime = Long.MAX_VALUE

            // Phase 1: MediaStore search as PRIMARY discovery mechanism
            val mediaStoreFile = findViaMediaStore(callTimestamp, phone)
            if (mediaStoreFile != null && mediaStoreFile.exists()) {
                bestFile = mediaStoreFile
                bestTime = parseTimestampFromFileName(mediaStoreFile.name) ?: mediaStoreFile.lastModified()
                bestScore = scoreFile(mediaStoreFile.name, bestTime, callTimestamp, phone)
            }

            // Phase 2: Direct accessible directory check fallback (if accessible)
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
                        if (!isRecordingForPhone(file, phone, callTimestamp)) continue

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
            val callType = detectCallType(foundFile.absolutePath, foundFile.name, phone, bestTime, callTimestamp)
            val directionTag = if (callType == "inbound") "INCOMING" else "OUTGOING"
            val safeName = cleanName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
            val filePrefix = if (phone.isNotEmpty()) "${directionTag}_${phone}_" else "${directionTag}_"

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

    private fun findViaMediaStore(callTimestamp: Long, cleanPhone: String): File? {
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

            val cursor = context.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, projection, null, null, sortOrder
            ) ?: return null

            val minTime = if (callTimestamp > 0L) callTimestamp - 10_000L else 0L
            val maxTime = if (callTimestamp > 0L) callTimestamp + MAX_POST_CALL_WINDOW_MS else Long.MAX_VALUE

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

                    val ext = fileName.substringAfterLast('.', "").lowercase()
                    if (!VALID_EXTENSIONS.contains(ext)) continue

                    val modDateMs = if (dateIdx >= 0) c.getLong(dateIdx) * 1000L else System.currentTimeMillis()
                    val effectiveTime = parseTimestampFromFileName(fileName) ?: modDateMs
                    if (callTimestamp > 0L && (effectiveTime < minTime || effectiveTime > maxTime)) continue
                    if (cleanPhone.isNotEmpty() && containsConflictingPhone(fileName, cleanPhone)) continue

                    val fileForCheck = File(path)
                    if (cleanPhone.isNotEmpty() && !isRecordingForPhone(fileForCheck, cleanPhone, callTimestamp) && !fileNameContainsPhone(fileName, cleanPhone) && !matchesCallLogForPhone(fileName, effectiveTime, cleanPhone)) {
                        continue
                    }

                    val score = scoreFile(fileName, effectiveTime, callTimestamp, cleanPhone)
                    if (score > highestScore || (score == highestScore && effectiveTime > newestTime)) {
                        val directFile = File(path)
                        if (directFile.exists() && directFile.canRead() && isValidRecording(directFile)) {
                            bestCandidateFile = directFile
                            highestScore = score
                            newestTime = effectiveTime
                        } else if (id > 0) {
                            val safeName = fileName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                            val destFile = File(cacheRecordingsDir, "REC_${id}_$safeName")
                            val contentUri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
                            if (copyUriToDestFile(contentUri, destFile)) {
                                bestCandidateFile = destFile
                                highestScore = score
                                newestTime = effectiveTime
                            }
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
        while (clean.startsWith("REC_") || clean.startsWith("INBOUND_") || clean.startsWith("OUTBOUND_") || clean.startsWith("INCOMING_") || clean.startsWith("OUTGOING_")) {
            val parts = clean.split("_")
            if (parts.size >= 3) {
                clean = parts.drop(2).joinToString("_")
            } else if (parts.size >= 2) {
                clean = parts.drop(1).joinToString("_")
            } else {
                break
            }
        }
        return clean
    }

    // ─── Get all recordings for a phone number ────────────────────────────────

    suspend fun getAllSystemRecordings(phoneNumber: String = "", callTimestamp: Long = 0L): List<Map<String, Any>> = withContext(Dispatchers.IO) {
        clearInternalRecordings()
        val phone = cleanPhone(phoneNumber)
        val uniqueRecordingsMap = LinkedHashMap<String, File>() // key (cleanName) -> File

        fun registerFile(file: File) {
            if (!file.exists() || !isValidRecording(file)) return
            val cleanName = extractCleanOriginalName(file.name).lowercase()
            val fileLength = file.length()
            val key = "${cleanName}_$fileLength"

            val isTagged = file.name.contains("INCOMING_") || file.name.contains("OUTGOING_") || file.name.contains("INBOUND_") || file.name.contains("OUTBOUND_")

            if (!uniqueRecordingsMap.containsKey(key) || isTagged) {
                uniqueRecordingsMap[key] = file
            }
        }

        if (phone.isNotEmpty() && callTimestamp > 0L) {
            appOutboundCalls[phone] = callTimestamp
            if (phone.length >= 10) {
                appOutboundCalls[phone.takeLast(10)] = callTimestamp
            }
        }

        // Phase 1: MediaStore query as PRIMARY mechanism
        try {
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
            context.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, projectionList.toTypedArray(), null, null, "${MediaStore.Audio.Media.DATE_MODIFIED} DESC"
            )?.use { c ->
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

                    val ext = fileName.substringAfterLast('.', "").lowercase()
                    if (!VALID_EXTENSIONS.contains(ext)) continue

                    val modDateMs = if (dateIdx >= 0) c.getLong(dateIdx) * 1000L else System.currentTimeMillis()
                    val effectiveTime = parseTimestampFromFileName(fileName) ?: modDateMs

                    val fileForMatch = File(path)
                    val isMatch = if (phone.isEmpty()) {
                        true
                    } else {
                        isRecordingForPhone(fileForMatch, phone, callTimestamp) ||
                        (fileNameContainsPhone(fileName, phone) || matchesCallLogForPhone(fileName, effectiveTime, phone))
                    } && !containsConflictingPhone(fileName, phone)

                    if (!isMatch) continue

                    val callType = detectCallType(fileForMatch.absolutePath, fileName, phone, effectiveTime, callTimestamp)
                    val directionTag = if (callType == "inbound") "INCOMING" else "OUTGOING"
                    val cleanName = extractCleanOriginalName(fileName)
                    val safeName = cleanName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                    val filePrefix = if (phone.isNotEmpty()) "${directionTag}_${phone}_" else "${directionTag}_"

                    val cacheDir = File(context.cacheDir, "recordings").apply { mkdirs() }
                    val destFile = File(cacheDir, "$filePrefix$safeName")
                    if (fileForMatch.exists() && fileForMatch.canRead() && copyStreamSafely(fileForMatch, destFile)) {
                        registerFile(destFile)
                    } else if (id > 0) {
                        val contentUri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
                        if (copyUriToDestFile(contentUri, destFile)) {
                            registerFile(destFile)
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "MediaStore query error in getAllSystemRecordings", e)
        }

        // Phase 2: Direct accessible directory scan fallback (if accessible)
        if (PermissionUtils.hasStoragePermission(context)) {
            for (dir in getCallRecordingDirs()) {
                if (!dir.exists() || !dir.isDirectory) continue
                val files = runCatching {
                    dir.listFiles()?.filter { isValidRecording(it) } ?: emptyList()
                }.getOrNull() ?: continue

                for (file in files) {
                    if (!file.exists()) continue
                    if (phone.isNotEmpty() && !isRecordingForPhone(file, phone, callTimestamp)) continue
                    if (phone.isNotEmpty() && containsConflictingPhone(file.name, phone)) continue

                    val timestamp = parseTimestampFromFileName(file.name) ?: file.lastModified()
                    val callType = detectCallType(file.absolutePath, file.name, phone, timestamp, callTimestamp)
                    val directionTag = if (callType == "inbound") "INCOMING" else "OUTGOING"

                    val cleanName = extractCleanOriginalName(file.name)
                    val safeName = cleanName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                    val filePrefix = if (phone.isNotEmpty()) "${directionTag}_${phone}_" else "${directionTag}_"

                    val cacheDir = File(context.cacheDir, "recordings").apply { mkdirs() }
                    val destFile = File(cacheDir, "$filePrefix$safeName")
                    if (copyStreamSafely(file, destFile)) {
                        registerFile(destFile)
                    } else {
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
                val durationMs = try {
                    android.media.MediaMetadataRetriever().use { mmr ->
                        mmr.setDataSource(file.absolutePath)
                        mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                    }
                } catch (_: Exception) { 0L }

                val callType = detectCallType(file.absolutePath, file.name, phone, timestamp, callTimestamp)

                mapOf(
                    "path" to path,
                    "timestamp" to timestamp,
                    "durationMs" to durationMs,
                    "callType" to callType
                )
            }
    }

    fun detectCallType(filePath: String, fileName: String, phone: String, timestamp: Long, callTimestamp: Long = 0L): String {
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

        if (cleanDigits.isNotEmpty() && callTimestamp > 0L) {
            appOutboundCalls[cleanDigits] = callTimestamp
            if (last10.isNotEmpty()) appOutboundCalls[last10] = callTimestamp
        }

        // 2. Query CallLog (Android OS official record of call direction)
        if (last10.length >= 7 && timestamp > 0L) {
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
                        if (callLast10.length >= 7 && (callLast10 == last10 || cleanNum.contains(last10) || last10.contains(callLast10))) {
                            val callStart = if (dateIdx >= 0) c.getLong(dateIdx) else 0L
                            val callDurSec = if (durIdx >= 0) c.getLong(durIdx) else 0L
                            val callEnd = callStart + (callDurSec * 1000L)
                            val rawType = if (typeIdx >= 0) c.getInt(typeIdx) else CallLog.Calls.INCOMING_TYPE

                            val diffStart = abs(callStart - timestamp)
                            val diffEnd = abs(callEnd - timestamp)
                            val diff = minOf(diffStart, diffEnd)

                            if (diff <= 30 * 60 * 1000L && diff < minDiff) {
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
                        return bestCallType
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "CallLog query error in detectCallType", e)
            }
        }

        // 3. Check app-initiated outbound call tracking (within 10 minutes)
        val appCallTime = if (callTimestamp > 0L) callTimestamp else (if (last10.isNotEmpty()) appOutboundCalls[last10] ?: 0L else 0L)
        if (appCallTime > 0L && timestamp > 0L) {
            val diff = abs(timestamp - appCallTime)
            if (diff <= 10 * 60 * 1000L) {
                Log.d(TAG, "App-initiated call match for $last10 ($diff ms) -> outbound")
                return "outbound"
            }
        }

        // 4. Default fallback when unclassified
        return "inbound"
    }

    // ─── Utilities ────────────────────────────────────────────────────────────

    private fun copyStreamSafely(src: File, dst: File): Boolean {
        return try {
            if (!src.exists()) return false
            src.inputStream().use { input ->
                dst.outputStream().use { output ->
                    input.copyTo(output)
                    output.flush()
                }
            }
            if (dst.exists() && dst.length() >= MIN_RECORDING_BYTES && dst.length() == src.length()) {
                dst.setLastModified(src.lastModified())
                true
            } else {
                dst.delete()
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Copy failed: ${src.absolutePath}", e)
            dst.delete()
            false
        }
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
            audioManager.isSpeakerphoneOn = true
        } catch (e: Exception) {
            Log.e(TAG, "Error forcing loudspeaker", e)
        }
    }

    private var nativeMediaPlayer: android.media.MediaPlayer? = null

    fun startNativeAudio(context: Context, path: String): Map<String, Any> {
        stopNativeAudio()
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            audioManager.mode = android.media.AudioManager.MODE_NORMAL
            audioManager.isSpeakerphoneOn = true

            val currentVol = audioManager.getStreamVolume(android.media.AudioManager.STREAM_MUSIC)
            val maxVol = audioManager.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC)
            if (currentVol == 0) {
                audioManager.setStreamVolume(android.media.AudioManager.STREAM_MUSIC, maxVol / 2, 0)
            }

            val player = android.media.MediaPlayer().apply {
                setAudioAttributes(
                    android.media.AudioAttributes.Builder()
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC)
                        .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                        .build()
                )
                if (path.startsWith("content://")) {
                    setDataSource(context, Uri.parse(path))
                } else {
                    val file = File(path)
                    if (file.exists()) {
                        setDataSource(file.absolutePath)
                    } else {
                        setDataSource(context, Uri.parse(path))
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
            nativeMediaPlayer?.start()
        } catch (_: Exception) {}
    }

    fun stopNativeAudio() {
        try {
            nativeMediaPlayer?.stop()
            nativeMediaPlayer?.release()
        } catch (_: Exception) {}
        nativeMediaPlayer = null
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
}
