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
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/blocs/leads_event.dart';
import 'package:crm_mobile/blocs/leads_state.dart';
import 'package:crm_mobile/core/services/call_recording_service.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_constants.dart';
import 'package:crm_mobile/models/lead_detail.dart';
import 'package:crm_mobile/widgets/call_number_picker_sheet.dart';

class LeadCallLogsTab extends StatefulWidget {
  final LeadDetailsLoaded state;

  const LeadCallLogsTab({super.key, required this.state});

  static List<String> collectUsableLeadPhones(LeadDetail lead) {
    final result = <String>[];
    final seen = <String>{};
    void addIfUsable(String? raw) {
      if (!AutoCallRecordingUploader.isUsablePhone(raw)) return;
      final trimmed = raw!.trim();
      final digits = AutoCallRecordingUploader.usablePhoneDigits(trimmed);
      final key =
          digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
      if (seen.add(key)) {
        result.add(trimmed);
      }
    }

    addIfUsable(lead.phone);
    addIfUsable(lead.alternatePhone);
    for (final opt in extractLeadDetailCustomPhoneOptions(lead.customFields)) {
      addIfUsable(opt.phoneNumber);
    }
    return result;
  }

  static bool itemBelongsToLead({
    required String itemLeadId,
    required String fromNumber,
    required String toNumber,
    required String bound,
    required LeadDetail lead,
    required List<String> leadPhones,
    String? fileName,
  }) {
    final cleanItemLeadId = itemLeadId.trim();
    if (cleanItemLeadId.isNotEmpty && cleanItemLeadId != lead.id) {
      return false;
    }
    if (leadPhones.isEmpty) return true;

    final fromUsable = AutoCallRecordingUploader.isUsablePhone(fromNumber);
    final toUsable = AutoCallRecordingUploader.isUsablePhone(toNumber);

    for (final lp in leadPhones) {
      if (AutoCallRecordingUploader.phonesMatch(fromNumber, lp) ||
          AutoCallRecordingUploader.phonesMatch(toNumber, lp)) {
        return true;
      }
    }

    if (fromUsable && toUsable) {
      return false;
    }

    final b = bound.trim().toUpperCase();
    if (b.startsWith('OUT') && toUsable) return false;
    if ((b == 'IN' || b.startsWith('INC') || b.startsWith('INB')) && fromUsable) {
      return false;
    }

    if (fileName != null &&
        fileName.trim().isNotEmpty &&
        leadPhones.every(
          (lp) => AutoCallRecordingUploader.hasConflictingPhoneInFileName(
            fileName,
            lp,
          ),
        )) {
      return false;
    }

    return true;
  }

  @override
  State<LeadCallLogsTab> createState() => _LeadCallLogsTabState();
}

class _LeadCallLogsTabState extends State<LeadCallLogsTab> {
  final Set<String> _expandedCallLogIds = {};
  final Map<String, String> _resolvedCallTypes = {};
  final Set<String> _pendingAsyncResolutions = {};
  final Map<String, int> _resolvedAudioDurations = {};
  String? _loadingAudioId;
  int _selectedSubTabIndex = 0;
  bool _isRefreshing = false;
  static String? _workingAudioUrlTemplate;

  List<MapEntry<String, String>> _buildOrderedAudioCandidates(
    LeadAudio audio, {
    bool includeFallbackStreamPaths = false,
  }) {
    final leadsBaseUrl = ApiUrl.leadService;
    final baseUrlWithoutApi = leadsBaseUrl.replaceAll(RegExp(r'/api/v1/?$'), '');
    final candidates = <MapEntry<String, String>>[];

    if (audio.fileName.startsWith('http://') ||
        audio.fileName.startsWith('https://')) {
      candidates.add(MapEntry('direct_url', audio.fileName));
    }
    if (audio.leadId.isNotEmpty && audio.id.isNotEmpty) {
      candidates.add(
        MapEntry(
          'lead_audio_download',
          '$leadsBaseUrl/leads/${audio.leadId}/audios/${audio.id}/download',
        ),
      );
      if (includeFallbackStreamPaths) {
        candidates.add(
          MapEntry(
            'lead_audio_stream',
            '$leadsBaseUrl/leads/${audio.leadId}/audios/${audio.id}',
          ),
        );
      }
    }
    if (audio.id.isNotEmpty) {
      candidates.add(
        MapEntry(
          'leads_audios_download',
          '$leadsBaseUrl/leads/audios/${audio.id}/download',
        ),
      );
      if (includeFallbackStreamPaths) {
        candidates.add(
          MapEntry('leads_audios_stream', '$leadsBaseUrl/leads/audios/${audio.id}'),
        );
      }
      candidates.add(
        MapEntry('audios_download', '$leadsBaseUrl/audios/${audio.id}/download'),
      );
      if (includeFallbackStreamPaths) {
        candidates.add(
          MapEntry('audios_stream', '$leadsBaseUrl/audios/${audio.id}'),
        );
      }
    }
    if (includeFallbackStreamPaths && audio.fileName.isNotEmpty) {
      final fn = audio.fileName.replaceAll('+', '_');
      candidates.add(MapEntry('uploads_audios', '$leadsBaseUrl/uploads/audios/$fn'));
      candidates.add(MapEntry('uploads_root', '$leadsBaseUrl/uploads/$fn'));
      candidates.add(
        MapEntry('base_uploads_audios', '$baseUrlWithoutApi/uploads/audios/$fn'),
      );
      candidates.add(MapEntry('base_uploads_root', '$baseUrlWithoutApi/uploads/$fn'));
    }

    final preferred = _workingAudioUrlTemplate;
    if (preferred != null) {
      final idx = candidates.indexWhere((e) => e.key == preferred);
      if (idx > 0) {
        final entry = candidates.removeAt(idx);
        candidates.insert(0, entry);
      }
    }
    return candidates;
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final leadPhones = _collectUsableLeadPhones(widget.state.leadDetail);
      for (final scanPhone in leadPhones) {
        if (!mounted) break;
        await AutoCallRecordingUploader.autoScanAndUploadLeadRecordings(
          context: context,
          leadId: widget.state.leadDetail.id,
          phoneNumber: scanPhone,
          existingServerAudios: widget.state.audios,
          existingServerCallLogs: widget.state.callLogs?.callHistory,
        );
      }
      if (mounted) {
        context.read<LeadsBloc>().add(FetchLeadCallLogs(widget.state.leadDetail.id));
        context.read<LeadsBloc>().add(FetchLeadAudios(widget.state.leadDetail.id));
      }
      await Future.delayed(const Duration(milliseconds: 400));
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (widget.state.audios == null && !widget.state.isAudiosLoading) {
          context.read<LeadsBloc>().add(FetchLeadAudios(widget.state.leadDetail.id));
        }
        if (widget.state.callLogs == null && !widget.state.isCallLogsLoading) {
          context.read<LeadsBloc>().add(FetchLeadCallLogs(widget.state.leadDetail.id));
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant LeadCallLogsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.leadDetail.id != widget.state.leadDetail.id) {
      _expandedCallLogIds.clear();
      _resolvedCallTypes.clear();
      _pendingAsyncResolutions.clear();
      _resolvedAudioDurations.clear();
      _loadingAudioId = null;
    }
  }

  /// Returns true if [audio] represents a real uploaded audio file,
  /// not just a dummy placeholder entry for a missed/unanswered call.
  /// Some backends return size=0 even for valid recordings, so we also
  /// check the fileName to determine if a real file was uploaded.
  bool _audioHasRealFile(LeadAudio audio) {
    if (audio.size > 0) return true;
    final fn = (audio.fileName.isNotEmpty ? audio.fileName : audio.displayName).toLowerCase();
    if (fn.isEmpty || fn == 'missed_call.mp3' || fn.contains('dummy')) return false;
    final cs = (audio.callStatus ?? '').toUpperCase();
    if ((cs == 'MISSED' || cs == 'UNANSWERED' || cs == 'NOT_CONNECTED') && audio.size <= 0) return false;
    return audio.id.isNotEmpty || fn.endsWith('.mp3') || fn.endsWith('.m4a') || fn.endsWith('.wav');
  }

  bool _isNotConnectedStatus(String callStatus) {
    final statusUpper = callStatus.trim().toUpperCase();
    return statusUpper == 'MISSED' ||
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
        statusUpper.contains('NOT_CONNECTED');
  }

  List<String> _collectUsableLeadPhones(LeadDetail lead) =>
      LeadCallLogsTab.collectUsableLeadPhones(lead);

  bool _belongsToCurrentLead({
    required String itemLeadId,
    required String fromNumber,
    required String toNumber,
    required String bound,
    required LeadDetail lead,
    required List<String> leadPhones,
    String? fileName,
  }) => LeadCallLogsTab.itemBelongsToLead(
        itemLeadId: itemLeadId,
        fromNumber: fromNumber,
        toNumber: toNumber,
        bound: bound,
        lead: lead,
        leadPhones: leadPhones,
        fileName: fileName,
      );

  String _effectiveLeadDisplayPhone(LeadDetail lead) {
    final phones = _collectUsableLeadPhones(lead);
    if (phones.isNotEmpty) return phones.first;
    final raw = lead.phone.trim();
    return (raw.isNotEmpty && raw != '-') ? raw : '';
  }

  bool _isMissedLog(LeadCallLog log, [String leadPhone = '', LeadAudio? matchedAudio]) {
    if (matchedAudio != null && _audioHasRealFile(matchedAudio)) return false;
    if (!_isNotConnectedStatus(log.callStatus)) return false;
    return _resolveIsIncoming(log, leadPhone, matchedAudio);
  }

  bool _isUnansweredLog(LeadCallLog log, [String leadPhone = '', LeadAudio? matchedAudio]) {
    if (matchedAudio != null && _audioHasRealFile(matchedAudio)) return false;
    if (!_isNotConnectedStatus(log.callStatus)) return false;
    return !_resolveIsIncoming(log, leadPhone, matchedAudio);
  }

  bool _resolveIsIncoming(LeadCallLog log, String leadPhone, LeadAudio? matchedAudio) {
    final statusUpper = log.callStatus.trim().toUpperCase();
    if (statusUpper == 'MISSED') return true;

    final cleanLead = leadPhone.replaceAll(RegExp(r'\D'), '');
    final cleanFrom = log.fromNumber.replaceAll(RegExp(r'\D'), '');
    final cleanTo = log.toNumber.replaceAll(RegExp(r'\D'), '');
    if (cleanLead.isNotEmpty) {
      final leadLast10 = cleanLead.length >= 10 ? cleanLead.substring(cleanLead.length - 10) : cleanLead;
      final fromLast10 = cleanFrom.length >= 10 ? cleanFrom.substring(cleanFrom.length - 10) : cleanFrom;
      final toLast10 = cleanTo.length >= 10 ? cleanTo.substring(cleanTo.length - 10) : cleanTo;
      if (fromLast10.isNotEmpty && fromLast10 == leadLast10) return true;
      if (toLast10.isNotEmpty && toLast10 == leadLast10 && fromLast10 != leadLast10) return false;
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

    if (AutoCallRecordingUploader.isUsablePhone(phoneNumber)) {
      final fromMatchesLead = AutoCallRecordingUploader.phonesMatch(
        audio.fromNumber,
        phoneNumber,
      );
      final toMatchesLead = AutoCallRecordingUploader.phonesMatch(
        audio.toNumber,
        phoneNumber,
      );

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

  DateTime _parseAudioDateTime(LeadAudio audio) {
    // 1. Authoritative: callDate + startTimeStr / createdAt from backend
    final parsed = AutoCallRecordingUploader.parseCallDateTime(
      audio.callDate,
      audio.startTimeStr,
      audio.createdAt?.toIso8601String(),
    );
    if (parsed != null && parsed.year >= 2020 && parsed.year <= 2030) {
      if (parsed.hour == 0 && parsed.minute == 0 && parsed.second == 0) {
        final timeFromFn = _extractDateTimeFromFileName(audio.displayName) ??
            _extractDateTimeFromFileName(audio.fileName);
        if (timeFromFn != null &&
            timeFromFn.year == parsed.year &&
            timeFromFn.month == parsed.month &&
            timeFromFn.day == parsed.day) {
          return timeFromFn;
        }
      }
      return parsed;
    }

    // 2. Extract YYYYMMDDHHmmss pattern from filename
    final fnDt = _extractDateTimeFromFileName(audio.displayName) ??
        _extractDateTimeFromFileName(audio.fileName);
    if (fnDt != null) return fnDt;

    // 3. Fallback to createdAt
    if (audio.createdAt != null && audio.createdAt!.year >= 2020 && audio.createdAt!.year <= 2030) {
      return audio.createdAt!.toLocal();
    }

    return parsed ?? audio.createdAt ?? DateTime.now();
  }

  DateTime? _extractDateTimeFromFileName(String filename) {
    if (filename.isEmpty) return null;
    final m = RegExp(
      r'(?:^|[^0-9])(20\d{2})[-_]?(0[1-9]|1[0-2])[-_]?(0[1-9]|[12]\d|3[01])[-_]?([01]\d|2[0-3])[-_]?([0-5]\d)[-_]?([0-5]\d)(?:$|[^0-9])',
    ).firstMatch(filename);
    if (m != null) {
      try {
        final y = int.parse(m.group(1)!);
        final mo = int.parse(m.group(2)!);
        final d = int.parse(m.group(3)!);
        final h = int.parse(m.group(4)!);
        final mi = int.parse(m.group(5)!);
        final s = int.parse(m.group(6)!);
        return DateTime(y, mo, d, h, mi, s);
      } catch (_) {}
    }
    return null;
  }

  int _getEffectiveTimestamp(LeadAudio audio) {
    return _parseAudioDateTime(audio).millisecondsSinceEpoch;
  }

  int _parseTimeStringToMs(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty || timeStr == 'null' || timeStr == '--:--') return 0;
    String clean = timeStr.trim();
    if (clean.contains(' - ')) {
      clean = clean.split(' - ').first.trim();
    }
    try {
      if (clean.contains('T')) {
        return DateTime.parse(clean).toLocal().millisecondsSinceEpoch;
      }
      final timeFormats = [
        'hh:mm:ss a',
        'hh:mm a',
        'HH:mm:ss',
        'HH:mm',
      ];
      for (final tf in timeFormats) {
        try {
          final parsed = DateFormat('yyyy-MM-dd $tf').parse('2000-01-01 $clean');
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
      return isIncoming ? 'Missed Call' : 'Unanswered Call';
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
    final str = seconds.toString().trim();
    if (str.isEmpty || str == 'null' || str == '--:--') return '0s';
    if (str.contains(':')) {
      return str;
    }
    final int secs = seconds is int ? seconds : (int.tryParse(str) ?? 0);
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
    return AutoCallRecordingUploader.parseCallDateTime(log.callDate, log.startTime, log.createdAt);
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
    final bool hasRealAudio = matchedAudio != null && _audioHasRealFile(matchedAudio);
    final logDurSec = _parseDurationStringToSeconds(log.duration);
    final bool isNotConnected = !hasRealAudio && logDurSec <= 0 && _isNotConnectedStatus(log.callStatus);
    final bool isIncoming = _resolveIsIncoming(log, leadPhone, matchedAudio);
    final bool isMissed = isNotConnected && isIncoming;
    final bool isUnanswered = isNotConnected && !isIncoming;
    
    final logDt = _parseCallLogDateTime(log);
    String dateStr = log.callDate;
    if (logDt != null) {
      dateStr = DateFormat('MMM dd, yyyy').format(logDt);
    }

    final audioMs = matchedAudio != null ? _getEffectiveTimestamp(matchedAudio) : 0;

    final logHasValidTime = logDt != null && !(logDt.hour == 0 && logDt.minute == 0 && logDt.second == 0);

    DateTime logTimestamp = logHasValidTime
        ? logDt
        : (audioMs > 0 ? DateTime.fromMillisecondsSinceEpoch(audioMs) : (logDt ?? DateTime.fromMillisecondsSinceEpoch(0)));

    final trueDurSec = isNotConnected ? 0 : _resolveTrueDurationSeconds(audio: matchedAudio, log: log);
    String durStr = isNotConnected ? '' : (trueDurSec > 0 ? _formatDuration(trueDurSec) : log.duration);

    String displayStartTime = _formatTimeString(log.startTime) ?? '--:--';
    String displayEndTime = _formatTimeString(log.endTime) ?? '--:--';

    // Only fallback to matchedAudio time strings if call log itself lacked valid times
    if (matchedAudio != null && (displayStartTime == '--:--' || displayStartTime == 'null' || displayStartTime.startsWith('12:00:00 AM'))) {
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
    }
    if (matchedAudio != null && (displayEndTime == '--:--' || displayEndTime == 'null' || displayEndTime.startsWith('12:00:00 AM'))) {
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

    DateTime? startDt = logHasValidTime
        ? logDt
        : (audioMs > 0 ? DateTime.fromMillisecondsSinceEpoch(audioMs) : logDt);

    if (startDt != null && !(startDt.hour == 0 && startDt.minute == 0 && startDt.second == 0)) {
      displayStartTime = DateFormat('hh:mm:ss a').format(startDt);
      final endDt = isNotConnected
          ? startDt
          : startDt.add(Duration(seconds: trueDurSec > 0 ? trueDurSec : 1));
      displayEndTime = DateFormat('hh:mm:ss a').format(endDt);
    }

    String sizeStr = 'No Audio';
    if (!isNotConnected && matchedAudio != null && matchedAudio.size > 0) {
      final kb = matchedAudio.size / 1024;
      final mb = kb / 1024;
      sizeStr = mb >= 1 ? '${mb.toStringAsFixed(1)} MB' : '${kb.toStringAsFixed(0)} KB';
    }

    final title = isMissed 
        ? 'Missed Call'
        : (isUnanswered
            ? 'Unanswered Call'
            : (matchedAudio != null ? _cleanAudioTitle(matchedAudio.displayName, isIncoming: isIncoming, isUnanswered: false) : (isIncoming ? 'Incoming Call' : 'Outgoing Call')));

    return _CallCardData(
      audio: hasRealAudio ? matchedAudio : null,
      timestamp: logTimestamp,
      isIncoming: isIncoming,
      isMissed: isMissed,
      isUnanswered: isUnanswered,
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

  String _formatAudioSize(int bytes) {
    if (bytes <= 0) return '0 KB';
    final kb = bytes / 1024;
    final mb = kb / 1024;
    return mb >= 1 ? '${mb.toStringAsFixed(1)} MB' : '${kb.toStringAsFixed(0)} KB';
  }

  Widget _buildSubTabBar({
    required int callLogsCount,
    required int audiosCount,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderEnabled),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSubTabItem(
              title: 'Call Logs',
              count: callLogsCount,
              icon: Icons.phone_in_talk_rounded,
              isSelected: _selectedSubTabIndex == 0,
              onTap: () => setState(() => _selectedSubTabIndex = 0),
            ),
          ),
          Expanded(
            child: _buildSubTabItem(
              title: 'Audio Recordings',
              count: audiosCount,
              icon: Icons.graphic_eq_rounded,
              isSelected: _selectedSubTabIndex == 1,
              onTap: () {
                setState(() => _selectedSubTabIndex = 1);
                if (widget.state.audios == null && !widget.state.isAudiosLoading) {
                  context.read<LeadsBloc>().add(FetchLeadAudios(widget.state.leadDetail.id));
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubTabItem({
    required String title,
    required int count,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioListItem(LeadAudio audio, LeadDetailsLoaded state) {
    final b = (audio.bound ?? '').toUpperCase();
    final isIncoming = b == 'IN' || b == 'INBOUND' || audio.callType == 'inbound';
    final iconColor = isIncoming ? const Color(0xFF059669) : const Color(0xFFE11D48);
    final iconBgColor = isIncoming ? const Color(0xFFD1FAE5) : const Color(0xFFFFE4E6);
    final cardIcon = isIncoming ? Icons.call_received_rounded : Icons.call_made_rounded;

    final displayTitle = audio.originalFileName.isNotEmpty
        ? audio.originalFileName
        : (audio.displayName.isNotEmpty ? audio.displayName : 'Call Recording');

    final fromPhone = (audio.fromNumber?.isNotEmpty == true) ? audio.fromNumber! : (isIncoming ? state.leadDetail.phone : 'Me');
    final toPhone = (audio.toNumber?.isNotEmpty == true) ? audio.toNumber! : (isIncoming ? 'Me' : state.leadDetail.phone);

    final durSec = audio.durationSeconds;
    final durStr = durSec > 0 ? '${durSec}s' : '0s';
    final sizeStr = _formatAudioSize(audio.size);

    final dt = _parseAudioDateTime(audio);
    final displayDate = DateFormat('MMM dd, yyyy • hh:mm a').format(dt);

    return Container(
      margin: const EdgeInsets.only(bottom: 8.0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderEnabled),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
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
                      displayTitle,
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
                      '$fromPhone ➔ $toPhone',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textHint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0xFF6EE7B7)),
                ),
                child: Text(
                  audio.callStatus?.toUpperCase() ?? 'CONNECTED',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF059669),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.borderEnabled),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMetaItem('Date & Time', displayDate),
              _buildMetaItem('Duration', durStr),
              _buildMetaItem('Audio Size', sizeStr),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.borderEnabled),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Play Button
              InkWell(
                onTap: _loadingAudioId == audio.id ? null : () => _playLeadAudio(audio),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_loadingAudioId == audio.id) ...[
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text('Loading...', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ] else ...[
                        const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 4),
                        const Text('Play', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Download Button
              InkWell(
                onTap: () => _downloadLeadAudio(context, audio),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.primary),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.download_rounded, color: AppColors.primary, size: 16),
                      SizedBox(width: 4),
                      Text('Download', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    final isEitherLoading = (state.callLogs == null && state.isCallLogsLoading) || (state.audios == null && state.isAudiosLoading);
    if (state.callLogs == null && state.audios == null) {
      if (isEitherLoading) {
        return const Center(child: SpinningLogo(size: 40));
      }
      if (state.callLogsError != null || state.audiosError != null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Failed to load call data', style: TextStyle(color: AppColors.primary)),
              TextButton(
                onPressed: () {
                  context.read<LeadsBloc>().add(FetchLeadCallLogs(state.leadDetail.id));
                  context.read<LeadsBloc>().add(FetchLeadAudios(state.leadDetail.id));
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      }
    }

    final leadPhones = _collectUsableLeadPhones(state.leadDetail);
    final leadDisplayPhone = _effectiveLeadDisplayPhone(state.leadDetail);
    final callLogs = state.callLogs;
    final List<LeadCallLog> unFilteredHistory =
        callLogs != null ? callLogs.callHistory : const [];
    final List<LeadCallLog> rawHistory = unFilteredHistory
        .where(
          (log) => _belongsToCurrentLead(
            itemLeadId: log.leadId,
            fromNumber: log.fromNumber,
            toNumber: log.toNumber,
            bound: log.bound,
            lead: state.leadDetail,
            leadPhones: leadPhones,
          ),
        )
        .toList();
    final bool filteredForeignLogs =
        callLogs != null && rawHistory.length < unFilteredHistory.length;

    // Filter server audios to real audio files for the Audios tab
    final List<LeadAudio> realAudios = (state.audios ?? [])
        .where(_audioHasRealFile)
        .where(
          (audio) => _belongsToCurrentLead(
            itemLeadId: audio.leadId,
            fromNumber: audio.fromNumber ?? '',
            toNumber: audio.toNumber ?? '',
            bound: audio.bound ?? audio.callType,
            lead: state.leadDetail,
            leadPhones: leadPhones,
            fileName: '${audio.fileName} ${audio.originalFileName}',
          ),
        )
        .toList();

    rawHistory.sort((a, b) {
      final dtA = _parseCallLogDateTime(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dtB = _parseCallLogDateTime(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return dtB.compareTo(dtA);
    });

    // Deduplicate only identical records or tight timestamp jitter collisions (<= 3s)
    final List<LeadCallLog> serverHistory = [];
    for (final log in rawHistory) {
      final logDt = _parseCallLogDateTime(log);
      final logTimeMs = logDt?.millisecondsSinceEpoch ?? 0;
      final logBound = log.bound.toUpperCase();

      bool isDuplicate = false;
      for (int i = 0; i < serverHistory.length; i++) {
        final existing = serverHistory[i];
        if (existing.id.isNotEmpty && existing.id == log.id) {
          isDuplicate = true;
          break;
        }
        final exBound = existing.bound.toUpperCase();
        final sameBound = (logBound.startsWith('IN') && exBound.startsWith('IN')) ||
            (logBound.startsWith('OUT') && exBound.startsWith('OUT'));
        if (!sameBound) continue;

        final exDt = _parseCallLogDateTime(existing);
        final exTimeMs = exDt?.millisecondsSinceEpoch ?? 0;
        final logDur = int.tryParse(log.duration.replaceAll(RegExp(r'\D'), '')) ?? 0;
        final exDur = int.tryParse(existing.duration.replaceAll(RegExp(r'\D'), '')) ?? 0;
        final logConnected = log.callStatus.toUpperCase().contains('CONN') ||
            log.callStatus.toUpperCase().contains('ANS') ||
            logDur > 0;
        final exConnected = existing.callStatus.toUpperCase().contains('CONN') ||
            existing.callStatus.toUpperCase().contains('ANS') ||
            exDur > 0;
        final sameStatus = existing.callStatus.toUpperCase() == log.callStatus.toUpperCase() ||
            (existing.callStatus.toUpperCase().contains('CONN') && log.callStatus.toUpperCase().contains('ANS')) ||
            (existing.callStatus.toUpperCase().contains('ANS') && log.callStatus.toUpperCase().contains('CONN'));

        final diffMs = (logTimeMs > 0 && exTimeMs > 0) ? (logTimeMs - exTimeMs).abs() : 1 << 30;
        if (logConnected && exConnected) {
          // Only dedup two connected logs if they start within jitter range AND have compatible duration
          if (diffMs <= 3000 && (logDur == 0 || exDur == 0 || (logDur - exDur).abs() <= 10)) {
            if (logDur > exDur) {
              serverHistory[i] = log;
            }
            isDuplicate = true;
            break;
          }
        } else if (logConnected != exConnected) {
          // Connected log supersedes a nearby 0s shadow entry at the same start timestamp
          if (diffMs <= 3000) {
            if (logConnected && !exConnected) {
              serverHistory[i] = log;
            }
            isDuplicate = true;
            break;
          }
        } else {
          if (sameStatus && diffMs <= 2500) {
            isDuplicate = true;
            break;
          }
        }
      }
      if (!isDuplicate) {
        serverHistory.add(log);
      }
    }

    realAudios.sort((a, b) {
      final dtA = _parseAudioDateTime(a);
      final dtB = _parseAudioDateTime(b);
      return dtB.compareTo(dtA);
    });

    // Call logs summary metrics from /call-logs endpoint (recalculated if foreign logs filtered)
    final totalCallsCount = (!filteredForeignLogs && callLogs != null)
        ? callLogs.totalCalls
        : serverHistory.length;
    final totalDurationSec = (!filteredForeignLogs && callLogs != null)
        ? callLogs.totalDuration
        : serverHistory.fold<int>(0, (sum, l) => sum + _parseDurationStringToSeconds(l.duration));
    final totalInboundCount = (!filteredForeignLogs && callLogs != null)
        ? callLogs.totalInboundCalls
        : serverHistory.where((l) {
            final b = l.bound.toUpperCase();
            return b == 'IN' || b == 'INBOUND' || b.startsWith('IN');
          }).length;
    final totalOutboundCount = (!filteredForeignLogs && callLogs != null)
        ? callLogs.totalOutboundCalls
        : serverHistory.where((l) {
            final b = l.bound.toUpperCase();
            return b == 'OUT' || b == 'OUTBOUND' || b.startsWith('OUT');
          }).length;
    final totalMissedCount = (!filteredForeignLogs && callLogs != null && callLogs.totalMissedCalls > 0)
        ? callLogs.totalMissedCalls
        : serverHistory.where((l) => _isMissedLog(l, leadDisplayPhone)).length;
    final totalUnansweredCount = (!filteredForeignLogs && callLogs != null && callLogs.totalUnansweredCalls > 0)
        ? callLogs.totalUnansweredCalls
        : serverHistory.where((l) => _isUnansweredLog(l, leadDisplayPhone)).length;

    // Audio recordings summary metrics from /audios endpoint
    final totalAudiosCount = realAudios.length;
    final inboundAudiosCount = realAudios.where((a) {
      final b = (a.bound ?? '').toUpperCase();
      return b == 'IN' || b == 'INBOUND' || a.callType == 'inbound';
    }).length;
    final outboundAudiosCount = realAudios.where((a) {
      final b = (a.bound ?? '').toUpperCase();
      return b == 'OUT' || b == 'OUTBOUND' || a.callType == 'outbound';
    }).length;
    final totalAudioBytes = realAudios.fold<int>(0, (sum, a) => sum + a.size);

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sub-Tab Switcher: Call Logs vs Audio Recordings
            _buildSubTabBar(
              callLogsCount: serverHistory.length,
              audiosCount: realAudios.length,
            ),
            const SizedBox(height: 12),

            if (_selectedSubTabIndex == 0) ...[
              // === TAB 0: CALL LOGS (from /call-logs) ===
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
                      (callLogs != null && callLogs.totalDurationFormatted.isNotEmpty)
                          ? callLogs.totalDurationFormatted
                          : _formatDuration(totalDurationSec),
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
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _buildCallLogSummaryCard(
                      'Missed',
                      totalMissedCount.toString(),
                      Icons.phone_missed_rounded,
                      Colors.red,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildCallLogSummaryCard(
                      'Unanswered',
                      totalUnansweredCount.toString(),
                      Icons.call_missed_outgoing_rounded,
                      const Color(0xFFD97706),
                    ),
                  ),
                ],
              ),
              if (callLogs != null && (callLogs.ownerCallCount > 0 || callLogs.otherCallCount > 0)) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _buildCallLogSummaryCard(
                        'Owner Calls',
                        callLogs.ownerCallCount.toString(),
                        Icons.person,
                        Colors.teal,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildCallLogSummaryCard(
                        'Other Calls',
                        callLogs.otherCallCount.toString(),
                        Icons.people_outline,
                        Colors.indigo,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Call History (${serverHistory.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: (_isRefreshing || state.isCallLogsLoading)
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          )
                        : const Icon(Icons.refresh, color: AppColors.primary),
                    tooltip: 'Refresh Call Logs',
                    onPressed: (_isRefreshing || state.isCallLogsLoading) ? null : _handleRefresh,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (serverHistory.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  alignment: Alignment.center,
                  child: const Text(
                    'No call logs found for this lead.',
                    style: TextStyle(color: AppColors.textHint, fontSize: 15),
                  ),
                )
              else
                Builder(
                  builder: (context) {
                    final Map<String, List<LeadCallLog>> groupedLogs = {};
                    for (final log in serverHistory) {
                      final dt = _parseCallLogDateTime(log) ?? DateTime.now();
                      final headerKey = _getRelativeDateHeader(dt);
                      groupedLogs.putIfAbsent(headerKey, () => []).add(log);
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: groupedLogs.entries.map((group) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 10.0, bottom: 8.0),
                              child: Row(
                                children: [
                                  Text(
                                    group.key.toUpperCase(),
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
                              itemCount: group.value.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final log = group.value[index];
                                LeadAudio? matchedAudio;
                                final logDt = _parseCallLogDateTime(log);
                                final logMs = logDt?.millisecondsSinceEpoch ?? 0;
                                if (logMs > 0 && realAudios.isNotEmpty) {
                                  final logBoundUpper = log.bound.trim().toUpperCase();
                                  final logIsIn = logBoundUpper.startsWith('IN');
                                  final logDurSec = int.tryParse(log.duration.replaceAll(RegExp(r'\D'), '')) ?? 0;
                                  int? bestDiffMs;
                                  for (final a in realAudios) {
                                    final aBoundUpper = (a.bound ?? '').trim().toUpperCase();
                                    if (aBoundUpper.isNotEmpty && logBoundUpper.isNotEmpty) {
                                      final aIsIn = aBoundUpper.startsWith('IN');
                                      if (aIsIn != logIsIn) continue;
                                    }
                                    final aDt = _parseAudioDateTime(a);
                                    final aMs = aDt.millisecondsSinceEpoch;
                                    final aEndMs = a.durationSeconds > 0
                                        ? aMs + a.durationSeconds * 1000
                                        : aMs;
                                    final isNear = (aMs - logMs).abs() <= 3000 ||
                                        (logDurSec > 0 &&
                                            logMs >= aMs - 2500 &&
                                            logMs <= aEndMs + 2500);
                                    if (isNear) {
                                      final diff = (aMs - logMs).abs();
                                      if (bestDiffMs == null || diff < bestDiffMs) {
                                        bestDiffMs = diff;
                                        matchedAudio = a;
                                      }
                                    }
                                  }
                                }
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
            ] else ...[
              // === TAB 1: AUDIO RECORDINGS (from /audios) ===
              Row(
                children: [
                  Expanded(
                    child: _buildCallLogSummaryCard(
                      'Total Audios',
                      totalAudiosCount.toString(),
                      Icons.audiotrack,
                      Colors.indigo,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildCallLogSummaryCard(
                      'Total Size',
                      _formatAudioSize(totalAudioBytes),
                      Icons.storage,
                      Colors.teal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _buildCallLogSummaryCard(
                      'Inbound Audio',
                      inboundAudiosCount.toString(),
                      Icons.call_received,
                      Colors.green,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildCallLogSummaryCard(
                      'Outbound Audio',
                      outboundAudiosCount.toString(),
                      Icons.call_made,
                      Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Audio Recordings (${realAudios.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: (_isRefreshing || state.isAudiosLoading)
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          )
                        : const Icon(Icons.refresh, color: AppColors.primary),
                    tooltip: 'Refresh Audio Recordings',
                    onPressed: (_isRefreshing || state.isAudiosLoading) ? null : _handleRefresh,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (state.isAudiosLoading && realAudios.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  alignment: Alignment.center,
                  child: const SpinningLogo(size: 40),
                )
              else if (state.audiosError != null && realAudios.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      Text(
                        'Failed to load audio recordings: ${state.audiosError}',
                        style: const TextStyle(color: AppColors.primary, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                        onPressed: _handleRefresh,
                      ),
                    ],
                  ),
                )
              else if (realAudios.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  alignment: Alignment.center,
                  child: const Text(
                    'No audio recordings found for this lead.',
                    style: TextStyle(color: AppColors.textHint, fontSize: 15),
                  ),
                )
              else
                Builder(
                  builder: (context) {
                    final Map<String, List<LeadAudio>> groupedAudios = {};
                    for (final audio in realAudios) {
                      final dt = _parseAudioDateTime(audio);
                      final headerKey = _getRelativeDateHeader(dt);
                      groupedAudios.putIfAbsent(headerKey, () => []).add(audio);
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: groupedAudios.entries.map((group) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 10.0, bottom: 8.0),
                              child: Row(
                                children: [
                                  Text(
                                    group.key.toUpperCase(),
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
                              itemCount: group.value.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final audio = group.value[index];
                                return _buildAudioListItem(audio, state);
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
    final isMissed = cardData.isMissed;
    final isUnanswered = cardData.isUnanswered;
    final isIncoming = cardData.isIncoming;
    
    IconData icon;
    Color iconColor;
    
    if (isMissed) {
      icon = Icons.phone_missed_rounded;
      iconColor = const Color(0xFFDC2626);
    } else if (isUnanswered) {
      icon = Icons.call_missed_outgoing_rounded;
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
      statusPillText = 'MISSED';
      statusPillTextColor = const Color(0xFFDC2626);
      statusPillBgColor = const Color(0xFFFEF2F2);
      statusPillBorderColor = const Color(0xFFFCA5A5);
    } else if (isUnanswered) {
      statusPillText = 'UNANSWERED';
      statusPillTextColor = const Color(0xFFD97706);
      statusPillBgColor = const Color(0xFFFFFBEB);
      statusPillBorderColor = const Color(0xFFFCD34D);
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
                                isIncoming
                                    ? (cardData.fromPhone.isNotEmpty && cardData.fromPhone != 'Lead' && cardData.fromPhone != 'Me'
                                        ? cardData.fromPhone
                                        : (log.fromNumber.isNotEmpty ? log.fromNumber : state.leadDetail.phone))
                                    : (cardData.toPhone.isNotEmpty && cardData.toPhone != 'Lead' && cardData.toPhone != 'Me'
                                        ? cardData.toPhone
                                        : (log.toNumber.isNotEmpty ? log.toNumber : state.leadDetail.phone)),
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
    final isMissed = data.isMissed;
    final isUnanswered = data.isUnanswered;

    Color iconBgColor;
    Color iconColor;
    IconData cardIcon;

    if (isMissed) {
      cardIcon = Icons.phone_missed_rounded;
      iconBgColor = const Color(0xFFFEE2E2);
      iconColor = const Color(0xFFDC2626);
    } else if (isUnanswered) {
      cardIcon = Icons.call_missed_outgoing_rounded;
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
          if (hasAudio) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.borderEnabled),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Play Button
                InkWell(
                  onTap: _loadingAudioId == data.audio!.id ? null : () => _playLeadAudio(data.audio!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_loadingAudioId == data.audio!.id) ...[
                          const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text('Loading...', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ] else ...[
                          const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 3),
                          const Text('Play', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
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

      final candidateUrls = _buildOrderedAudioCandidates(audio);

      bool downloaded = false;
      for (final entry in candidateUrls) {
        final downloadUrl = entry.value;
        try {
          debugPrint('Attempting download: $downloadUrl');
          final response = await sl<ApiClient>().download(downloadUrl, tempFile.path);
          if (response.statusCode == 200 && await tempFile.exists() && (await tempFile.length()) > 0) {
            _workingAudioUrlTemplate = entry.key;
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
      final leadPhones = _collectUsableLeadPhones(widget.state.leadDetail);
      final phonesToSearch = <String>{...leadPhones};
      if (phonesToSearch.isEmpty) {
        if (AutoCallRecordingUploader.isUsablePhone(audio.fromNumber)) {
          phonesToSearch.add(audio.fromNumber!.trim());
        }
        if (AutoCallRecordingUploader.isUsablePhone(audio.toNumber)) {
          phonesToSearch.add(audio.toNumber!.trim());
        }
      } else {
        for (final candidate in [audio.fromNumber, audio.toNumber]) {
          if (AutoCallRecordingUploader.isUsablePhone(candidate) &&
              leadPhones.any((lp) => AutoCallRecordingUploader.phonesMatch(candidate, lp))) {
            phonesToSearch.add(candidate!.trim());
          }
        }
      }

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
    if (_loadingAudioId != null) return;
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

    setState(() {
      _loadingAudioId = audio.id;
    });

    void handleDurationFound(int seconds) {
      if (mounted && seconds > 0) {
        if (_resolvedAudioDurations[audio.id] != seconds) {
          setState(() {
            _resolvedAudioDurations[audio.id] = seconds;
          });
        }
      }
    }

    bool dialogShown = false;
    try {
      // 1. Check if recording exists locally on device
      final localFile = await _findLocalDeviceRecording(audio);
      if (localFile != null) {
        if (!mounted) return;
        debugPrint('Playing local device recording: ${localFile.path}');
        if (mounted) {
          setState(() {
            _loadingAudioId = null;
          });
        }
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
      dialogShown = true;

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
        final candidateUrls = _buildOrderedAudioCandidates(
          audio,
          includeFallbackStreamPaths: true,
        );

        for (final entry in candidateUrls) {
          final downloadUrl = entry.value;
          debugPrint('Downloading audio file from: $downloadUrl to ${tempFile.path}');
          try {
            await sl<ApiClient>().download(
              downloadUrl,
              tempFile.path,
            );
            if (await tempFile.exists() && await _checkAudioFileValid(tempFile)) {
              _workingAudioUrlTemplate = entry.key;
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
      if (dialogShown) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }

      if (downloaded && await tempFile.exists() && await _checkAudioFileValid(tempFile)) {
        if (!mounted) return;
        if (mounted) {
          setState(() {
            _loadingAudioId = null;
          });
        }
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
      if (dialogShown) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }
      debugPrint('Play error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load recording ${audio.displayName}'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } finally {
      if (mounted && _loadingAudioId != null) {
        setState(() {
          _loadingAudioId = null;
        });
      }
    }
  }
}

class _CallCardData {
  final LeadAudio? audio;
  final DateTime timestamp;
  final bool isIncoming;
  final bool isMissed;
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
    this.isMissed = false,
    this.isUnanswered = false,
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
