package com.example.crm_mobile

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Calendar
import java.util.UUID
import kotlin.math.abs

class CallRecordingManager(private val context: Context) {

    companion object {
        private const val MIN_RECORDING_BYTES = 4 * 1024L  // 4 KB
        private const val MAX_POST_CALL_WINDOW_MS = 3 * 60 * 1000L // 3 minutes
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

    suspend fun findLatestSystemRecording(callTimestamp: Long, phoneNumber: String = ""): String? = withContext(Dispatchers.IO) {
        try {
            val appRecordingsDir = File(context.filesDir, "recordings").apply { mkdirs() }
            val validExtensions = setOf("m4a", "mp3", "aac", "wav", "3gp", "amr")
            val cleanPhone = phoneNumber.replace("[^0-9]".toRegex(), "")

            var bestFile: File? = null
            var bestScore = -1
            var bestEffectiveTime = -1L

            Log.d("CallRecordingSync", "Starting scan for cleanPhone: $cleanPhone, callTimestamp: $callTimestamp")

            val minModTime = if (callTimestamp > 0L) callTimestamp - 10_000L else 0L
            val maxModTime = if (callTimestamp > 0L) callTimestamp + MAX_POST_CALL_WINDOW_MS else Long.MAX_VALUE

            if (PermissionUtils.hasStoragePermission(context)) {
                val primaryCallDirectories = listOf(
                    File(Environment.getExternalStorageDirectory(), "Recordings/Call"),
                    File(Environment.getExternalStorageDirectory(), "Call"),
                    File(Environment.getExternalStorageDirectory(), "MIUI/sound_recorder/call_rec"),
                    File(Environment.getExternalStorageDirectory(), "Recordings/sound_recorder/call_rec"),
                    File(Environment.getExternalStorageDirectory(), "Sounds/Call"),
                    File(Environment.getExternalStorageDirectory(), "Recordings")
                )

                for (dir in primaryCallDirectories) {
                    if (dir.exists() && dir.isDirectory) {
                        val files = runCatching {
                            dir.listFiles { f ->
                                f.isFile && f.length() >= MIN_RECORDING_BYTES && validExtensions.contains(f.extension.lowercase())
                            }
                        }.getOrNull()

                        files?.forEach { file ->
                            Log.d("CallRecordingSync", "Found file: ${file.absolutePath}, canRead: ${file.canRead()}, length: ${file.length()}")
                            if (!file.canRead()) return@forEach
                            val effectiveTime = parseTimestampFromFileName(file.name) ?: file.lastModified()

                            if (callTimestamp > 0L && (effectiveTime < minModTime || effectiveTime > maxModTime)) return@forEach
                            if (containsConflictingPhone(file.name, cleanPhone)) return@forEach

                            val timeDiff = if (callTimestamp > 0L) abs(effectiveTime - callTimestamp) else 0L
                            val nameContainsPhone = cleanPhone.length >= 2 && file.name.contains(cleanPhone)

                            var score = 0
                            if (nameContainsPhone) score += 50
                            when {
                                callTimestamp == 0L -> score += 10
                                timeDiff < 15 * 1000L  -> score += 50
                                timeDiff < 45 * 1000L  -> score += 30
                                timeDiff < 90 * 1000L  -> score += 15
                                else                   -> score += 5
                            }

                            if (score > bestScore || (score == bestScore && effectiveTime > bestEffectiveTime)) {
                                Log.d("CallRecordingSync", "New best file: ${file.name} with score: $score")
                                bestScore = score
                                bestFile = file
                                bestEffectiveTime = effectiveTime
                            }
                        }

                        if (bestScore >= 50 && dir.name.equals("Call", ignoreCase = true)) {
                            break
                        }
                    }
                }
            }

            if (bestFile == null) {
                bestFile = findLatestRecordingViaMediaStore(validExtensions, callTimestamp, cleanPhone)
            }

            val foundFile = bestFile ?: return@withContext null

            val safeName = foundFile.name.replace(Regex("[^a-zA-Z0-9._-]"), "_")
            val destFile = File(appRecordingsDir, "REC_SYS_${UUID.randomUUID().toString().take(8)}_$safeName")
            val copySuccess = copyStreamSafely(foundFile, destFile)

            if (!copySuccess) {
                Log.e("CallRecordingSync", "Could not copy or file invalid: ${foundFile.absolutePath} to ${destFile.absolutePath}. Dest exists: ${destFile.exists()}, length: ${destFile.length()}, src length: ${foundFile.length()}")
                destFile.delete()
                return@withContext null
            }
            
            Log.d("CallRecordingSync", "Successfully copied to ${destFile.absolutePath}")
            destFile.absolutePath
        } catch (e: Exception) {
            Log.e("CallRecordingManager", "Error finding system call recording", e)
            null
        }
    }

    private fun findLatestRecordingViaMediaStore(
        validExtensions: Set<String>,
        callTimestamp: Long = 0L,
        cleanPhone: String = ""
    ): File? {
        return try {
            val projection = arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.DATA,
                MediaStore.Audio.Media.DATE_MODIFIED,
                MediaStore.Audio.Media.SIZE
            )

            val selection = "${MediaStore.Audio.Media.DATA} LIKE '%/Recordings/%' OR ${MediaStore.Audio.Media.DATA} LIKE '%/Call/%'"
            val sortOrder = "${MediaStore.Audio.Media.DATE_MODIFIED} DESC"

            val cursor = context.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                null,
                sortOrder
            ) ?: return null

            val minModTime = if (callTimestamp > 0L) callTimestamp - 10_000L else 0L
            val maxModTime = if (callTimestamp > 0L) callTimestamp + MAX_POST_CALL_WINDOW_MS else Long.MAX_VALUE

            cursor.use { c ->
                val dataIndex = c.getColumnIndex(MediaStore.Audio.Media.DATA)
                val sizeIndex = c.getColumnIndex(MediaStore.Audio.Media.SIZE)
                val dateIndex = c.getColumnIndex(MediaStore.Audio.Media.DATE_MODIFIED)

                while (c.moveToNext()) {
                    val path = c.getString(dataIndex)
                    val size = c.getLong(sizeIndex)
                    val modDateSec = c.getLong(dateIndex)
                    val modDateMs = modDateSec * 1000L

                    if (!path.isNullOrBlank() && size >= MIN_RECORDING_BYTES) {
                        val f = File(path)
                        if (f.exists() && f.canRead() && validExtensions.contains(f.extension.lowercase())) {
                            val effectiveTime = parseTimestampFromFileName(f.name) ?: modDateMs

                            if (callTimestamp > 0L && (effectiveTime < minModTime || effectiveTime > maxModTime)) continue
                            if (containsConflictingPhone(f.name, cleanPhone)) continue

                            val timeDiff = abs(effectiveTime - callTimestamp)
                            val phoneMatch = cleanPhone.length >= 2 && f.name.contains(cleanPhone)
                            if (phoneMatch || timeDiff < MAX_POST_CALL_WINDOW_MS || callTimestamp == 0L) {
                                return f
                            }
                        }
                    }
                }
            }
            null
        } catch (e: Exception) {
            Log.e("CallRecordingManager", "MediaStore query error", e)
            null
        }
    }

    private fun copyStreamSafely(src: File, dst: File): Boolean {
        return try {
            src.inputStream().use { input ->
                dst.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            dst.exists() && dst.length() >= MIN_RECORDING_BYTES && dst.length() == src.length()
        } catch (e: Exception) {
            Log.e("CallRecordingManager", "Failed to stream copy ${src.absolutePath} to ${dst.absolutePath}", e)
            dst.delete()
            false
        }
    }

    private fun containsConflictingPhone(fileName: String, targetCleanPhone: String): Boolean {
        if (targetCleanPhone.isBlank()) return false

        val sanitizedName = fileName
            .replace(Regex("\\d{6}_\\d{6}"), "")
            .replace(Regex("\\d{8}_\\d{6}"), "")
            .replace(Regex("\\b1\\d{12}\\b"), "")

        val digitChunks = Regex("\\d+").findAll(sanitizedName).map { it.value }.toList()
        for (chunk in digitChunks) {
            if (chunk.length in 2..11) {
                val matchesTarget = targetCleanPhone.contains(chunk) || chunk.contains(targetCleanPhone)
                if (!matchesTarget) {
                    return true 
                }
            }
        }
        return false
    }

    private fun parseTimestampFromFileName(fileName: String): Long? {
        try {
            val regexLong = Regex("(20\\d{2})(\\d{2})(\\d{2})_?(\\d{2})(\\d{2})(\\d{2})")
            val matchLong = regexLong.findAll(fileName).lastOrNull()
            if (matchLong != null) {
                val (yyyy, mm, dd, hh, min, ss) = matchLong.destructured
                val cal = Calendar.getInstance()
                cal.set(yyyy.toInt(), mm.toInt() - 1, dd.toInt(), hh.toInt(), min.toInt(), ss.toInt())
                cal.set(Calendar.MILLISECOND, 0)
                return cal.timeInMillis
            }

            val regexShort = Regex("(\\d{2})(\\d{2})(\\d{2})_(\\d{2})(\\d{2})(\\d{2})")
            val matchShort = regexShort.findAll(fileName).lastOrNull()
            if (matchShort != null) {
                val (yy, mm, dd, hh, min, ss) = matchShort.destructured
                val month = mm.toInt()
                val day = dd.toInt()
                val hour = hh.toInt()
                val minute = min.toInt()
                if (month in 1..12 && day in 1..31 && hour in 0..23 && minute in 0..59) {
                    val cal = Calendar.getInstance()
                    val year = 2000 + yy.toInt()
                    cal.set(year, month - 1, day, hour, minute, ss.toInt())
                    cal.set(Calendar.MILLISECOND, 0)
                    return cal.timeInMillis
                }
            }

            val regexEpoch = Regex("\\b(1\\d{12})\\b")
            val matchEpoch = regexEpoch.findAll(fileName).lastOrNull()
            if (matchEpoch != null) {
                return matchEpoch.value.toLongOrNull()
            }
        } catch (e: Exception) {
            // Ignore
        }
        return null
    }

    suspend fun getAllSystemRecordings(phoneNumber: String = ""): List<Map<String, Any>> = withContext(Dispatchers.IO) {
        val appRecordingsDir = File(context.filesDir, "recordings").apply { mkdirs() }
        val validExtensions = setOf("m4a", "mp3", "aac", "wav", "3gp", "amr")
        val cleanPhone = phoneNumber.replace("[^0-9]".toRegex(), "")
        val foundPaths = mutableListOf<String>()

        if (PermissionUtils.hasStoragePermission(context)) {
            val primaryCallDirectories = listOf(
                File(Environment.getExternalStorageDirectory(), "Recordings/Call"),
                File(Environment.getExternalStorageDirectory(), "Call"),
                File(Environment.getExternalStorageDirectory(), "MIUI/sound_recorder/call_rec"),
                File(Environment.getExternalStorageDirectory(), "Recordings/sound_recorder/call_rec"),
                File(Environment.getExternalStorageDirectory(), "Sounds/Call"),
                File(Environment.getExternalStorageDirectory(), "Recordings")
            )
            for (dir in primaryCallDirectories) {
                if (dir.exists() && dir.isDirectory) {
                    val files = runCatching {
                        dir.listFiles { f -> f.isFile && f.length() >= MIN_RECORDING_BYTES && validExtensions.contains(f.extension.lowercase()) }
                    }.getOrNull()
                    files?.forEach { file ->
                        if (!file.canRead()) return@forEach
                        if (containsConflictingPhone(file.name, cleanPhone)) return@forEach
                        
                        val nameContainsPhone = cleanPhone.length >= 2 && file.name.contains(cleanPhone)
                        if (nameContainsPhone) {
                            val safeName = file.name.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                            val destFile = File(appRecordingsDir, "REC_SYS_${file.name.hashCode()}_$safeName")
                            if (copyStreamSafely(file, destFile)) {
                                foundPaths.add(destFile.absolutePath)
                            }
                        }
                    }
                }
            }
        }
        
        try {
            val projection = arrayOf(MediaStore.Audio.Media.DATA, MediaStore.Audio.Media.SIZE)
            val selection = "${MediaStore.Audio.Media.DATA} LIKE '%/Recordings/%' OR ${MediaStore.Audio.Media.DATA} LIKE '%/Call/%'"
            context.contentResolver.query(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, projection, selection, null, null)?.use { c ->
                val dataIndex = c.getColumnIndex(MediaStore.Audio.Media.DATA)
                while (c.moveToNext()) {
                    val path = c.getString(dataIndex)
                    if (!path.isNullOrBlank()) {
                        val f = File(path)
                        if (f.exists() && f.canRead() && validExtensions.contains(f.extension.lowercase())) {
                            if (!containsConflictingPhone(f.name, cleanPhone)) {
                                val nameContainsPhone = cleanPhone.length >= 2 && f.name.contains(cleanPhone)
                                if (nameContainsPhone) {
                                    val safeName = f.name.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                                    val destFile = File(appRecordingsDir, "REC_SYS_${f.name.hashCode()}_$safeName")
                                    if (copyStreamSafely(f, destFile)) {
                                        foundPaths.add(destFile.absolutePath)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {}
        
        val sortedPaths = foundPaths.distinct().sortedByDescending { path ->
            parseTimestampFromFileName(File(path).name) ?: File(path).lastModified()
        }
        
        sortedPaths.map { path ->
            val file = File(path)
            val durationMs = try {
                val mmr = android.media.MediaMetadataRetriever()
                mmr.setDataSource(file.absolutePath)
                val durStr = mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
                mmr.release()
                durStr?.toLongOrNull() ?: 0L
            } catch(e: Exception) { 0L }
            
            mapOf(
                "path" to path,
                "timestamp" to (parseTimestampFromFileName(file.name) ?: file.lastModified()),
                "durationMs" to durationMs
            )
        }
    }

    fun playRecording(context: Context, path: String) {
        try {
            val file = File(path)
            val uri = androidx.core.content.FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "audio/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            Log.e("CallRecordingManager", "Error playing recording", e)
        }
    }
}
