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
import 'package:crm_mobile/core/services/call_history_storage.dart';
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
  List<Map<String, dynamic>> _localRecordings = [];
  bool _localRecordingsFetched = false;
  final Map<String, String> _resolvedCallTypes = {};
  final Map<String, int> _resolvedAudioDurations = {};
  List<LeadCallLog> _localCallLogs = [];

  Future<void> _fetchLocalRecordings(String leadPhone) async {
    try {
      final recordings = await CallRecordingService().getAllSystemRecordings(leadPhone);
      final trackedCallHistory = await CallHistoryStorage.loadCallHistory();
      final systemCallLogs = await CallRecordingService().getSystemCallLogs(leadPhone);

      final cleanLeadPhone = leadPhone.replaceAll(RegExp(r'\D'), '');
      final leadLast10 = cleanLeadPhone.length >= 10 ? cleanLeadPhone.substring(cleanLeadPhone.length - 10) : cleanLeadPhone;

      final List<LeadCallLog> localLogs = [];

      for (final h in trackedCallHistory) {
        final hPhoneDigits = h.phoneNumber.replaceAll(RegExp(r'\D'), '');
        final hLast10 = hPhoneDigits.length >= 10 ? hPhoneDigits.substring(hPhoneDigits.length - 10) : hPhoneDigits;
        if (leadLast10.isNotEmpty && (hLast10 == leadLast10 || hPhoneDigits.contains(leadLast10))) {
          final dt = DateTime.fromMillisecondsSinceEpoch(h.startTime > 0 ? h.startTime : h.timestamp);
          final timeStr = DateFormat('HH:mm:ss').format(dt);
          final dateStr = DateFormat('yyyy-MM-dd').format(dt);
          localLogs.add(LeadCallLog(
            id: 'local_hist_${h.id}',
            leadId: widget.state.leadDetail.id,
            bound: h.callType.toUpperCase() == 'INCOMING' ? 'IN' : 'OUT',
            startTime: timeStr,
            endTime: timeStr,
            fromNumber: h.appUserPhone ?? '',
            toNumber: h.phoneNumber,
            duration: '${h.durationSeconds}s',
            callDate: dateStr,
            callStatus: h.callStatus,
            createdAt: dt.toIso8601String(),
          ));
        }
      }

      for (final sys in systemCallLogs) {
        final num = sys['phoneNumber']?.toString() ?? '';
        final cleanNum = num.replaceAll(RegExp(r'\D'), '');
        final callLast10 = cleanNum.length >= 10 ? cleanNum.substring(cleanNum.length - 10) : cleanNum;
        if (leadLast10.isNotEmpty && (callLast10 == leadLast10 || cleanNum.contains(leadLast10))) {
          final st = sys['startTime'] as int? ?? 0;
          if (st > 0) {
            final dt = DateTime.fromMillisecondsSinceEpoch(st);
            final timeStr = DateFormat('HH:mm:ss').format(dt);
            final dateStr = DateFormat('yyyy-MM-dd').format(dt);
            final durSec = sys['durationSeconds'] as int? ?? 0;
            final isIncoming = (sys['callType']?.toString() ?? '').toUpperCase() == 'INCOMING';
            localLogs.add(LeadCallLog(
              id: 'local_sys_${sys['id']}',
              leadId: widget.state.leadDetail.id,
              bound: isIncoming ? 'IN' : 'OUT',
              startTime: timeStr,
              endTime: timeStr,
              fromNumber: sys['fromNumber']?.toString() ?? (isIncoming ? leadPhone : 'Me'),
              toNumber: sys['toNumber']?.toString() ?? (isIncoming ? 'Me' : leadPhone),
              duration: '${durSec}s',
              callDate: dateStr,
              callStatus: sys['callStatus']?.toString() ?? (isIncoming ? 'MISSED' : 'UNANSWERED'),
              createdAt: dt.toIso8601String(),
            ));
          }
        }
      }

      if (mounted) {
        setState(() {
          _localRecordings = recordings;
          _localCallLogs = localLogs;
        });
      }
    } catch (e) {
      debugPrint('Error fetching local recordings for call log: $e');
    }
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

    if (audio.bound != null && audio.bound!.isNotEmpty) {
      final b = audio.bound!.toUpperCase();
      if (b == 'IN' || b == 'INBOUND' || b == 'INCOMING' || b.contains('IN')) {
        _resolvedCallTypes[audio.id] = 'inbound';
        return 'inbound';
      }
      if (b == 'OUT' || b == 'OUTBOUND' || b == 'OUTGOING' || b.contains('OUT')) {
        _resolvedCallTypes[audio.id] = 'outbound';
        return 'outbound';
      }
    }

    _resolvedCallTypes[audio.id] = 'outbound';
    return 'outbound';
  }

  int _getEffectiveTimestamp(LeadAudio audio) {
    if (audio.createdAt != null && audio.createdAt!.millisecondsSinceEpoch > 0) {
      return audio.createdAt!.millisecondsSinceEpoch;
    }
    if (audio.startTimeStr != null && audio.startTimeStr!.isNotEmpty) {
      final parsed = _parseTimeStringToMs(audio.startTimeStr);
      if (parsed > 0) return parsed;
    }
    // Try 13-digit epoch ms timestamp
    final match = RegExp(r'(\d{13})').firstMatch('${audio.fileName}_${audio.displayName}');
    if (match != null) {
      final val = int.tryParse(match.group(1)!);
      if (val != null && val > 1500000000000) return val;
    }
    // Try YYYYMMDD_HHMMSS pattern from fileName/displayName (e.g. Call_+918925966055_20260929_163257.m4a)
    final combined = '${audio.fileName}_${audio.displayName}';
    final dateTimeMatch = RegExp(r'(?:^|[^0-9])(20[2-3]\d)(\d{2})(\d{2})[_\-]?(\d{2})(\d{2})(\d{2})(?:$|[^0-9])').firstMatch(combined);
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
    return 0;
  }

  int _parseTimeStringToMs(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty || timeStr == 'null' || timeStr == '--:--') return 0;
    try {
      if (timeStr.contains('T')) {
        return DateTime.parse(timeStr).toLocal().millisecondsSinceEpoch;
      }
      final now = DateTime.now();
      final datePart = DateFormat('yyyy-MM-dd').format(now);
      if (timeStr.toUpperCase().contains('AM') || timeStr.toUpperCase().contains('PM')) {
        final parsed = DateFormat('yyyy-MM-dd hh:mm:ss a').parse('$datePart $timeStr');
        return parsed.millisecondsSinceEpoch;
      } else {
        final parsed = DateFormat('yyyy-MM-dd HH:mm:ss').parse('$datePart $timeStr');
        return parsed.millisecondsSinceEpoch;
      }
    } catch (_) {
      try {
        final now = DateTime.now();
        final datePart = DateFormat('yyyy-MM-dd').format(now);
        if (timeStr.toUpperCase().contains('AM') || timeStr.toUpperCase().contains('PM')) {
          final parsed = DateFormat('yyyy-MM-dd hh:mm a').parse('$datePart $timeStr');
          return parsed.millisecondsSinceEpoch;
        } else {
          final parsed = DateFormat('yyyy-MM-dd HH:mm').parse('$datePart $timeStr');
          return parsed.millisecondsSinceEpoch;
        }
      } catch (_) {}
    }
    return 0;
  }

  String? _formatTimeString(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty || timeStr == 'null' || timeStr == '--:--') return null;
    try {
      if (timeStr.contains('T')) {
        final dt = DateTime.parse(timeStr).toLocal();
        return DateFormat('hh:mm:ss a').format(dt);
      }
      final now = DateTime.now();
      final datePart = DateFormat('yyyy-MM-dd').format(now);
      if (timeStr.toUpperCase().contains('AM') || timeStr.toUpperCase().contains('PM')) {
        final dt = DateFormat('yyyy-MM-dd hh:mm:ss a').parse('$datePart $timeStr');
        return DateFormat('hh:mm:ss a').format(dt);
      } else {
        final dt = DateFormat('yyyy-MM-dd HH:mm:ss').parse('$datePart $timeStr');
        return DateFormat('hh:mm:ss a').format(dt);
      }
    } catch (_) {
      try {
        final now = DateTime.now();
        final datePart = DateFormat('yyyy-MM-dd').format(now);
        if (timeStr.toUpperCase().contains('AM') || timeStr.toUpperCase().contains('PM')) {
          final dt = DateFormat('yyyy-MM-dd hh:mm a').parse('$datePart $timeStr');
          return DateFormat('hh:mm:ss a').format(dt);
        } else {
          final dt = DateFormat('yyyy-MM-dd HH:mm').parse('$datePart $timeStr');
          return DateFormat('hh:mm:ss a').format(dt);
        }
      } catch (_) {}
    }
    return timeStr;
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
    if (log.createdAt.isNotEmpty) {
      try {
        return DateTime.parse(log.createdAt).toLocal();
      } catch (_) {}
    }

    if (log.startTime.isNotEmpty) {
      try {
        return DateTime.parse(log.startTime).toLocal();
      } catch (_) {}
    }

    if (log.callDate.isNotEmpty) {
      final dateStr = log.callDate.trim();
      final timeStr = log.startTime.trim();
      if (timeStr.isNotEmpty) {
        final combined = '$dateStr $timeStr';
        try {
          if (timeStr.toUpperCase().contains('AM') || timeStr.toUpperCase().contains('PM')) {
            return DateFormat('yyyy-MM-dd hh:mm:ss a').parse(combined);
          } else {
            return DateFormat('yyyy-MM-dd HH:mm:ss').parse(combined);
          }
        } catch (_) {
          try {
            if (timeStr.toUpperCase().contains('AM') || timeStr.toUpperCase().contains('PM')) {
              return DateFormat('yyyy-MM-dd hh:mm a').parse(combined);
            } else {
              return DateFormat('yyyy-MM-dd HH:mm').parse(combined);
            }
          } catch (_) {}
        }
      }
      try {
        return DateTime.parse(dateStr).toLocal();
      } catch (_) {}
    }

    return null;
  }

  LeadAudio? _findMatchingAudioForCallLog(LeadCallLog log, List<LeadAudio>? serverAudios, String leadPhone) {
    final statusUpper = log.callStatus.toUpperCase();
    final hasExplicitMissedStatus = statusUpper == 'MISSED' ||
        statusUpper == 'REJECTED' ||
        statusUpper == 'UNANSWERED' ||
        statusUpper == 'NOT_CONNECTED';
    // Only check duration when there's no explicit connected/answered status
    final hasZeroDuration = log.duration == '0s' || log.duration == '0' || log.duration == '00:00:00';
    final isUnansweredLog = hasExplicitMissedStatus ||
        (statusUpper != 'CONNECTED' && statusUpper != 'ANSWERED' && statusUpper.isEmpty && (hasZeroDuration || log.duration.trim().isEmpty));

    if (isUnansweredLog) {
      return null;
    }

    final logDt = _parseCallLogDateTime(log);
    final logBoundUpper = log.bound.toUpperCase();

    if (serverAudios != null && serverAudios.isNotEmpty) {
      LeadAudio? bestMatch;
      int minDiffMs = 1000 * 60 * 30; // 30 minutes window

      for (final audio in serverAudios) {
        if (audio.size <= 0) continue;

        final audioMs = _getEffectiveTimestamp(audio);
        if (audioMs <= 0) continue;

        if (logDt != null) {
          final diffMs = (audioMs - logDt.millisecondsSinceEpoch).abs();
          if (diffMs < minDiffMs) {
            final audioType = _getResolvedCallType(audio, leadPhone).toUpperCase();
            final audioBound = (audio.bound ?? '').toUpperCase();
            
            bool isDirectionMatch = true;
            if (logBoundUpper == 'IN') {
              isDirectionMatch = audioBound.contains('IN') || audioType == 'INBOUND' || audioType == 'IN';
            } else if (logBoundUpper == 'OUT') {
              isDirectionMatch = audioBound.contains('OUT') || audioType == 'OUTBOUND' || audioType == 'OUT';
            }

            if (isDirectionMatch) {
              minDiffMs = diffMs;
              bestMatch = audio;
            }
          }
        }
      }

      if (bestMatch != null) return bestMatch;

      // Fallback 1: match audio on same date with direction match
      if (logDt != null) {
        for (final audio in serverAudios) {
          if (audio.size <= 0) continue;
          final audioMs = _getEffectiveTimestamp(audio);
          if (audioMs <= 0) continue;
          final audioDt = DateTime.fromMillisecondsSinceEpoch(audioMs);
          if (audioDt.year == logDt.year && audioDt.month == logDt.month && audioDt.day == logDt.day) {
            final audioType = _getResolvedCallType(audio, leadPhone).toUpperCase();
            final audioBound = (audio.bound ?? '').toUpperCase();
            bool isDirectionMatch = true;
            if (logBoundUpper == 'IN') {
              isDirectionMatch = audioBound.contains('IN') || audioType == 'INBOUND' || audioType == 'IN';
            } else if (logBoundUpper == 'OUT') {
              isDirectionMatch = audioBound.contains('OUT') || audioType == 'OUTBOUND' || audioType == 'OUT';
            }
            if (isDirectionMatch) return audio;
          }
        }

        // Fallback 2: any server audio on same date
        for (final audio in serverAudios) {
          if (audio.size <= 0) continue;
          final audioMs = _getEffectiveTimestamp(audio);
          if (audioMs <= 0) continue;
          final audioDt = DateTime.fromMillisecondsSinceEpoch(audioMs);
          if (audioDt.year == logDt.year && audioDt.month == logDt.month && audioDt.day == logDt.day) {
            return audio;
          }
        }
      }

      // Fallback 3: if single server audio exists for lead
      if (serverAudios.length == 1 && serverAudios.first.size > 0) {
        return serverAudios.first;
      }
    }

    // Fallback 4: Check local recordings on phone storage
    if (_localRecordings.isNotEmpty) {
      for (final local in _localRecordings) {
        final localPath = local['path']?.toString() ?? '';
        if (localPath.isEmpty || !File(localPath).existsSync()) continue;
        final fileSize = File(localPath).lengthSync();
        if (fileSize <= 0) continue;

        final localTs = local['timestamp'] as int? ?? 0;
        final localName = localPath.split('/').last.split('\\').last;

        if (logDt != null && localTs > 0) {
          final diff = (localTs - logDt.millisecondsSinceEpoch).abs();
          if (diff < 1000 * 60 * 30) { // 30 minutes tolerance
            return LeadAudio(
              id: 'local_$localTs',
              leadId: log.leadId,
              fileName: localPath,
              originalFileName: localName,
              contentType: 'audio/mp3',
              size: fileSize,
              createdAt: DateTime.fromMillisecondsSinceEpoch(localTs),
              durationSeconds: local['duration'] as int? ?? 0,
              bound: log.bound,
            );
          }
        }
      }
    }

    return null;
  }

  _CallCardData _buildCallCardDataFromLog(LeadCallLog log, List<LeadAudio>? serverAudios, String leadPhone) {
    final statusUpper = log.callStatus.toUpperCase();
    final hasExplicitMissedStatus = statusUpper == 'MISSED' ||
        statusUpper == 'REJECTED' ||
        statusUpper == 'UNANSWERED' ||
        statusUpper == 'NOT_CONNECTED';
    final hasZeroDuration = log.duration == '0s' || log.duration == '0' || log.duration == '00:00:00';
    final isMissed = hasExplicitMissedStatus ||
        (statusUpper != 'CONNECTED' && statusUpper != 'ANSWERED' && statusUpper.isEmpty && (hasZeroDuration || log.duration.trim().isEmpty));

    final matchedAudio = isMissed ? null : _findMatchingAudioForCallLog(log, serverAudios, leadPhone);

    final isIncoming = log.bound.toUpperCase() == 'IN';
    
    String displayStartTime = _formatTimeString(log.startTime) ?? '--:--';
    String displayEndTime = _formatTimeString(log.endTime) ?? '--:--';

    if (matchedAudio != null) {
      if (matchedAudio.startTimeStr != null && matchedAudio.startTimeStr!.isNotEmpty && matchedAudio.startTimeStr != 'null' && matchedAudio.startTimeStr != '--:--') {
        final formatted = _formatTimeString(matchedAudio.startTimeStr);
        if (formatted != null && formatted.isNotEmpty) displayStartTime = formatted;
      }
      if (matchedAudio.endTimeStr != null && matchedAudio.endTimeStr!.isNotEmpty && matchedAudio.endTimeStr != 'null' && matchedAudio.endTimeStr != '--:--') {
        final formatted = _formatTimeString(matchedAudio.endTimeStr);
        if (formatted != null && formatted.isNotEmpty) displayEndTime = formatted;
      }
    }
    
    String dateStr = log.callDate;
    try {
      if (log.startTime.isNotEmpty) {
        final dt = DateTime.parse(log.startTime).toLocal();
        dateStr = DateFormat('MMM dd, yyyy').format(dt);
      }
    } catch (_) {}

    String sizeStr = 'No Audio';
    if (!isMissed && matchedAudio != null && matchedAudio.size > 0) {
      final kb = matchedAudio.size / 1024;
      final mb = kb / 1024;
      sizeStr = mb >= 1 ? '${mb.toStringAsFixed(1)} MB' : '${kb.toStringAsFixed(0)} KB';
    }

    final title = isMissed 
        ? (isIncoming ? 'Missed Call' : 'Unanswered Call')
        : (matchedAudio != null ? _cleanAudioTitle(matchedAudio.displayName, isIncoming: isIncoming, isUnanswered: isMissed) : (isIncoming ? 'Incoming Call' : 'Outgoing Call'));

    DateTime logTimestamp = DateTime.now();
    try {
      if (log.startTime.isNotEmpty) {
        logTimestamp = DateTime.parse(log.startTime).toLocal();
      }
    } catch (_) {}

    String durStr = isMissed ? '' : log.duration;
    if (!isMissed && durStr.isEmpty && matchedAudio != null && matchedAudio.durationSeconds > 0) {
      durStr = _formatDuration(matchedAudio.durationSeconds);
    }

    return _CallCardData(
      audio: (matchedAudio != null && matchedAudio.size > 0 && !isMissed) ? matchedAudio : null,
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

  String _formatCallLogDisplayTime(LeadCallLog log) {
    final parsedDt = _parseCallLogDateTime(log);
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

    if (state.isCallLogsLoading || state.callLogs == null) {
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
    final List<LeadCallLog> effectiveCallHistory = [...callLogs.callHistory];

    for (final localLog in _localCallLogs) {
      final localDt = _parseCallLogDateTime(localLog);
      if (localDt == null) continue;
      final localMs = localDt.millisecondsSinceEpoch;

      bool existsInServer = false;
      for (final sLog in callLogs.callHistory) {
        final sDt = _parseCallLogDateTime(sLog);
        if (sDt != null && (sDt.millisecondsSinceEpoch - localMs).abs() < 90000) {
          existsInServer = true;
          break;
        }
      }

      if (!existsInServer) {
        effectiveCallHistory.add(localLog);
      }
    }

    effectiveCallHistory.sort((a, b) {
      final dtA = _parseCallLogDateTime(a) ?? DateTime(1970);
      final dtB = _parseCallLogDateTime(b) ?? DateTime(1970);
      return dtB.compareTo(dtA);
    });

    if (effectiveCallHistory.isEmpty) {
      return const Center(
        child: Text(
          'No call logs found for this lead.',
          style: TextStyle(color: AppColors.textHint, fontSize: 16),
        ),
      );
    }

    final totalCallsCount = effectiveCallHistory.length;
    final totalInboundCount = effectiveCallHistory.where((l) => l.bound.toUpperCase() == 'IN').length;
    final totalOutboundCount = effectiveCallHistory.where((l) => l.bound.toUpperCase() == 'OUT').length;
    final totalMissedCount = effectiveCallHistory.where((l) {
      final st = l.callStatus.toUpperCase();
      return st == 'MISSED' || st == 'REJECTED' || st == 'UNANSWERED' || st == 'NOT_CONNECTED';
    }).length;

    return SingleChildScrollView(
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
              const SizedBox(width: 8),
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
          const SizedBox(height: 8),
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
              const SizedBox(width: 8),
              Expanded(
                child: _buildCallLogSummaryCard(
                  'Outbound',
                  totalOutboundCount.toString(),
                  Icons.call_made,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
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
          const SizedBox(height: 16),
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
                  context.read<LeadsBloc>().add(FetchLeadCallLogs(widget.state.leadDetail.id));
                  context.read<LeadsBloc>().add(FetchLeadAudios(widget.state.leadDetail.id));
                  _fetchLocalRecordings(widget.state.leadDetail.phone);
                  AutoCallRecordingUploader.autoScanAndUploadLeadRecordings(
                    context: context,
                    leadId: widget.state.leadDetail.id,
                    phoneNumber: widget.state.leadDetail.phone,
                    existingServerAudios: widget.state.audios,
                    onUploadSuccess: () {
                      if (mounted) {
                        context.read<LeadsBloc>().add(FetchLeadAudios(widget.state.leadDetail.id));
                        context.read<LeadsBloc>().add(FetchLeadCallLogs(widget.state.leadDetail.id));
                      }
                    },
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Refreshing call logs...'),
                      duration: Duration(seconds: 1),
                      backgroundColor: AppColors.primary,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          Builder(
            builder: (context) {
              // Group call logs by relative date header (Today, Yesterday, Date)
              final Map<String, List<LeadCallLog>> groupedLogs = {};
              for (final log in effectiveCallHistory) {
                final dt = _parseCallLogDateTime(log) ?? DateTime.now();
                final headerKey = _getRelativeDateHeader(dt);
                groupedLogs.putIfAbsent(headerKey, () => []).add(log);
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: groupedLogs.entries.map((group) {
                  final headerKey = group.key;
                  final groupList = group.value;

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
                          return _buildCallLogListItem(log, state);
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
    );
  }

  Widget _buildCallLogSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallLogListItem(LeadCallLog log, LeadDetailsLoaded state) {
    final isExpanded = _expandedCallLogIds.contains(log.id);
    final isIncoming = log.bound.toUpperCase() == 'IN';
    final statusUpper = log.callStatus.toUpperCase();
    final hasExplicitMissedStatus = statusUpper == 'MISSED' ||
        statusUpper == 'REJECTED' ||
        statusUpper == 'UNANSWERED' ||
        statusUpper == 'NOT_CONNECTED';
    final hasZeroDuration = log.duration == '0s' || log.duration == '0' || log.duration == '00:00:00';
    final isMissed = hasExplicitMissedStatus ||
        (statusUpper != 'CONNECTED' && statusUpper != 'ANSWERED' && statusUpper.isEmpty && (hasZeroDuration || log.duration.trim().isEmpty));
    
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

    // Format date and time relatively (Today, Yesterday, Sep 28)
    final parsedDt = _parseCallLogDateTime(log);
    final displayDateTime = parsedDt != null ? _formatCallLogDisplayTime(log) : (log.callDate.isNotEmpty ? log.callDate : 'Unknown Date');

    final cardData = _buildCallCardDataFromLog(log, state.audios, state.leadDetail.phone);
    final displayDuration = isMissed ? 'Unanswered' : (log.duration.isNotEmpty ? log.duration : '0s');

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
                              style: TextStyle(
                                fontSize: 13,
                                color: isMissed ? const Color(0xFFD97706) : AppColors.textSecondary,
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
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.borderEnabled),
                                    ),
                                    child: Text(
                                      log.callStatus,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w600,
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
                      onTap: () => _playLeadAudio(context, data.audio!),
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

  void _playLeadAudio(BuildContext context, LeadAudio audio) async {
    void handleDurationFound(int seconds) {
      if (mounted && seconds > 0) {
        if (_resolvedAudioDurations[audio.id] != seconds) {
          setState(() {
            _resolvedAudioDurations[audio.id] = seconds;
          });
        }
      }
    }

    // 1. Check if audio.fileName is directly a local file path
    if (audio.fileName.isNotEmpty && File(audio.fileName).existsSync()) {
      debugPrint('Playing audio.fileName directly: ${audio.fileName}');
      CallRecordingService().playRecording(audio.fileName, context: context, title: audio.displayName, onDurationFound: handleDurationFound);
      return;
    }

    // 2. Play local phone recording directly if exact matching file exists in _localRecordings
    final cleanServerName = AutoCallRecordingUploader.cleanFileName(audio.displayName.toLowerCase());
    final rawFileName = audio.fileName.toLowerCase();
    if (cleanServerName.isNotEmpty || rawFileName.isNotEmpty) {
      for (final local in _localRecordings) {
        final localPath = local['path']?.toString() ?? '';
        if (localPath.isNotEmpty && File(localPath).existsSync() && File(localPath).lengthSync() > 0) {
          final localName = AutoCallRecordingUploader.cleanFileName(localPath.split('/').last.split('\\').last.toLowerCase());
          final lowerPath = localPath.toLowerCase();
          
          final isExactMatch = (rawFileName.isNotEmpty && (lowerPath.contains(rawFileName) || localName == rawFileName)) ||
                               (cleanServerName.length >= 10 && localName == cleanServerName);

          if (isExactMatch) {
            debugPrint('Playing matched local phone recording directly: $localPath');
            CallRecordingService().playRecording(localPath, context: context, title: audio.displayName, onDurationFound: handleDurationFound);
            return;
          }
        }
      }
    }

    // 3. Download from server with full BASE_URL if not local
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
      final displayFileName = audio.displayName.isNotEmpty ? audio.displayName : 'audio_${audio.id}.mp3';
      final sanitizedName = displayFileName.replaceAll(RegExp(r'[^\w.\- ]'), '_');
      final tempFile = File('${tempDir.path}/audio_${audio.id}_$sanitizedName');

      bool downloaded = false;
      if (await tempFile.exists() && (await tempFile.length()) > 0) {
        downloaded = true;
      } else {
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

        for (final downloadUrl in candidateUrls) {
          debugPrint('Downloading audio file from: $downloadUrl to ${tempFile.path}');
          try {
            await sl<ApiClient>().download(
              downloadUrl,
              tempFile.path,
            );
            if (await tempFile.exists() && (await tempFile.length()) > 0) {
              downloaded = true;
              break;
            }
          } catch (e) {
            debugPrint('Failed download candidate $downloadUrl: $e');
          }
        }
      }

      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

      if (downloaded && await tempFile.exists() && (await tempFile.length()) > 0 && context.mounted) {
        CallRecordingService().playRecording(tempFile.path, context: context, title: audio.displayName, onDurationFound: handleDurationFound);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load recording ${audio.displayName}'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      debugPrint('Play error: $e');
      if (context.mounted) {
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
