import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:crm_mobile/models/lead_audio.dart';
import 'package:crm_mobile/models/lead_call_log.dart';
import 'package:crm_mobile/models/call_history.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/blocs/leads_event.dart';
import 'package:crm_mobile/blocs/leads_state.dart';
import 'package:crm_mobile/core/services/call_recording_service.dart';
import 'package:crm_mobile/core/services/call_history_storage.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_constants.dart';

class LeadCallLogsTab extends StatefulWidget {
  final LeadDetailsLoaded state;

  const LeadCallLogsTab({super.key, required this.state});

  @override
  State<LeadCallLogsTab> createState() => _LeadCallLogsTabState();
}

class _LeadCallLogsTabState extends State<LeadCallLogsTab> {
  final Set<String> _expandedCallLogIds = {};
  bool _localRecordingsFetched = false;
  final Map<String, String> _resolvedCallTypes = {};
  final Set<String> _pendingAsyncResolutions = {};
  final Map<String, int> _resolvedAudioDurations = {};

  @override
  void initState() {
    super.initState();
    _fetchLocalRecordings(widget.state.leadDetail.phone);
  }

  @override
  void didUpdateWidget(covariant LeadCallLogsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.leadDetail.id != oldWidget.state.leadDetail.id) {
      _fetchLocalRecordings(widget.state.leadDetail.phone);
    }
  }

  List<CallHistory> _localTrackedCalls = [];
  List<Map<String, dynamic>> _systemCallLogs = [];

  Future<void> _fetchLocalRecordings(String leadPhone) async {
    try {
      final localHistory = await CallHistoryStorage.loadCallHistory();
      List<Map<String, dynamic>> sysLogs = [];
      if (Platform.isAndroid && leadPhone.isNotEmpty) {
        try {
          sysLogs = await CallRecordingService().getSystemCallLogs(leadPhone);
        } catch (e) {
          debugPrint('Error fetching system call logs: $e');
        }
      }

      if (mounted) {
        setState(() {
          _localTrackedCalls = localHistory;
          _systemCallLogs = sysLogs;
        });
      }
    } catch (e) {
      debugPrint('Error fetching local call history: $e');
    }
  }

  /// Returns true if [audio] represents a real uploaded audio file,
  /// not just a dummy placeholder entry for a missed/unanswered call.
  /// Some backends return size=0 even for valid recordings, so we also
  /// check the fileName to determine if a real file was uploaded.
  bool _audioHasRealFile(LeadAudio audio) {
    if (audio.size > 0) return true;
    final fn = (audio.fileName.isNotEmpty ? audio.fileName : audio.displayName).toLowerCase();
    if (fn == 'missed_call.mp3' || fn.contains('dummy')) return false;
    final cs = (audio.callStatus ?? '').toUpperCase();
    if ((cs == 'MISSED' || cs == 'UNANSWERED' || cs == 'NOT_CONNECTED') && audio.size <= 0) return false;
    return audio.id.isNotEmpty;
  }

  int _parseDurationSeconds(String? durationStr) {
    if (durationStr == null || durationStr.isEmpty) return 0;
    final digits = durationStr.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(digits) ?? 0;
  }

  bool _isMissedLog(LeadCallLog log) {
    final statusUpper = log.callStatus.trim().toUpperCase();
    if (statusUpper == 'MISSED' ||
        statusUpper == 'REJECTED' ||
        statusUpper == 'UNANSWERED' ||
        statusUpper == 'NOT_CONNECTED' ||
        statusUpper == 'NO_ANSWER' ||
        statusUpper == 'CANCELLED' ||
        statusUpper == 'DECLINED' ||
        statusUpper == 'BUSY' ||
        statusUpper == 'FAILED' ||
        statusUpper.contains('MISSED') ||
        statusUpper.contains('UNANSWERED') ||
        statusUpper.contains('NOT_CONNECTED')) {
      return true;
    }
    return false;
  }

  bool _resolveIsIncoming(LeadCallLog log, String leadPhone, LeadAudio? matchedAudio) {
    final statusUpper = log.callStatus.trim().toUpperCase();
    if (statusUpper == 'MISSED') {
      return true;
    }
    final boundUpper = log.bound.trim().toUpperCase();
    if (boundUpper == 'IN' || boundUpper == 'INBOUND' || boundUpper == 'INCOMING' || boundUpper.startsWith('INC') || boundUpper.startsWith('INB')) {
      return true;
    }
    if (boundUpper == 'OUT' || boundUpper == 'OUTBOUND' || boundUpper == 'OUTGOING' || boundUpper.startsWith('OUT')) {
      return false;
    }
    if (matchedAudio != null) {
      final audioType = _getResolvedCallType(matchedAudio, leadPhone).toUpperCase();
      if (audioType == 'OUTBOUND' || audioType == 'OUT' || audioType == 'OUTGOING') return false;
      if (audioType == 'INBOUND' || audioType == 'IN' || audioType == 'INCOMING') return true;
    }
    final cleanLead = leadPhone.replaceAll(RegExp(r'\D'), '');
    final cleanFrom = log.fromNumber.replaceAll(RegExp(r'\D'), '');
    if (cleanLead.isNotEmpty && cleanFrom.isNotEmpty) {
      final leadLast10 = cleanLead.length >= 10 ? cleanLead.substring(cleanLead.length - 10) : cleanLead;
      final fromLast10 = cleanFrom.length >= 10 ? cleanFrom.substring(cleanFrom.length - 10) : cleanFrom;
      if (leadLast10 == fromLast10) {
        return true;
      }
    }
    return false;
  }

  String _getResolvedCallType(LeadAudio audio, String phoneNumber) {
    if (_resolvedCallTypes.containsKey(audio.id)) {
      return _resolvedCallTypes[audio.id]!;
    }

    final nameLower = '${audio.displayName} ${audio.fileName}'.toLowerCase();
    if (nameLower.contains('outgoing') || nameLower.contains('outbound') || nameLower.contains('call_out') || nameLower.contains('_outg_') || nameLower.startsWith('outgoing_') || nameLower.startsWith('outbound_') || nameLower.contains('missed_out')) {
      _resolvedCallTypes[audio.id] = 'outbound';
      return 'outbound';
    }
    if (nameLower.contains('incoming') || nameLower.contains('inbound') || nameLower.contains('call_in') || nameLower.contains('_inc_') || nameLower.startsWith('incoming_') || nameLower.startsWith('inbound_') || nameLower.contains('missed_in')) {
      _resolvedCallTypes[audio.id] = 'inbound';
      return 'inbound';
    }

    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isNotEmpty) {
      final last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;
      final cleanFrom = (audio.fromNumber ?? '').replaceAll(RegExp(r'\D'), '');
      final cleanTo = (audio.toNumber ?? '').replaceAll(RegExp(r'\D'), '');

      final fromMatchesLead = cleanFrom.isNotEmpty && (cleanFrom.endsWith(last10) || last10.contains(cleanFrom));
      final toMatchesLead = cleanTo.isNotEmpty && (cleanTo.endsWith(last10) || last10.contains(cleanTo));

      if (toMatchesLead && !fromMatchesLead) {
        _resolvedCallTypes[audio.id] = 'outbound';
        return 'outbound';
      }
      if (fromMatchesLead && !toMatchesLead) {
        _resolvedCallTypes[audio.id] = 'inbound';
        return 'inbound';
      }
    }

    if (audio.bound != null && audio.bound!.isNotEmpty) {
      final b = audio.bound!.toUpperCase();
      if (b == 'OUT' || b == 'OUTBOUND' || b == 'OUTGOING' || b.startsWith('OUT')) {
        _resolvedCallTypes[audio.id] = 'outbound';
        return 'outbound';
      }
      if (b == 'IN' || b == 'INBOUND' || b == 'INCOMING' || b.startsWith('INC') || b.startsWith('INB')) {
        _resolvedCallTypes[audio.id] = 'inbound';
        return 'inbound';
      }
    }

    if (audio.hasExplicitDirection) {
      final ct = audio.callType.toLowerCase();
      _resolvedCallTypes[audio.id] = ct;
      return ct;
    }

    final timestamp = _getEffectiveTimestamp(audio);
    if (timestamp > 0 && phoneNumber.isNotEmpty && !_pendingAsyncResolutions.contains(audio.id)) {
      _pendingAsyncResolutions.add(audio.id);
      _resolveAudioDirectionFromSystemCallLog(audio, phoneNumber, timestamp);
    }

    return audio.callType.toLowerCase();
  }

  void _resolveAudioDirectionFromSystemCallLog(LeadAudio audio, String phoneNumber, int timestamp) async {
    if (phoneNumber.isEmpty || timestamp <= 0) return;
    try {
      final detected = await CallRecordingService().detectCallType(
        filePath: audio.fileName,
        fileName: audio.displayName,
        phoneNumber: phoneNumber,
        timestamp: timestamp,
      );
      if (mounted && detected.isNotEmpty && _resolvedCallTypes[audio.id] != detected) {
        setState(() {
          _resolvedCallTypes[audio.id] = detected;
        });
      }
    } catch (_) {}
  }

  int _getEffectiveTimestamp(LeadAudio audio) {
    final combined = '${audio.fileName}_${audio.displayName}_${audio.id}';
    
    // 1. Try 13-digit epoch ms timestamp (e.g. 1791016205000)
    final msMatch = RegExp(r'(\d{13})').firstMatch(combined);
    if (msMatch != null) {
      final val = int.tryParse(msMatch.group(1)!);
      if (val != null && val > 1500000000000 && val < 2500000000000) {
        return val;
      }
    }

    // 2. Try 10-digit epoch seconds timestamp (e.g. 1791016205)
    final secMatch = RegExp(r'(?:^|[^0-9])(1[5-9]\d{8})(?:$|[^0-9])').firstMatch(combined);
    if (secMatch != null) {
      final val = int.tryParse(secMatch.group(1)!);
      if (val != null && val > 1500000000 && val < 2500000000) {
        return val * 1000;
      }
    }

    // 3. Try YYYYMMDD_HHMMSS or YYYY-MM-DD_HH-MM-SS pattern
    final dateTimeMatch = RegExp(r'(?:^|[^0-9])(20[2-3]\d)[_\-]?(\d{2})[_\-]?(\d{2})[_\-]?(\d{2})[_\-]?(\d{2})[_\-]?(\d{2})(?:$|[^0-9])').firstMatch(combined);
    if (dateTimeMatch != null) {
      try {
        final y = int.parse(dateTimeMatch.group(1)!);
        final m = int.parse(dateTimeMatch.group(2)!);
        final d = int.parse(dateTimeMatch.group(3)!);
        final h = int.parse(dateTimeMatch.group(4)!);
        final mi = int.parse(dateTimeMatch.group(5)!);
        final s = int.parse(dateTimeMatch.group(6)!);
        if (m >= 1 && m <= 12 && d >= 1 && d <= 31 && h >= 0 && h <= 23 && mi >= 0 && mi <= 59 && s >= 0 && s <= 59) {
          return DateTime(y, m, d, h, mi, s).millisecondsSinceEpoch;
        }
      } catch (_) {}
    }

    // Extract actual call date from audio.callDate or audio.createdAt
    String? resolvedDateStr;
    if (audio.callDate != null && audio.callDate!.isNotEmpty) {
      resolvedDateStr = audio.callDate!.trim();
    } else if (audio.createdAt != null && audio.createdAt!.millisecondsSinceEpoch > 0) {
      resolvedDateStr = DateFormat('yyyy-MM-dd').format(audio.createdAt!.toLocal());
    }

    // 4. Check audio.createdAt if non-midnight
    if (audio.createdAt != null && audio.createdAt!.millisecondsSinceEpoch > 0) {
      final dt = audio.createdAt!.toLocal();
      if (dt.hour != 0 || dt.minute != 0 || dt.second != 0) {
        return dt.millisecondsSinceEpoch;
      }
    }

    // 5. Combine resolvedDateStr with audio.startTimeStr if startTimeStr exists
    if (audio.startTimeStr != null && audio.startTimeStr!.isNotEmpty && audio.startTimeStr != 'null' && audio.startTimeStr != '--:--') {
      final parsed = _parseTimeStringToMs(audio.startTimeStr, resolvedDateStr);
      if (parsed > 0) {
        return parsed;
      }
    }

    // 6. Fallback to createdAt
    if (audio.createdAt != null && audio.createdAt!.millisecondsSinceEpoch > 0) {
      return audio.createdAt!.millisecondsSinceEpoch;
    }

    // 7. Fallback to startTimeStr without known date
    if (audio.startTimeStr != null && audio.startTimeStr!.isNotEmpty) {
      final parsed = _parseTimeStringToMs(audio.startTimeStr);
      if (parsed > 0) return parsed;
    }

    return 0;
  }

  int _parseTimeStringToMs(String? timeStr, [String? knownDateStr]) {
    if (timeStr == null || timeStr.isEmpty || timeStr == 'null' || timeStr == '--:--') return 0;
    String clean = timeStr.trim();
    if (clean.contains(' - ')) {
      clean = clean.split(' - ').first.trim();
    }
    try {
      if (clean.contains('T')) {
        return DateTime.parse(clean).toLocal().millisecondsSinceEpoch;
      }
      var datePart = (knownDateStr != null && knownDateStr.isNotEmpty)
          ? knownDateStr.trim()
          : DateFormat('yyyy-MM-dd').format(DateTime.now());

      if (datePart.toUpperCase() == 'TODAY') {
        datePart = DateFormat('yyyy-MM-dd').format(DateTime.now());
      } else if (datePart.toUpperCase() == 'YESTERDAY') {
        datePart = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));
      }

      final dateFormats = ['yyyy-MM-dd', 'dd-MM-yyyy', 'yyyy/MM/dd', 'dd/MM/yyyy'];
      DateTime? parsedBaseDate;
      for (final df in dateFormats) {
        try {
          parsedBaseDate = DateFormat(df).parse(datePart);
          break;
        } catch (_) {}
      }
      final normalizedDate = parsedBaseDate != null ? DateFormat('yyyy-MM-dd').format(parsedBaseDate) : datePart;

      final timeFormats = [
        'hh:mm:ss a',
        'hh:mm a',
        'HH:mm:ss',
        'HH:mm',
      ];

      for (final tf in timeFormats) {
        try {
          final parsed = DateFormat('yyyy-MM-dd $tf').parse('$normalizedDate $clean');
          return parsed.millisecondsSinceEpoch;
        } catch (_) {}
      }
    } catch (_) {}
    return 0;
  }

  String? _formatTimeString(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty || timeStr == 'null' || timeStr == '--:--') return null;
    String clean = timeStr.trim();
    if (clean.contains(' - ')) {
      final parts = clean.split(' - ').map((e) => e.trim()).toList();
      final start = _formatTimeString(parts.first);
      final end = parts.length > 1 ? _formatTimeString(parts.last) : null;
      if (start != null && end != null && start != end) {
        return '$start - $end';
      }
      clean = parts.first;
    }
    try {
      if (clean.contains('T')) {
        final dt = DateTime.parse(clean).toLocal();
        return DateFormat('hh:mm:ss a').format(dt);
      }
      final now = DateTime.now();
      final datePart = DateFormat('yyyy-MM-dd').format(now);
      if (clean.toUpperCase().contains('AM') || clean.toUpperCase().contains('PM')) {
        final dt = DateFormat('yyyy-MM-dd hh:mm:ss a').parse('$datePart $clean');
        return DateFormat('hh:mm:ss a').format(dt);
      } else {
        final dt = DateFormat('yyyy-MM-dd HH:mm:ss').parse('$datePart $clean');
        return DateFormat('hh:mm:ss a').format(dt);
      }
    } catch (_) {
      try {
        final now = DateTime.now();
        final datePart = DateFormat('yyyy-MM-dd').format(now);
        if (clean.toUpperCase().contains('AM') || clean.toUpperCase().contains('PM')) {
          final dt = DateFormat('yyyy-MM-dd hh:mm a').parse('$datePart $clean');
          return DateFormat('hh:mm:ss a').format(dt);
        } else {
          final dt = DateFormat('yyyy-MM-dd HH:mm').parse('$datePart $clean');
          return DateFormat('hh:mm:ss a').format(dt);
        }
      } catch (_) {}
    }
    return clean;
  }

  String _cleanAudioTitle(String title, {required bool isIncoming, required bool isUnanswered}) {
    if (isUnanswered) {
      return isIncoming ? 'Missed Call' : 'Not Connected Call';
    }
    String cleaned = title.trim();
    if (cleaned.toLowerCase().startsWith('call_recording_')) {
      cleaned = cleaned.substring('call_recording_'.length);
    }
    if (cleaned.toLowerCase().startsWith('recording_')) {
      cleaned = cleaned.substring('recording_'.length);
    }
    final dateMatch = RegExp(r'^\d{4}[-_]\d{2}[-_]\d{2}[-_]?').firstMatch(cleaned);
    if (dateMatch != null) {
      cleaned = cleaned.substring(dateMatch.end);
    }
    final numMatch = RegExp(r'^\d{10,12}_?').firstMatch(cleaned);
    if (numMatch != null) {
      cleaned = cleaned.substring(numMatch.end);
    }
    cleaned = cleaned.replaceAll('_', ' ').replaceAll('-', ' ').trim();
    if (cleaned.isEmpty || cleaned.length < 3) {
      return isIncoming ? 'Incoming Call' : 'Outgoing Call';
    }
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  String _formatDuration(dynamic seconds) {
    if (seconds == null) return '0s';
    final int secs = seconds is int ? seconds : (int.tryParse(seconds.toString()) ?? 0);
    if (secs <= 0) return '0s';
    final duration = Duration(seconds: secs);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final remainingSeconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    }
  }

  DateTime? _parseCallLogDateTime(LeadCallLog log) {
    // 1. Clean startTime
    String cleanTime = log.startTime.trim();
    if (cleanTime.contains(' - ')) {
      cleanTime = cleanTime.split(' - ').first.trim();
    }

    if (cleanTime.contains('T') || RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(cleanTime)) {
      try {
        final parsed = DateTime.parse(cleanTime).toLocal();
        if (parsed.year > 2000) return parsed;
      } catch (_) {}
    }

    // 2. Try combining callDate and cleanTime (actual call occurrence time)
    if (log.callDate.isNotEmpty) {
      var dateStr = log.callDate.trim();
      if (dateStr.toUpperCase() == 'TODAY') {
        dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      } else if (dateStr.toUpperCase() == 'YESTERDAY') {
        dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));
      }

      if (cleanTime.isNotEmpty && cleanTime != '--:--' && cleanTime != 'null') {
        final combined = '$dateStr $cleanTime';
        final formats = [
          'yyyy-MM-dd hh:mm:ss a',
          'yyyy-MM-dd hh:mm a',
          'yyyy-MM-dd HH:mm:ss',
          'yyyy-MM-dd HH:mm',
          'dd-MM-yyyy hh:mm:ss a',
          'dd-MM-yyyy hh:mm a',
          'dd-MM-yyyy HH:mm:ss',
          'dd-MM-yyyy HH:mm',
          'yyyy/MM/dd hh:mm:ss a',
          'yyyy/MM/dd HH:mm:ss',
          'dd/MM/yyyy hh:mm:ss a',
          'dd/MM/yyyy HH:mm:ss',
        ];

        for (final fmt in formats) {
          try {
            final parsed = DateFormat(fmt).parse(combined);
            if (parsed.year > 2000) return parsed;
          } catch (_) {}
        }
      }

      // Try dateStr alone
      try {
        final parsed = DateTime.parse(dateStr).toLocal();
        if (parsed.year > 2000) return parsed;
      } catch (_) {}
      try {
        final parsed = DateFormat('yyyy-MM-dd').parse(dateStr);
        if (parsed.year > 2000) return parsed;
      } catch (_) {}
      try {
        final parsed = DateFormat('dd-MM-yyyy').parse(dateStr);
        if (parsed.year > 2000) return parsed;
      } catch (_) {}
    }

    // 3. Fallback to ISO createdAt if startTime & callDate are absent
    if (log.createdAt.isNotEmpty) {
      try {
        final parsed = DateTime.parse(log.createdAt).toLocal();
        if (parsed.year > 2000) return parsed;
      } catch (_) {}
    }

    return null;
  }

  DateTime _getCallLogTimestamp(LeadCallLog log, LeadAudio? matchedAudio) {
    if (matchedAudio != null) {
      final audioMs = _getEffectiveTimestamp(matchedAudio);
      if (audioMs > 0) {
        return DateTime.fromMillisecondsSinceEpoch(audioMs);
      }
    }
    final parsed = _parseCallLogDateTime(log);
    if (parsed != null) return parsed;
    return DateTime.now();
  }

  int _parseDurationStringToSeconds(String? durStr) {
    if (durStr == null || durStr.isEmpty || durStr == 'null' || durStr == '--:--' || durStr == '0s' || durStr == '0') {
      return 0;
    }
    final clean = durStr.trim();

    // Check hh:mm:ss or mm:ss format (e.g. "00:01:15" -> 75s, "01:15" -> 75s, "00:00:11" -> 11s)
    if (clean.contains(':')) {
      final parts = clean.split(':').map((e) => int.tryParse(e.replaceAll(RegExp(r'[^\d]'), '')) ?? 0).toList();
      if (parts.length == 3) {
        return parts[0] * 3600 + parts[1] * 60 + parts[2];
      } else if (parts.length == 2) {
        return parts[0] * 60 + parts[1];
      }
    }

    // Single number or "15s" format
    final cleanDigits = clean.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(cleanDigits) ?? 0;
  }

  int _resolveTrueDurationSeconds({
    required LeadAudio? audio,
    required LeadCallLog log,
  }) {
    // 1. Check cached duration from actual played audio file (exact match)
    if (audio != null && _resolvedAudioDurations.containsKey(audio.id)) {
      final cached = _resolvedAudioDurations[audio.id];
      if (cached != null && cached > 0) return cached;
    }

    // 2. Check audio.durationSeconds if > 0
    if (audio != null && audio.durationSeconds > 0) {
      return audio.durationSeconds;
    }

    // 3. Check log.duration if > 0
    final logSec = _parseDurationStringToSeconds(log.duration);
    if (logSec > 0) {
      return logSec;
    }

    // 4. Try start/end time difference from audio (only if non-midnight)
    if (audio != null &&
        audio.startTimeStr != null &&
        audio.startTimeStr!.isNotEmpty &&
        audio.endTimeStr != null &&
        audio.endTimeStr!.isNotEmpty &&
        audio.startTimeStr != 'null' &&
        audio.endTimeStr != 'null' &&
        audio.startTimeStr != '--:--' &&
        audio.endTimeStr != '--:--' &&
        audio.startTimeStr != '00:00:00' &&
        audio.startTimeStr != '12:00:00 AM') {
      final startMs = _parseTimeStringToMs(audio.startTimeStr);
      final endMs = _parseTimeStringToMs(audio.endTimeStr);
      if (startMs > 0 && endMs > startMs) {
        final diffSec = ((endMs - startMs) / 1000).round();
        if (diffSec > 0) return diffSec;
      }
    }

    // 5. Try start/end time difference from call log (only if non-midnight)
    if (log.startTime.isNotEmpty &&
        log.endTime.isNotEmpty &&
        log.startTime != '--:--' &&
        log.endTime != '--:--' &&
        log.startTime != '00:00:00' &&
        log.startTime != '12:00:00 AM') {
      final startMs = _parseTimeStringToMs(log.startTime);
      final endMs = _parseTimeStringToMs(log.endTime);
      if (startMs > 0 && endMs > startMs) {
        final diffSec = ((endMs - startMs) / 1000).round();
        if (diffSec > 0) return diffSec;
      }
    }

    // 6. Estimate from audio file size (~8 KB/s for compressed mono mobile recordings)
    if (audio != null && audio.size > 1000) {
      final estSec = (audio.size / 8192).round();
      if (estSec > 0) return estSec;
    }

    return 0;
  }

  _CallCardData _buildCallCardDataFromLog(LeadCallLog log, LeadAudio? matchedAudio, String leadPhone) {
    bool isMissed = _isMissedLog(log);
    if (matchedAudio != null && _audioHasRealFile(matchedAudio)) {
      isMissed = false;
    }
    final isIncoming = _resolveIsIncoming(log, leadPhone, matchedAudio);
    
    final logDt = _parseCallLogDateTime(log);
    String dateStr = log.callDate;
    if (logDt != null) {
      dateStr = DateFormat('MMM dd, yyyy').format(logDt);
    }

    final audioMs = matchedAudio != null ? _getEffectiveTimestamp(matchedAudio) : 0;

    DateTime logTimestamp = logDt ?? DateTime.now();
    if (matchedAudio != null && audioMs > 0) {
      logTimestamp = DateTime.fromMillisecondsSinceEpoch(audioMs);
    } else if (logDt == null || (logDt.hour == 0 && logDt.minute == 0 && logDt.second == 0)) {
      if (audioMs > 0) {
        logTimestamp = DateTime.fromMillisecondsSinceEpoch(audioMs);
      }
    }

    final trueDurSec = isMissed ? 0 : _resolveTrueDurationSeconds(audio: matchedAudio, log: log);
    String durStr = isMissed ? '' : (trueDurSec > 0 ? _formatDuration(trueDurSec) : log.duration);

    String displayStartTime = _formatTimeString(log.startTime) ?? '--:--';
    String displayEndTime = _formatTimeString(log.endTime) ?? '--:--';

    if (matchedAudio != null) {
      if (matchedAudio.startTimeStr != null &&
          matchedAudio.startTimeStr!.isNotEmpty &&
          matchedAudio.startTimeStr != 'null' &&
          matchedAudio.startTimeStr != '--:--' &&
          matchedAudio.startTimeStr != '00:00:00') {
        final formatted = _formatTimeString(matchedAudio.startTimeStr);
        if (formatted != null && formatted.isNotEmpty && !formatted.startsWith('12:00:00 AM')) {
          displayStartTime = formatted;
        }
      }
      if (matchedAudio.endTimeStr != null &&
          matchedAudio.endTimeStr!.isNotEmpty &&
          matchedAudio.endTimeStr != 'null' &&
          matchedAudio.endTimeStr != '--:--' &&
          matchedAudio.endTimeStr != '00:00:00') {
        final formatted = _formatTimeString(matchedAudio.endTimeStr);
        if (formatted != null && formatted.isNotEmpty && !formatted.startsWith('12:00:00 AM')) {
          displayEndTime = formatted;
        }
      }
    }

    if (!isMissed) {
      DateTime startDt = (logDt != null && !(logDt.hour == 0 && logDt.minute == 0 && logDt.second == 0))
          ? logDt
          : (audioMs > 0 ? DateTime.fromMillisecondsSinceEpoch(audioMs) : (logDt ?? DateTime.now()));

      if ((startDt.hour == 0 && startDt.minute == 0 && startDt.second == 0) && audioMs > 0) {
        startDt = DateTime.fromMillisecondsSinceEpoch(audioMs);
      }

      if (audioMs > 0 || !(startDt.hour == 0 && startDt.minute == 0 && startDt.second == 0)) {
        displayStartTime = DateFormat('hh:mm:ss a').format(startDt);
        final endDt = startDt.add(Duration(seconds: trueDurSec > 0 ? trueDurSec : 1));
        displayEndTime = DateFormat('hh:mm:ss a').format(endDt);
      }
    }

    String sizeStr = 'No Audio';
    if (!isMissed && matchedAudio != null && matchedAudio.size > 0) {
      final kb = matchedAudio.size / 1024;
      final mb = kb / 1024;
      sizeStr = mb >= 1 ? '${mb.toStringAsFixed(1)} MB' : '${kb.toStringAsFixed(0)} KB';
    }

    final title = isMissed 
        ? (isIncoming ? 'Missed Call' : 'Not Connected Call')
        : (matchedAudio != null ? _cleanAudioTitle(matchedAudio.displayName, isIncoming: isIncoming, isUnanswered: isMissed) : (isIncoming ? 'Incoming Call' : 'Outgoing Call'));

    return _CallCardData(
      audio: (matchedAudio != null && _audioHasRealFile(matchedAudio)) ? matchedAudio : null,
      timestamp: logTimestamp,
      isIncoming: isIncoming,
      isUnanswered: isMissed,
      title: title,
      fromPhone: log.fromNumber.isNotEmpty ? log.fromNumber : (isIncoming ? leadPhone : 'Me'),
      toPhone: log.toNumber.isNotEmpty ? log.toNumber : (isIncoming ? 'Me' : leadPhone),
      startTimeStr: displayStartTime,
      endTimeStr: displayEndTime,
      durationStr: durStr,
      sizeStr: sizeStr,
      dateStr: dateStr,
    );
  }

  String _getRelativeDateHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final itemDate = DateTime(dt.year, dt.month, dt.day);

    if (itemDate == today) {
      return 'Today';
    } else if (itemDate == yesterday) {
      return 'Yesterday';
    } else if (today.difference(itemDate).inDays < 7 && today.difference(itemDate).inDays > 0) {
      return DateFormat('EEEE').format(dt);
    } else {
      return DateFormat('MMM dd, yyyy').format(dt);
    }
  }

  String _formatCallLogDisplayTime(LeadCallLog log, [DateTime? overrideDt]) {
    final parsedDt = overrideDt ?? _parseCallLogDateTime(log);
    if (parsedDt != null) {
      final relHeader = _getRelativeDateHeader(parsedDt);
      final timeStr = DateFormat('hh:mm a').format(parsedDt);
      return '$relHeader • $timeStr';
    }
    return log.callDate.isNotEmpty ? log.callDate : 'Unknown Date';
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (!_localRecordingsFetched) {
      _localRecordingsFetched = true;
      _fetchLocalRecordings(state.leadDetail.phone);
    }

    if (state.callLogs == null && state.isCallLogsLoading) {
      return const Center(child: SpinningLogo(size: 40));
    }

    if (state.callLogsError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Failed to load call logs', style: TextStyle(color: AppColors.primary)),
            TextButton(
              onPressed: () {
                context.read<LeadsBloc>().add(FetchLeadCallLogs(state.leadDetail.id));
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final callLogs = state.callLogs!;
    final List<LeadCallLog> rawServerHistory = List.from(callLogs.callHistory);

    // Merge server audio recordings (both connected & missed/unanswered) that don't have a matching server call log
    if (state.audios != null && state.audios!.isNotEmpty) {
      for (final audio in state.audios!) {
        bool matchesExistingServerLog = false;
        final audioMs = _getEffectiveTimestamp(audio);

        for (final log in rawServerHistory) {
          if (log.id == audio.id || log.id == 'audio_connected_${audio.id}' || log.id == 'audio_missed_${audio.id}') {
            matchesExistingServerLog = true;
            break;
          }
          final logDt = _parseCallLogDateTime(log);
          if (logDt != null && audioMs > 0) {
            final diffMs = (audioMs - logDt.millisecondsSinceEpoch).abs();
            if (diffMs < 180000) {
              final audioType = _getResolvedCallType(audio, state.leadDetail.phone).toUpperCase();
              final bUpper = (audio.bound ?? '').toUpperCase().trim();
              final isAudioIncoming = audioType == 'INBOUND' ||
                  audioType == 'IN' ||
                  audioType == 'INCOMING' ||
                  bUpper == 'IN' ||
                  bUpper.startsWith('INC');
              final isLogIncoming = _resolveIsIncoming(log, state.leadDetail.phone, null);
              if (isAudioIncoming == isLogIncoming) {
                matchesExistingServerLog = true;
                break;
              }
            }
          }
        }

        if (!matchesExistingServerLog) {
          final audioMs = _getEffectiveTimestamp(audio);
          final dt = audioMs > 0 ? DateTime.fromMillisecondsSinceEpoch(audioMs) : (audio.createdAt ?? DateTime.now());
          final timeStr = DateFormat('HH:mm:ss').format(dt);
          final dateStr = DateFormat('yyyy-MM-dd').format(dt);
          final audioType = _getResolvedCallType(audio, state.leadDetail.phone).toUpperCase();
          final bUpper = (audio.bound ?? '').toUpperCase().trim();
          final isIncoming = audioType == 'INBOUND' ||
              audioType == 'IN' ||
              audioType == 'INCOMING' ||
              bUpper == 'IN' ||
              bUpper == 'INBOUND' ||
              bUpper == 'INCOMING' ||
              bUpper.startsWith('INC') ||
              bUpper.startsWith('INB');
          final targetBound = isIncoming ? 'IN' : 'OUT';

          final isAudioMissed = !_audioHasRealFile(audio);

          final String statusFinal;
          if (isAudioMissed) {
            statusFinal = isIncoming ? 'MISSED' : 'NOT_CONNECTED';
          } else {
            statusFinal = isIncoming ? 'INCOMING' : 'OUTGOING';
          }

          rawServerHistory.add(LeadCallLog(
            id: 'audio_${isAudioMissed ? "missed" : "connected"}_${audio.id}',
            leadId: state.leadDetail.id,
            bound: targetBound,
            startTime: audio.startTimeStr ?? timeStr,
            endTime: audio.endTimeStr ?? timeStr,
            fromNumber: audio.fromNumber ?? (isIncoming ? state.leadDetail.phone : 'Me'),
            toNumber: audio.toNumber ?? (isIncoming ? 'Me' : state.leadDetail.phone),
            duration: audio.durationSeconds > 0 ? '${audio.durationSeconds}s' : '0s',
            callDate: dateStr,
            callStatus: statusFinal,
            createdAt: dt.toIso8601String(),
          ));
        }
      }
    }

    // Merge local tracked call history matching lead's phone number
    if (_localTrackedCalls.isNotEmpty) {
      final cleanLeadPhone = state.leadDetail.phone.replaceAll(RegExp(r'\D'), '');
      final leadLast10 = cleanLeadPhone.length >= 10 ? cleanLeadPhone.substring(cleanLeadPhone.length - 10) : cleanLeadPhone;

      if (leadLast10.isNotEmpty) {
        for (final localCall in _localTrackedCalls) {
          final hPhoneDigits = localCall.phoneNumber.replaceAll(RegExp(r'\D'), '');
          final hLast10 = hPhoneDigits.length >= 10 ? hPhoneDigits.substring(hPhoneDigits.length - 10) : hPhoneDigits;

          if (hLast10 == leadLast10 || hPhoneDigits.contains(leadLast10)) {
            final callStMs = localCall.startTime > 0 ? localCall.startTime : localCall.timestamp;
            bool matched = false;

            final isIncoming = localCall.callType.toUpperCase() == 'INCOMING' || localCall.callType.toUpperCase() == 'MISSED';
            final isLocalMissed = localCall.callStatus.toUpperCase() == 'MISSED' ||
                localCall.callStatus.toUpperCase() == 'UNANSWERED' ||
                localCall.callStatus.toUpperCase() == 'REJECTED' ||
                localCall.durationSeconds == 0;
            final localBoundStr = isIncoming ? 'IN' : 'OUT';

            for (final sLog in rawServerHistory) {
              final logDt = _parseCallLogDateTime(sLog);
              final sMs = logDt?.millisecondsSinceEpoch ?? 0;
              if (sMs > 0 && (sMs - callStMs).abs() < 30000) {
                final isServerBoundMatch = AutoCallRecordingUploader.checkBoundMatch(localBoundStr, sLog.bound);
                final isServerMissed = _isMissedLog(sLog);
                if (isServerBoundMatch && (isLocalMissed == isServerMissed)) {
                  matched = true;
                  break;
                }
              }
            }

            if (!matched && state.audios != null) {
              for (final sAudio in state.audios!) {
                final audioMs = _getEffectiveTimestamp(sAudio);
                if (audioMs > 0 && (audioMs - callStMs).abs() < 30000) {
                  final serverBound = sAudio.bound ?? '';
                  final isServerBoundMatch = AutoCallRecordingUploader.checkBoundMatch(localBoundStr, serverBound);
                  final isAudioMissed = !_audioHasRealFile(sAudio);
                  if (isServerBoundMatch && (isLocalMissed == isAudioMissed)) {
                    matched = true;
                    break;
                  }
                }
              }
            }

            if (!matched) {
              final dt = DateTime.fromMillisecondsSinceEpoch(callStMs);
              final timeStr = DateFormat('HH:mm:ss').format(dt);
              final dateStr = DateFormat('yyyy-MM-dd').format(dt);
              final isIncoming = localCall.callType.toUpperCase() == 'INCOMING' || localCall.callType.toUpperCase() == 'MISSED';
              final isMissed = localCall.callStatus.toUpperCase() == 'MISSED' ||
                  localCall.callStatus.toUpperCase() == 'UNANSWERED' ||
                  localCall.callStatus.toUpperCase() == 'REJECTED' ||
                  localCall.durationSeconds == 0;

              final String statusFinal;
              if (isMissed) {
                statusFinal = isIncoming ? 'MISSED' : 'NOT_CONNECTED';
              } else {
                statusFinal = isIncoming ? 'INCOMING' : 'OUTGOING';
              }

              rawServerHistory.add(LeadCallLog(
                id: 'local_history_${localCall.id}',
                leadId: state.leadDetail.id,
                bound: isIncoming ? 'IN' : 'OUT',
                startTime: timeStr,
                endTime: timeStr,
                fromNumber: (localCall.appUserPhone != null && localCall.appUserPhone!.isNotEmpty) ? localCall.appUserPhone! : (isIncoming ? state.leadDetail.phone : 'Me'),
                toNumber: isIncoming ? 'Me' : state.leadDetail.phone,
                duration: localCall.durationSeconds > 0 ? '${localCall.durationSeconds}s' : '0s',
                callDate: dateStr,
                callStatus: statusFinal,
                createdAt: dt.toIso8601String(),
              ));
            }
          }
        }
      }
    }

    // Merge Android system call logs (including incoming missed calls & unanswered calls)
    if (_systemCallLogs.isNotEmpty) {
      for (final sysCall in _systemCallLogs) {
        final st = sysCall['startTime'] as int? ?? 0;
        if (st <= 0) continue;

        final dur = sysCall['durationSeconds'] as int? ?? 0;
        final cType = (sysCall['callType'] as String? ?? '').toUpperCase();
        final cStatus = (sysCall['callStatus'] as String? ?? '').toUpperCase();
        final isIncoming = cType == 'INCOMING' || cType == 'MISSED' || cType == 'REJECTED' || cStatus == 'MISSED';
        final isMissed = cStatus == 'MISSED' || cStatus == 'UNANSWERED' || cStatus == 'REJECTED' || dur == 0;
        final sysBound = isIncoming ? 'IN' : 'OUT';

        bool matched = false;
        for (final sLog in rawServerHistory) {
          final logDt = _parseCallLogDateTime(sLog);
          final sMs = logDt?.millisecondsSinceEpoch ?? 0;
          if (sMs > 0 && (sMs - st).abs() < 60000) {
            final isServerBoundMatch = AutoCallRecordingUploader.checkBoundMatch(sysBound, sLog.bound);
            final isServerMissed = _isMissedLog(sLog);
            if (isServerBoundMatch && (isMissed == isServerMissed)) {
              matched = true;
              break;
            }
          }
        }

        if (!matched && state.audios != null) {
          for (final sAudio in state.audios!) {
            final audioMs = _getEffectiveTimestamp(sAudio);
            if (audioMs > 0 && (audioMs - st).abs() < 60000) {
              final serverBound = sAudio.bound ?? '';
              final isServerBoundMatch = AutoCallRecordingUploader.checkBoundMatch(sysBound, serverBound);
              final isAudioMissed = !_audioHasRealFile(sAudio);
              if (isServerBoundMatch && (isMissed == isAudioMissed)) {
                matched = true;
                break;
              }
            }
          }
        }

        if (!matched) {
          final dt = DateTime.fromMillisecondsSinceEpoch(st);
          final timeStr = DateFormat('HH:mm:ss').format(dt);
          final dateStr = DateFormat('yyyy-MM-dd').format(dt);
          final statusFinal = isMissed ? (isIncoming ? 'MISSED' : 'NOT_CONNECTED') : (isIncoming ? 'INCOMING' : 'OUTGOING');

          rawServerHistory.add(LeadCallLog(
            id: 'sys_log_${st}_$sysBound',
            leadId: state.leadDetail.id,
            bound: sysBound,
            startTime: timeStr,
            endTime: timeStr,
            fromNumber: sysCall['fromNumber']?.toString() ?? (isIncoming ? state.leadDetail.phone : 'Me'),
            toNumber: sysCall['toNumber']?.toString() ?? (isIncoming ? 'Me' : state.leadDetail.phone),
            duration: dur > 0 ? '${dur}s' : '0s',
            callDate: dateStr,
            callStatus: statusFinal,
            createdAt: dt.toIso8601String(),
          ));
        }
      }
    }

    final List<LeadCallLog> effectiveCallHistory = [];

    for (final log in rawServerHistory) {
      if (effectiveCallHistory.any((e) => e.id == log.id)) continue;

      final dtLog = _parseCallLogDateTime(log);
      final logMs = dtLog?.millisecondsSinceEpoch ?? 0;
      final logBound = log.bound.toUpperCase();

      bool isDuplicate = false;
      for (int i = 0; i < effectiveCallHistory.length; i++) {
        final existing = effectiveCallHistory[i];
        if (existing.id == log.id) {
          isDuplicate = true;
          break;
        }

        final existingDt = _parseCallLogDateTime(existing);
        final existingMs = existingDt?.millisecondsSinceEpoch ?? 0;
        final existingBound = existing.bound.toUpperCase();

        final isBoundMatch = AutoCallRecordingUploader.checkBoundMatch(logBound, existingBound);
        final isTimeMatch = (logMs > 0 && existingMs > 0 && (logMs - existingMs).abs() < 60000);        if (isBoundMatch && isTimeMatch) {
          final existingIsMissed = _isMissedLog(existing);
          final logIsMissed = _isMissedLog(log);
          final sameStatus = (existingIsMissed == logIsMissed);

          if (sameStatus) {
            isDuplicate = true;

            final existingIsSynthetic = existing.id.startsWith('local_history_') ||
                existing.id.startsWith('sys_log_') ||
                existing.id.startsWith('audio_');
            final logIsSynthetic = log.id.startsWith('local_history_') ||
                log.id.startsWith('sys_log_') ||
                log.id.startsWith('audio_');

            if (existingIsSynthetic && !logIsSynthetic) {
              effectiveCallHistory[i] = log;
            } else if (!existingIsSynthetic && logIsSynthetic) {
              // Keep existing real server log
            } else {
              final existingDur = _parseDurationSeconds(existing.duration);
              final logDur = _parseDurationSeconds(log.duration);
              if (logDur > existingDur) {
                effectiveCallHistory[i] = log;
              }
            }
            break;
          } else if (existingIsMissed && !logIsMissed) {
            effectiveCallHistory[i] = log;
            isDuplicate = true;
            break;
          } else if (!existingIsMissed && logIsMissed) {
            isDuplicate = true;
            break;
          }
        }
      }

      if (!isDuplicate) {
        effectiveCallHistory.add(log);
      }
    }

    // Build 1-to-1 mapping from LeadCallLog -> LeadAudio (no double-claiming of audio recordings)
    final Map<String, LeadAudio?> logToAudioMap = {};
    final Set<String> claimedAudioIds = {};

    if (state.audios != null && state.audios!.isNotEmpty) {
      // Pass 1: Pair REAL server call logs (from API) FIRST with unclaimed LeadAudio
      for (final log in effectiveCallHistory) {
        if (log.id.startsWith('audio_connected_') || log.id.startsWith('audio_missed_')) continue;

        final logDt = _parseCallLogDateTime(log);
        final logBoundUpper = log.bound.toUpperCase();

        LeadAudio? bestMatch;
        int minDiffMs = 1000 * 60 * 360; // 6 hour tolerance (handles UTC vs local time zone shifts)

        for (final audio in state.audios!) {
          final hasRealFile = _audioHasRealFile(audio);
          if (!hasRealFile) continue;
          if (claimedAudioIds.contains(audio.id)) continue;

          final audioMs = _getEffectiveTimestamp(audio);

          if (logDt != null && audioMs > 0) {
            final diffMs = (audioMs - logDt.millisecondsSinceEpoch).abs();
            final audioType = _getResolvedCallType(audio, state.leadDetail.phone).toUpperCase();
            final audioBound = (audio.bound ?? '').toUpperCase();

            bool isDirectionMatch = true;
            if (logBoundUpper == 'IN') {
              isDirectionMatch = audioBound.contains('IN') || audioType == 'INBOUND' || audioType == 'IN';
            } else if (logBoundUpper == 'OUT') {
              isDirectionMatch = audioBound.contains('OUT') || audioType == 'OUTBOUND' || audioType == 'OUT';
            }

            if (isDirectionMatch && diffMs < minDiffMs) {
              minDiffMs = diffMs;
              bestMatch = audio;
            }
          }
        }

        if (bestMatch != null) {
          logToAudioMap[log.id] = bestMatch;
          claimedAudioIds.add(bestMatch.id);
          if (logBoundUpper == 'OUT' || logBoundUpper == 'OUTBOUND') {
            _resolvedCallTypes[bestMatch.id] = 'outbound';
          } else if (logBoundUpper == 'IN' || logBoundUpper == 'INBOUND') {
            _resolvedCallTypes[bestMatch.id] = 'inbound';
          }
        }
      }

      // Pass 1.5: Fallback matching for any remaining unclaimed LeadAudio with unmapped non-missed call logs
      for (final audio in state.audios!) {
        if (claimedAudioIds.contains(audio.id)) continue;
        if (!_audioHasRealFile(audio)) continue;

        final audioMs = _getEffectiveTimestamp(audio);
        if (audioMs <= 0) continue;

        LeadCallLog? bestLogMatch;
        int minDiffMs = 1000 * 60 * 360;

        for (final log in effectiveCallHistory) {
          if (logToAudioMap[log.id] != null) continue;
          if (_isMissedLog(log)) continue;

          final logDt = _parseCallLogDateTime(log);
          if (logDt != null) {
            final diffMs = (audioMs - logDt.millisecondsSinceEpoch).abs();
            if (diffMs < minDiffMs) {
              minDiffMs = diffMs;
              bestLogMatch = log;
            }
          }
        }

        if (bestLogMatch != null) {
          logToAudioMap[bestLogMatch.id] = audio;
          claimedAudioIds.add(audio.id);
        }
      }

      // Pass 2: Direct matches for remaining synthetic logs where audio was not claimed by a real server log
      for (final log in effectiveCallHistory) {
        if (log.id.startsWith('audio_connected_') || log.id.startsWith('audio_missed_')) {
          final audioId = log.id.replaceFirst('audio_connected_', '').replaceFirst('audio_missed_', '');
          if (claimedAudioIds.contains(audioId)) continue;

          LeadAudio? matched;
          for (final a in state.audios!) {
            if (a.id == audioId) {
              matched = a;
              break;
            }
          }
          if (matched != null) {
            logToAudioMap[log.id] = matched;
            claimedAudioIds.add(matched.id);
          }
        }
      }

      // Prune any synthetic audio_connected_ logs or spurious sys_log_/local_history_ duplicates near matching real server logs
      effectiveCallHistory.removeWhere((log) {
        if (log.id.startsWith('audio_connected_') || log.id.startsWith('audio_missed_')) {
          final audioId = log.id.replaceFirst('audio_connected_', '').replaceFirst('audio_missed_', '');
          return claimedAudioIds.contains(audioId) && logToAudioMap[log.id] == null;
        }
        if (log.id.startsWith('sys_log_') || log.id.startsWith('local_history_')) {
          final logDt = _parseCallLogDateTime(log);
          if (logDt != null) {
            for (final realLog in effectiveCallHistory) {
              if (realLog != log && !realLog.id.startsWith('sys_log_') && !realLog.id.startsWith('local_history_') && !realLog.id.startsWith('audio_')) {
                final rDt = _parseCallLogDateTime(realLog);
                if (rDt != null && (rDt.millisecondsSinceEpoch - logDt.millisecondsSinceEpoch).abs() < 120000) {
                  final sameBound = AutoCallRecordingUploader.checkBoundMatch(log.bound, realLog.bound);
                  final sameStatus = _isMissedLog(log) == _isMissedLog(realLog);
                  if (sameBound && sameStatus) {
                    return true;
                  }
                }
              }
            }
          }
        }
        return false;
      });
    }

    // Final post-processing deduplication pass: purge any residual duplicate call cards matching bound, status, and time (within 2 min)
    final List<LeadCallLog> finalHistoryList = [];
    for (final log in effectiveCallHistory) {
      final dtLog = _parseCallLogDateTime(log);
      final logMs = dtLog?.millisecondsSinceEpoch ?? 0;

      bool isDup = false;
      for (int i = 0; i < finalHistoryList.length; i++) {
        final existing = finalHistoryList[i];
        final dtExisting = _parseCallLogDateTime(existing);
        final existingMs = dtExisting?.millisecondsSinceEpoch ?? 0;

        final sameBound = AutoCallRecordingUploader.checkBoundMatch(log.bound, existing.bound);
        final sameStatus = _isMissedLog(log) == _isMissedLog(existing);
        final timeDiff = (logMs > 0 && existingMs > 0) ? (logMs - existingMs).abs() : 999999;

        if (sameBound && sameStatus && timeDiff < 120000) {
          isDup = true;
          if (logToAudioMap[log.id] != null && logToAudioMap[existing.id] == null) {
            finalHistoryList[i] = log;
          }
          break;
        }
      }
      if (!isDup) {
        finalHistoryList.add(log);
      }
    }

    finalHistoryList.sort((a, b) {
      final dtA = _getCallLogTimestamp(a, logToAudioMap[a.id]);
      final dtB = _getCallLogTimestamp(b, logToAudioMap[b.id]);
      return dtB.compareTo(dtA);
    });

    if (finalHistoryList.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          _fetchLocalRecordings(state.leadDetail.phone);
          context.read<LeadsBloc>().add(FetchLeadCallLogs(state.leadDetail.id));
          context.read<LeadsBloc>().add(FetchLeadAudios(state.leadDetail.id));
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: const Center(
              child: Text(
                'No call logs found for this lead.',
                style: TextStyle(color: AppColors.textHint, fontSize: 16),
              ),
            ),
          ),
        ),
      );
    }

    final totalCallsCount = finalHistoryList.length;
    final totalInboundCount = finalHistoryList.where((l) => _resolveIsIncoming(l, state.leadDetail.phone, logToAudioMap[l.id])).length;
    final totalOutboundCount = finalHistoryList.where((l) => !_resolveIsIncoming(l, state.leadDetail.phone, logToAudioMap[l.id])).length;
    final totalMissedCount = finalHistoryList.where(_isMissedLog).length;

    return RefreshIndicator(
      onRefresh: () async {
        _fetchLocalRecordings(state.leadDetail.phone);
        context.read<LeadsBloc>().add(FetchLeadCallLogs(state.leadDetail.id));
        context.read<LeadsBloc>().add(FetchLeadAudios(state.leadDetail.id));
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Cards
          Row(
            children: [
              Expanded(
                child: _buildCallLogSummaryCard(
                  'Total Calls',
                  totalCallsCount.toString(),
                  Icons.phone,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildCallLogSummaryCard(
                  'Duration',
                  _formatDuration(callLogs.totalDuration),
                  Icons.timer,
                  Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _buildCallLogSummaryCard(
                  'Inbound',
                  totalInboundCount.toString(),
                  Icons.call_received,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildCallLogSummaryCard(
                  'Outbound',
                  totalOutboundCount.toString(),
                  Icons.call_made,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildCallLogSummaryCard(
                  'Missed',
                  totalMissedCount.toString(),
                  Icons.call_missed,
                  Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Call History',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: AppColors.primary),
                tooltip: 'Refresh Call Logs',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Refreshing call logs...'),
                      duration: Duration(seconds: 1),
                      backgroundColor: AppColors.primary,
                    ),
                  );

                  _fetchLocalRecordings(widget.state.leadDetail.phone);
                  context.read<LeadsBloc>().add(FetchLeadCallLogs(widget.state.leadDetail.id));
                  context.read<LeadsBloc>().add(FetchLeadAudios(widget.state.leadDetail.id));
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          Builder(
            builder: (context) {
              // Group call logs by relative date header (Today, Yesterday, Date)
              final Map<String, List<LeadCallLog>> groupedLogs = {};
              for (final log in finalHistoryList) {
                final dt = _getCallLogTimestamp(log, logToAudioMap[log.id]);
                final headerKey = _getRelativeDateHeader(dt);
                groupedLogs.putIfAbsent(headerKey, () => []).add(log);
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: groupedLogs.entries.map((group) {
                  final headerKey = group.key;
                  final groupList = group.value;

                  groupList.sort((a, b) {
                    final dtA = _getCallLogTimestamp(a, logToAudioMap[a.id]);
                    final dtB = _getCallLogTimestamp(b, logToAudioMap[b.id]);
                    return dtB.compareTo(dtA);
                  });

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10.0, bottom: 8.0),
                        child: Row(
                          children: [
                            Text(
                              headerKey.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Divider(height: 1, color: AppColors.borderEnabled),
                            ),
                          ],
                        ),
                      ),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: groupList.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final log = groupList[index];
                          final matchedAudio = logToAudioMap[log.id];
                          return _buildCallLogListItem(log, matchedAudio, state);
                        },
                      ),
                      const SizedBox(height: 4),
                    ],
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    ),
  );
}

  Widget _buildCallLogSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCallLogListItem(LeadCallLog log, LeadAudio? matchedAudio, LeadDetailsLoaded state) {
    final isExpanded = _expandedCallLogIds.contains(log.id);
    final cardData = _buildCallCardDataFromLog(log, matchedAudio, state.leadDetail.phone);
    final isMissed = cardData.isUnanswered;
    final isIncoming = cardData.isIncoming;
    
    IconData icon;
    Color iconColor;
    
    if (isMissed) {
      icon = Icons.phone_missed_rounded;
      iconColor = const Color(0xFFD97706);
    } else if (isIncoming) {
      icon = Icons.call_received_rounded;
      iconColor = const Color(0xFF059669);
    } else {
      icon = Icons.call_made_rounded;
      iconColor = const Color(0xFFE11D48);
    }

    final displayDateTime = _formatCallLogDisplayTime(log, cardData.timestamp);
    final displayDuration = (cardData.durationStr.isNotEmpty && cardData.durationStr != 'Unanswered' && cardData.durationStr != 'Not Connected')
        ? cardData.durationStr
        : '0s';

    final String statusPillText;
    final Color statusPillTextColor;
    final Color statusPillBgColor;
    final Color statusPillBorderColor;

    if (isMissed) {
      if (isIncoming) {
        statusPillText = 'MISSED';
        statusPillTextColor = const Color(0xFFDC2626);
        statusPillBgColor = const Color(0xFFFEF2F2);
        statusPillBorderColor = const Color(0xFFFCA5A5);
      } else {
        statusPillText = 'NOT CONNECTED';
        statusPillTextColor = const Color(0xFFD97706);
        statusPillBgColor = const Color(0xFFFFFBEB);
        statusPillBorderColor = const Color(0xFFFCD34D);
      }
    } else {
      statusPillText = 'CONNECTED';
      statusPillTextColor = const Color(0xFF059669);
      statusPillBgColor = const Color(0xFFECFDF5);
      statusPillBorderColor = const Color(0xFF6EE7B7);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExpanded ? AppColors.primary.withValues(alpha: 0.5) : AppColors.borderEnabled,
          width: isExpanded ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        children: [
          // Header Row (Tappable to toggle dropdown)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCallLogIds.remove(log.id);
                } else {
                  _expandedCallLogIds.add(log.id);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                isIncoming ? log.fromNumber : log.toNumber,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                  color: AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              displayDuration,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayDateTime,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textHint,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (cardData.audio != null) ...[
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                    ),
                                    child: const Icon(Icons.mic_rounded, color: AppColors.primary, size: 12),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: statusPillBgColor,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: statusPillBorderColor),
                                    ),
                                    child: Text(
                                      statusPillText,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: statusPillTextColor,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.3,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                  color: isExpanded ? AppColors.primary : AppColors.textHint,
                                  size: 20,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Dropdown containing audio call recording card when expanded
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _buildAudioCallCardWidget(cardData),
            ),
        ],
      ),
    );
  }

  Widget _buildAudioCallCardWidget(_CallCardData data) {
    final hasAudio = data.audio != null;
    final isUnanswered = data.isUnanswered;

    Color iconBgColor;
    Color iconColor;
    IconData cardIcon;

    if (isUnanswered) {
      cardIcon = Icons.call_missed_rounded;
      iconBgColor = const Color(0xFFFEF3C7);
      iconColor = const Color(0xFFD97706);
    } else if (data.isIncoming) {
      cardIcon = Icons.call_received_rounded;
      iconBgColor = const Color(0xFFD1FAE5);
      iconColor = const Color(0xFF059669);
    } else {
      cardIcon = Icons.call_made_rounded;
      iconBgColor = const Color(0xFFFFE4E6);
      iconColor = const Color(0xFFE11D48);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderEnabled.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(cardIcon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${data.fromPhone} ➔ ${data.toPhone}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (hasAudio)
                Row(
                  children: [
                    // Play Button
                    InkWell(
                      onTap: () => _playLeadAudio(data.audio!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 3),
                            Text('Play', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Download Button
                    InkWell(
                      onTap: () => _downloadLeadAudio(context, data.audio!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.primary),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.download_rounded, color: AppColors.primary, size: 16),
                            SizedBox(width: 3),
                            Text('Download', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.borderEnabled),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMetaItem('Time', '${data.startTimeStr} - ${data.endTimeStr}'),
              _buildMetaItem('Duration', data.durationStr.isEmpty ? '0s' : data.durationStr),
              _buildMetaItem('Audio Size', data.sizeStr),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textHint,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  void _downloadLeadAudio(BuildContext context, LeadAudio audio) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SpinningLogo(size: 44),
              const SizedBox(height: 16),
              Text(
                'Downloading ${audio.displayName}...',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Please wait, saving to Downloads folder.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textHint),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final tempDir = await getTemporaryDirectory();
      final displayFileName = audio.displayName.isNotEmpty ? audio.displayName : 'audio_${audio.id}.mp3';
      final sanitizedName = displayFileName.replaceAll(RegExp(r'[^\w.\- ]'), '_');
      final tempFile = File('${tempDir.path}/$sanitizedName');

      final leadsBaseUrl = ApiUrl.leadService;
      final candidateUrls = <String>[];
      if (audio.leadId.isNotEmpty && audio.id.isNotEmpty) {
        candidateUrls.add('$leadsBaseUrl/leads/${audio.leadId}/audios/${audio.id}/download');
      }
      if (audio.id.isNotEmpty) {
        candidateUrls.add('$leadsBaseUrl/leads/audios/${audio.id}/download');
        candidateUrls.add('$leadsBaseUrl/audios/${audio.id}/download');
      }
      if (audio.fileName.startsWith('http://') || audio.fileName.startsWith('https://')) {
        candidateUrls.add(audio.fileName);
      }

      bool downloaded = false;
      for (final downloadUrl in candidateUrls) {
        try {
          debugPrint('Attempting download: $downloadUrl');
          final response = await sl<ApiClient>().download(downloadUrl, tempFile.path);
          if (response.statusCode == 200 && await tempFile.exists() && (await tempFile.length()) > 0) {
            downloaded = true;
            break;
          }
        } catch (e) {
          debugPrint('Download attempt failed for $downloadUrl: $e');
        }
      }

      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

      if (downloaded && await tempFile.exists() && (await tempFile.length()) > 0) {
        String? finalPath;
        if (Platform.isAndroid) {
          try {
            finalPath = await const MethodChannel('com.example.crm_mobile/call_recording').invokeMethod<String>(
              'saveToDownloads',
              {
                'filePath': tempFile.path,
                'fileName': sanitizedName,
                'mimeType': audio.contentType,
              },
            );
          } catch (e) {
            debugPrint('Error invoking saveToDownloads: $e');
          }
        }

        final savedFile = (finalPath != null && !finalPath.startsWith('content://')) ? File(finalPath) : tempFile;

        if (context.mounted) {
          final String shortName = audio.displayName.length > 25 
              ? '${audio.displayName.substring(0, 12)}...${audio.displayName.substring(audio.displayName.length - 10)}' 
              : audio.displayName;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Download Complete', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              content: Text('Successfully saved "$shortName" to your Downloads folder.', style: const TextStyle(fontSize: 14)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CANCEL', style: TextStyle(color: AppColors.textHint)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      if (Platform.isAndroid) {
                        await const MethodChannel('com.example.crm_mobile/call_recording').invokeMethod(
                          'openFile',
                          {
                            'filePath': savedFile.path,
                            'mimeType': audio.contentType,
                          },
                        );
                      } else {
                        final Uri uri = Uri.file(savedFile.path);
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    } catch (e) {
                      debugPrint('Could not launch file: $e');
                    }
                  },
                  child: const Text('OPEN FILE'),
                ),
              ],
            ),
          );
        }
      } else {
        if (context.mounted) {
          final String shortName = audio.displayName.length > 25 
              ? '${audio.displayName.substring(0, 12)}...${audio.displayName.substring(audio.displayName.length - 10)}' 
              : audio.displayName;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Download Failed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              content: Text('Could not download "$shortName". Please check your connection and try again.', style: const TextStyle(fontSize: 14)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CANCEL', style: TextStyle(color: AppColors.textHint)),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      debugPrint('Audio download error: $e');
      if (context.mounted) {
        final String shortName = audio.displayName.length > 25 
            ? '${audio.displayName.substring(0, 12)}...${audio.displayName.substring(audio.displayName.length - 10)}' 
            : audio.displayName;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Download Error', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            content: Text('An error occurred while downloading "$shortName".', style: const TextStyle(fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCEL', style: TextStyle(color: AppColors.textHint)),
              ),
            ],
          ),
        );
      }
    }
  }

  String _getAudioFileExtension(LeadAudio audio) {
    final lowerName = '${audio.fileName} ${audio.originalFileName} ${audio.displayName}'.toLowerCase();
    if (lowerName.contains('.wav')) return '.wav';
    if (lowerName.contains('.mp3')) return '.mp3';
    if (lowerName.contains('.m4a')) return '.m4a';
    if (lowerName.contains('.aac')) return '.aac';
    if (lowerName.contains('.3gp') || lowerName.contains('.3gpp')) return '.3gp';
    if (lowerName.contains('.amr')) return '.amr';
    if (lowerName.contains('.ogg') || lowerName.contains('.opus')) return '.ogg';
    
    final mime = audio.contentType.toLowerCase();
    if (mime.contains('mp3') || mime.contains('mpeg')) return '.mp3';
    if (mime.contains('wav')) return '.wav';
    if (mime.contains('3gp')) return '.3gp';
    if (mime.contains('amr')) return '.amr';
    if (mime.contains('ogg')) return '.ogg';
    if (mime.contains('aac')) return '.aac';
    
    return '.m4a';
  }

  Future<bool> _checkAudioFileValid(File file) async {
    if (!await file.exists()) return false;
    final len = await file.length();
    if (len < 500) return false;

    try {
      final raf = await file.open(mode: FileMode.read);
      final bytes = await raf.read(64);
      await raf.close();

      if (bytes.isEmpty) return false;

      final firstByte = bytes[0];
      if (firstByte == 0x7B /* '{' */ || firstByte == 0x3C /* '<' */) {
        return false;
      }

      final asciiStr = String.fromCharCodes(bytes.where((b) => b >= 32 && b <= 126));
      if (asciiStr.contains('<html>') || asciiStr.contains('<HTML>') || asciiStr.contains('404 Not Found') || asciiStr.contains('"success":false')) {
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<File?> _findLocalDeviceRecording(LeadAudio audio) async {
    try {
      if (audio.fileName.isNotEmpty && File(audio.fileName).existsSync() && File(audio.fileName).lengthSync() >= 500) {
        final f = File(audio.fileName);
        if (await _checkAudioFileValid(f)) return f;
      }

      final service = CallRecordingService();
      final phonesToSearch = <String>{};
      if (widget.state.leadDetail.phone.isNotEmpty) phonesToSearch.add(widget.state.leadDetail.phone);
      if (audio.fromNumber != null && audio.fromNumber!.isNotEmpty) phonesToSearch.add(audio.fromNumber!);
      if (audio.toNumber != null && audio.toNumber!.isNotEmpty) phonesToSearch.add(audio.toNumber!);

      final audioNameLower = '${audio.fileName} ${audio.originalFileName} ${audio.displayName}'.toLowerCase();
      final targetClean = AutoCallRecordingUploader.cleanFileName(audioNameLower);

      for (final phone in phonesToSearch) {
        final recordings = await service.getAllSystemRecordings(phone);
        for (final rec in recordings) {
          final path = rec['path'] as String?;
          if (path == null || path.isEmpty) continue;
          final f = File(path);
          if (!await f.exists()) continue;
          final len = await f.length();
          if (len < 500) continue;

          final recNameLower = path.split('/').last.toLowerCase();
          final recClean = AutoCallRecordingUploader.cleanFileName(recNameLower);

          final isSizeMatch = audio.size > 0 && (len - audio.size).abs() < 2048;
          final isNameMatch = (recClean.isNotEmpty && targetClean.isNotEmpty && (recClean.contains(targetClean) || targetClean.contains(recClean))) ||
              (audio.id.isNotEmpty && recNameLower.contains(audio.id)) ||
              (audio.fileName.isNotEmpty && recNameLower.contains(audio.fileName.toLowerCase()));

          if (isSizeMatch || isNameMatch) {
            if (await _checkAudioFileValid(f)) {
              debugPrint('Found local device recording match for audio ${audio.id}: ${f.path}');
              return f;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error searching local device recording: $e');
    }
    return null;
  }

  void _playLeadAudio(LeadAudio audio) async {
    if (!_audioHasRealFile(audio)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No audio recording available for this call.'),
          backgroundColor: AppColors.primary,
        ),
      );
      return;
    }

    void handleDurationFound(int seconds) {
      if (mounted && seconds > 0) {
        if (_resolvedAudioDurations[audio.id] != seconds) {
          setState(() {
            _resolvedAudioDurations[audio.id] = seconds;
          });
        }
      }
    }

    // 1. Check if recording exists locally on device
    final localFile = await _findLocalDeviceRecording(audio);
    if (localFile != null) {
      if (!mounted) return;
      debugPrint('Playing local device recording: ${localFile.path}');
      CallRecordingService().playRecording(localFile.path, context: context, title: audio.displayName, onDurationFound: handleDurationFound);
      return;
    }

    if (!mounted) return;

    // 2. Download from server with full candidate URLs if not local
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SpinningLogo(size: 40),
              const SizedBox(height: 14),
              Text(
                'Loading ${audio.displayName}...',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final tempDir = await getTemporaryDirectory();
      final ext = _getAudioFileExtension(audio);
      final displayFileName = audio.displayName.isNotEmpty ? audio.displayName : 'audio_${audio.id}';
      var sanitizedName = displayFileName.replaceAll(RegExp(r'[^\w.\- ]'), '_');
      if (!sanitizedName.toLowerCase().contains('.')) {
        sanitizedName = '$sanitizedName$ext';
      }
      final tempFile = File('${tempDir.path}/audio_${audio.id}_$sanitizedName');

      bool downloaded = false;
      if (await tempFile.exists()) {
        if (await _checkAudioFileValid(tempFile)) {
          downloaded = true;
        } else {
          try {
            await tempFile.delete();
          } catch (_) {}
        }
      }

      if (!downloaded) {
        final leadsBaseUrl = ApiUrl.leadService;
        final baseUrlWithoutApi = leadsBaseUrl.replaceAll(RegExp(r'/api/v1/?$'), '');
        final candidateUrls = <String>[];

        if (audio.fileName.startsWith('http://') || audio.fileName.startsWith('https://')) {
          candidateUrls.add(audio.fileName);
        }

        if (audio.leadId.isNotEmpty && audio.id.isNotEmpty) {
          candidateUrls.add('$leadsBaseUrl/leads/${audio.leadId}/audios/${audio.id}/download');
          candidateUrls.add('$leadsBaseUrl/leads/${audio.leadId}/audios/${audio.id}');
        }
        if (audio.id.isNotEmpty) {
          candidateUrls.add('$leadsBaseUrl/leads/audios/${audio.id}/download');
          candidateUrls.add('$leadsBaseUrl/leads/audios/${audio.id}');
          candidateUrls.add('$leadsBaseUrl/audios/${audio.id}/download');
          candidateUrls.add('$leadsBaseUrl/audios/${audio.id}');
        }
        if (audio.fileName.isNotEmpty) {
          final fn = audio.fileName.replaceAll('+', '_');
          candidateUrls.add('$leadsBaseUrl/uploads/audios/$fn');
          candidateUrls.add('$leadsBaseUrl/uploads/$fn');
          candidateUrls.add('$baseUrlWithoutApi/uploads/audios/$fn');
          candidateUrls.add('$baseUrlWithoutApi/uploads/$fn');
        }

        for (final downloadUrl in candidateUrls) {
          debugPrint('Downloading audio file from: $downloadUrl to ${tempFile.path}');
          try {
            await sl<ApiClient>().download(
              downloadUrl,
              tempFile.path,
            );
            if (await tempFile.exists() && await _checkAudioFileValid(tempFile)) {
              downloaded = true;
              break;
            } else if (await tempFile.exists()) {
              try {
                await tempFile.delete();
              } catch (_) {}
            }
          } catch (e) {
            debugPrint('Failed download candidate $downloadUrl: $e');
          }
        }
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (downloaded && await tempFile.exists() && await _checkAudioFileValid(tempFile)) {
        if (!mounted) return;
        CallRecordingService().playRecording(tempFile.path, context: context, title: audio.displayName, onDurationFound: handleDurationFound);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Audio recording ${audio.displayName} is unavailable on the server.'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      debugPrint('Play error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load recording ${audio.displayName}'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    }
  }
}

class _CallCardData {
  final LeadAudio? audio;
  final DateTime timestamp;
  final bool isIncoming;
  final bool isUnanswered;
  final String title;
  final String fromPhone;
  final String toPhone;
  final String startTimeStr;
  final String endTimeStr;
  final String durationStr;
  final String sizeStr;
  final String dateStr;

  _CallCardData({
    this.audio,
    required this.timestamp,
    required this.isIncoming,
    required this.isUnanswered,
    required this.title,
    required this.fromPhone,
    required this.toPhone,
    required this.startTimeStr,
    required this.endTimeStr,
    required this.durationStr,
    required this.sizeStr,
    required this.dateStr,
  });
}
