import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/blocs/leads_event.dart';
import 'package:crm_mobile/blocs/leads_state.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/models/lead_detail.dart';
import 'package:crm_mobile/models/attachment.dart';
import 'package:crm_mobile/models/lead_audio.dart';
import 'package:crm_mobile/models/lead_call_log.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crm_mobile/core/services/call_recording_service.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_constants.dart';
import 'package:crm_mobile/models/call_history.dart';
import 'package:crm_mobile/core/services/call_history_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';
import 'package:crm_mobile/core/utils/staff_phone_resolver.dart';
import 'package:crm_mobile/screens/leads/add_lead_screen.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';
import 'package:crm_mobile/screens/followups/add_followup_screen.dart';

class LeadDetailsScreen extends StatelessWidget {
  final String leadId;
  final bool isActive;
  const LeadDetailsScreen({super.key, required this.leadId, this.isActive = true});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<LeadsBloc>()
        ..add(FetchLeadDetails(leadId))
        ..add(FetchLeadAudios(leadId))
        ..add(FetchLeadCallLogs(leadId)),
      child: LeadDetailsView(isActive: isActive),
    );
  }
}

class LeadDetailsView extends StatefulWidget {
  final bool isActive;
  const LeadDetailsView({super.key, this.isActive = true});

  @override
  State<LeadDetailsView> createState() => _LeadDetailsViewState();
}

class _LeadDetailsViewState extends State<LeadDetailsView> with WidgetsBindingObserver {
  int _activeTabIndex = 0;
  final List<String> _tabs = ['Overview', 'Activities', 'Call Logs', 'Documents'];
  final TextEditingController _noteController = TextEditingController();
  final Set<String> _expandedCallLogIds = {};
  
  List<Map<String, dynamic>> _localRecordings = [];
  List<CallHistory> _trackedCallHistory = [];
  List<LeadStatus> _availableStatuses = [];
  bool _isLoadingRecordings = false;
  bool _hasStoragePermission = true;
  bool _wasEdited = false;
  int? _lastCallTimestamp;
  final Map<String, String> _resolvedCallTypes = {};
  final Map<String, int> _resolvedAudioDurations = {};
  Future<List<dynamic>>? _callLogsFuture;
  String? _callLogsFuturePhone;
  bool _localRecordingsFetched = false;
  String? _autoUploadedLeadId;

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

    if (audio.hasExplicitDirection) {
      _resolvedCallTypes[audio.id] = audio.callType.toLowerCase();
      return audio.callType.toLowerCase();
    }

    if (_localRecordings.isNotEmpty) {
      final cleanServerName = AutoCallRecordingUploader.cleanFileName(audio.displayName.toLowerCase());
      for (final local in _localRecordings) {
        final localPath = local['path']?.toString() ?? '';
        final localName = AutoCallRecordingUploader.cleanFileName(localPath.split('/').last.split('\\').last.toLowerCase());
        final localType = local['callType']?.toString() ?? '';
        if (localType.isNotEmpty && (localName == cleanServerName || localPath.contains(cleanServerName))) {
          _resolvedCallTypes[audio.id] = localType.toLowerCase();
          return localType.toLowerCase();
        }
      }
    }

    final audioMs = _getEffectiveTimestamp(audio);

    // 1. Check tracked call history for matching call timestamp within 1 minute
    if (_trackedCallHistory.isNotEmpty && audioMs > 0) {
      final cleanLeadPhone = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
      final leadLast10 = cleanLeadPhone.length >= 10 ? cleanLeadPhone.substring(cleanLeadPhone.length - 10) : cleanLeadPhone;

      for (final c in _trackedCallHistory) {
        final cleanCPhone = c.phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
        final cLast10 = cleanCPhone.length >= 10 ? cleanCPhone.substring(cleanCPhone.length - 10) : cleanCPhone;

        final isPhoneMatch = cleanLeadPhone.isEmpty || cLast10 == leadLast10 || cleanCPhone.contains(leadLast10) || leadLast10.contains(cLast10);
        if (isPhoneMatch) {
          final diff1 = (c.timestamp - audioMs).abs();
          final diff2 = (c.startTime - audioMs).abs();

          if (diff1 < 60 * 1000 || diff2 < 60 * 1000) {
            final typeStr = c.callType.toLowerCase();
            final resolved = (typeStr == 'outgoing' || typeStr == 'outbound') ? 'outbound' : 'inbound';
            _resolvedCallTypes[audio.id] = resolved;
            return resolved;
          }
        }
      }
    }

    // 2. Check last call timestamp if user placed call in this session within 1 minute
    if (_lastCallTimestamp != null && audioMs > 0) {
      final diff = (audioMs - _lastCallTimestamp!).abs();
      if (diff < 60 * 1000) {
        _resolvedCallTypes[audio.id] = 'outbound';
        return 'outbound';
      }
    }

    _resolveAudioDirectionFromCallLog(audio, phoneNumber);

    final fallback = (audio.callType.isNotEmpty && audio.callType.toLowerCase() != 'unknown')
        ? audio.callType.toLowerCase()
        : 'inbound';
    _resolvedCallTypes[audio.id] = fallback;
    return fallback;
  }

  void _resolveAudioDirectionFromCallLog(LeadAudio audio, String phoneNumber) async {
    if (phoneNumber.isEmpty || _resolvedCallTypes.containsKey(audio.id)) return;
    final timestamp = _getEffectiveTimestamp(audio);
    try {
      final detected = await CallRecordingService().detectCallType(
        filePath: audio.fileName,
        fileName: audio.displayName,
        phoneNumber: phoneNumber,
        timestamp: timestamp,
        callTimestamp: _lastCallTimestamp ?? 0,
      );
      if (mounted && detected.isNotEmpty && _resolvedCallTypes[audio.id] != detected) {
        setState(() {
          _resolvedCallTypes[audio.id] = detected;
        });
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchLeadStatuses();
    StaffPhoneResolver.getOrFetchStaffPhone().then((phone) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noteController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lastCallTimestamp = null;
      final blocState = context.read<LeadsBloc>().state;
      if (blocState is LeadDetailsLoaded) {
        final lead = blocState.leadDetail;

        // Schedule multi-stage scans (0s, 3s, 7s, 15s) when returning from call to capture finalized recording
        for (final delaySec in [0, 3, 7, 15]) {
          Future.delayed(Duration(seconds: delaySec), () {
            if (!mounted) return;
            AutoCallRecordingUploader.autoScanAndUploadLeadRecordings(
              context: context,
              leadId: lead.id,
              phoneNumber: lead.phone,
              onUploadSuccess: () {
                if (mounted) {
                  context.read<LeadsBloc>().add(FetchLeadAudios(lead.id));
                  _fetchLocalRecordings(lead.phone);
                }
              },
            );
          });
        }
      }
    }
  }

  void _fetchLeadStatuses() async {
    final result = await sl<SettingsRepository>().getLeadStatuses();
    result.fold((_) {}, (statuses) {
      if (mounted) {
        setState(() {
          _availableStatuses = statuses;
        });
      }
    });
  }

  void _fetchLocalRecordings(String phoneNumber) async {
    if (_isLoadingRecordings) return;
    if (mounted) {
      setState(() {
        _isLoadingRecordings = true;
      });
    }

    try {
      final history = await CallHistoryStorage.loadCallHistory();
      final callRecordingService = CallRecordingService();
      bool hasPermission = await callRecordingService.hasStoragePermission();

      if (!mounted) return;
      setState(() {
        _hasStoragePermission = hasPermission;
        _trackedCallHistory = history;
      });

      if (hasPermission) {
        final paths = await callRecordingService.getAllSystemRecordings(phoneNumber);
        if (!mounted) return;
        setState(() {
          _localRecordings = paths;
        });
      }
    } catch (e) {
      debugPrint('Error fetching local recordings: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRecordings = false;
        });
      } else {
        _isLoadingRecordings = false;
      }
    }
  }

  String? _formatTimeString(String? rawTime) {
    if (rawTime == null || rawTime.isEmpty || rawTime == 'null' || rawTime == '--:--') return null;
    try {
      var clean = rawTime.trim();
      if (clean.contains('T')) {
        clean = clean.split('T').last;
      }
      if (clean.contains('AM') || clean.contains('PM') || clean.contains('am') || clean.contains('pm')) {
        return clean;
      }
      final parts = clean.split(':');
      if (parts.length >= 2) {
        final hh = int.tryParse(parts[0]) ?? 0;
        final mm = int.tryParse(parts[1]) ?? 0;
        final ss = parts.length > 2 ? (int.tryParse(parts[2].split('.')[0]) ?? 0) : 0;
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, hh, mm, ss);
        return DateFormat('hh:mm:ss a').format(dt);
      }
    } catch (_) {}
    return rawTime;
  }

  Map<String, String> _getCallCardDetails(
    LeadAudio audio,
    String leadPhone,
    bool isIncoming, {
    List<Map<String, dynamic>>? localRecordings,
    List<CallHistory>? trackedCalls,
    List<Map<String, dynamic>>? systemLogs,
  }) {
    String fromPhone = '';
    String toPhone = '';

    final prefs = sl.isRegistered<SharedPreferences>() ? sl<SharedPreferences>() : null;
    final savedName = prefs?.getString('userName')?.trim();
    final savedPhone = prefs?.getString('userPhone')?.trim();

    final staffUser = (savedPhone != null && savedPhone.isNotEmpty)
        ? savedPhone
        : ((savedName != null && savedName.isNotEmpty) ? savedName : 'Staff');

    final cleanLeadPhone = leadPhone.isNotEmpty ? leadPhone : 'Lead';

    if (audio.fromNumber != null && audio.fromNumber!.isNotEmpty && audio.fromNumber != 'null' && audio.fromNumber != 'Unknown') {
      fromPhone = audio.fromNumber!;
    }
    if (audio.toNumber != null && audio.toNumber!.isNotEmpty && audio.toNumber != 'null' && audio.toNumber != 'Unknown') {
      toPhone = audio.toNumber!;
    }

    if (fromPhone.isEmpty || fromPhone == 'Staff' || fromPhone == 'null' || fromPhone == 'Unknown') {
      if (isIncoming) {
        fromPhone = cleanLeadPhone;
      } else {
        fromPhone = staffUser;
      }
    }

    if (toPhone.isEmpty || toPhone == 'Staff' || toPhone == 'null' || toPhone == 'Unknown') {
      if (isIncoming) {
        toPhone = staffUser;
      } else {
        toPhone = cleanLeadPhone;
      }
    }

    String startStr = '--:--';
    String endStr = '--:--';
    String durationStr = '';

    final startDt = (audio.createdAt != null) ? audio.createdAt!.toLocal() : DateTime.now();
    startStr = DateFormat('hh:mm:ss a').format(startDt);

    DateTime baseStartDt = startDt;

    if (audio.startTimeStr != null && audio.startTimeStr!.isNotEmpty && audio.startTimeStr != 'null' && audio.startTimeStr != '--:--') {
      final formattedStart = _formatTimeString(audio.startTimeStr);
      if (formattedStart != null) startStr = formattedStart;

      final parts = audio.startTimeStr!.split(':');
      if (parts.length >= 2) {
        final hh = int.tryParse(parts[0]) ?? startDt.hour;
        final mm = int.tryParse(parts[1]) ?? startDt.minute;
        final ss = parts.length > 2 ? (int.tryParse(parts[2].split('.')[0]) ?? startDt.second) : 0;
        baseStartDt = DateTime(startDt.year, startDt.month, startDt.day, hh, mm, ss);
      }
    }

    if (audio.endTimeStr != null && audio.endTimeStr!.isNotEmpty && audio.endTimeStr != 'null' && audio.endTimeStr != '--:--') {
      final formattedEnd = _formatTimeString(audio.endTimeStr);
      if (formattedEnd != null) endStr = formattedEnd;
    }

    int durationSec = audio.durationSeconds;

    if (durationSec <= 0 && _resolvedAudioDurations.containsKey(audio.id)) {
      durationSec = _resolvedAudioDurations[audio.id]!;
    }

    if (durationSec <= 0) {
      final effectiveLocals = localRecordings ?? _localRecordings;
      if (effectiveLocals.isNotEmpty) {
        final cleanServerName = AutoCallRecordingUploader.cleanFileName(audio.displayName.toLowerCase());
        for (final local in effectiveLocals) {
          final localPath = local['path']?.toString() ?? '';
          final localName = AutoCallRecordingUploader.cleanFileName(localPath.split('/').last.split('\\').last.toLowerCase());
          final localDurMs = (local['durationMs'] as num?)?.toInt() ?? 0;
          final lowerPath = localPath.toLowerCase();
          final rawFileName = audio.fileName.toLowerCase();

          final isNameMatch = localName == cleanServerName || 
                              lowerPath.contains(cleanServerName) || 
                              (rawFileName.isNotEmpty && lowerPath.contains(rawFileName)) ||
                              cleanServerName.contains(localName);

          if (localDurMs > 0 && isNameMatch) {
            durationSec = (localDurMs / 1000).round();
            _resolvedAudioDurations[audio.id] = durationSec;
            break;
          }
        }
      }
    }

    final effectiveTracked = trackedCalls ?? _trackedCallHistory;
    if (durationSec <= 0 && effectiveTracked.isNotEmpty) {
      final audioMs = baseStartDt.millisecondsSinceEpoch;
      for (final c in effectiveTracked) {
        final diff1 = (c.timestamp - audioMs).abs();
        final diff2 = (c.startTime - audioMs).abs();
        if (diff1 < 60000 || diff2 < 60000) { // 1 minute tolerance
          if (c.durationSeconds > 0) {
            durationSec = c.durationSeconds;
          }
          break;
        }
      }
    }

    String sysStatus = '';
    if (systemLogs != null && systemLogs.isNotEmpty) {
      final audioMs = baseStartDt.millisecondsSinceEpoch;
      for (final sys in systemLogs) {
        final sysStart = sys['startTime'] as int? ?? 0;
        final sysDur = sys['durationSeconds'] as int? ?? 0;
        if (sysStart > 0 && (sysStart - audioMs).abs() < 60000) { // 1 minute tolerance
          sysStatus = sys['callStatus'] as String? ?? '';
          if (durationSec <= 0 && sysDur > 0) {
            durationSec = sysDur;
          }
          break;
        }
      }
    }

    // Fallback estimate from file size if duration is still 0
    if (durationSec <= 0 && audio.size > 0) {
      durationSec = (audio.size / 2500).round();
      if (durationSec < 1) durationSec = 1;
    }

    if (durationSec > 0) {
      final endDt = baseStartDt.add(Duration(seconds: durationSec));
      endStr = DateFormat('hh:mm:ss a').format(endDt);
      final mins = durationSec ~/ 60;
      final secs = durationSec % 60;
      durationStr = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
    } else {
      durationStr = '';
    }

    return {
      'fromPhone': fromPhone,
      'toPhone': toPhone,
      'startTime': startStr,
      'endTime': endStr,
      'duration': durationStr,
      'sysStatus': sysStatus,
    };
  }

  Color _hexToColor(String? hexString) {
    if (hexString == null || hexString.isEmpty) return Colors.grey;
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) {
      buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    }
    return Colors.grey;
  }

  String _formatCurrency(double? value) {
    if (value == null || value == 0.0) return '\$0.00';
    final formatter = NumberFormat.simpleCurrency(decimalDigits: 0);
    return formatter.format(value);
  }

  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _wasEdited);
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.secondary,
        appBar: AppBar(
          backgroundColor: AppColors.secondary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context, _wasEdited),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.textPrimary),
              tooltip: 'Refresh Lead Details & Call Logs',
              onPressed: () {
                final state = context.read<LeadsBloc>().state;
                if (state is LeadDetailsLoaded) {
                  final leadId = state.leadDetail.id;
                  final phone = state.leadDetail.phone;

                  // 1. Re-fetch core lead details, call logs & audios
                  context.read<LeadsBloc>().add(FetchLeadDetails(leadId));
                  context.read<LeadsBloc>().add(FetchLeadCallLogs(leadId));
                  context.read<LeadsBloc>().add(FetchLeadAudios(leadId));

                  // 2. Clear cached call log futures & local recordings
                  setState(() {
                    _callLogsFuture = null;
                    _localRecordingsFetched = false;
                  });
                  _fetchLocalRecordings(phone);

                  // 3. Re-fetch tab-specific data if on Activities or Documents
                  if (_activeTabIndex == 1) {
                    context.read<LeadsBloc>().add(FetchLeadAuditLogs(leadId));
                  } else if (_activeTabIndex == 3) {
                    context.read<LeadsBloc>().add(FetchLeadAttachments(leadId));
                  }

                  // 4. Trigger auto-scan & upload for recordings
                  AutoCallRecordingUploader.autoScanAndUploadLeadRecordings(
                    context: context,
                    leadId: leadId,
                    phoneNumber: phone,
                    existingServerAudios: state.audios,
                    onUploadSuccess: () {
                      if (mounted) {
                        context.read<LeadsBloc>().add(FetchLeadAudios(leadId));
                        context.read<LeadsBloc>().add(FetchLeadCallLogs(leadId));
                      }
                    },
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Refreshing lead details & call logs...'),
                      duration: Duration(seconds: 1),
                      backgroundColor: AppColors.primary,
                    ),
                  );
                }
              },
            ),
            BlocBuilder<LeadsBloc, LeadsState>(
              builder: (context, state) {
                final leadPhone = state is LeadDetailsLoaded ? state.leadDetail.phone : '';
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leadPhone.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.phone, color: AppColors.primary),
                        tooltip: 'Call Lead',
                        onPressed: () async {
                          if (state is LeadDetailsLoaded) {
                            final lead = state.leadDetail;
                            _lastCallTimestamp = DateTime.now().millisecondsSinceEpoch;
                            AutoCallRecordingUploader.makeCallAndAutoUpload(
                              context: context,
                              leadId: lead.id,
                              phoneNumber: lead.phone,
                              leadName: '${lead.firstName} ${lead.lastName}',
                              onUploadSuccess: () {
                                if (context.mounted) {
                                  context.read<LeadsBloc>().add(FetchLeadAudios(lead.id));
                                  _fetchLocalRecordings(lead.phone);
                                }
                              },
                            );
                          }
                        },
                      ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz, color: AppColors.textPrimary),
                      onSelected: (value) {
                        if (value == 'edit') {
                          if (state is LeadDetailsLoaded) {
                            _navigateToEditForm(context, state.leadDetail, targetFieldKey: null);
                          }
                        } else if (value == 'toggle_status') {
                          if (state is LeadDetailsLoaded) {
                            context.read<LeadsBloc>().add(UpdateLeadActiveStatus(leadId: state.leadDetail.id, isActive: !widget.isActive));
                          }
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit Lead'),
                        ),
                        PopupMenuItem(
                          value: 'toggle_status',
                          child: Text(widget.isActive ? 'Deactivate Lead' : 'Activate Lead'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        body: BlocConsumer<LeadsBloc, LeadsState>(
          listener: (context, state) {
            if (state is LeadActionSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message), backgroundColor: Colors.green));
              Navigator.pop(context, true); // Pop out when activated/deactivated successfully
            } else if (state is LeadActionError) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message), backgroundColor: AppColors.primary));
            }
          },
          builder: (context, state) {
            if (state is LeadDetailsLoading || state is LeadActionLoading) {
              return const Center(child: SpinningLogo(size: 60));
            } else if (state is LeadDetailsError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(state.message, style: const TextStyle(color: AppColors.primary)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        // Trigger retry
                        Navigator.pop(context);
                      },
                      child: const Text('Go Back'),
                    ),
                  ],
                ),
              );
            } else if (state is LeadDetailsLoaded) {
              final lead = state.leadDetail;
              final fullName = '${lead.firstName} ${lead.lastName}';
              
              final statusColor = lead.status?.color != null 
                  ? _hexToColor(lead.status!.color) 
                  : AppColors.primary;

              final initials = (lead.firstName.isNotEmpty ? lead.firstName[0] : '') +
                               (lead.lastName.isNotEmpty ? lead.lastName[0] : '');

              return SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─── PROFILE HEADER: AVATAR ON LEFT BELOW BACK BUTTON ───────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: statusColor,
                            child: Text(
                              initials.toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        fullName,
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textHint),
                                      tooltip: 'Edit Name',
                                      onPressed: () => _navigateToEditForm(context, lead, targetFieldKey: 'name'),
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      padding: const EdgeInsets.all(4),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(Icons.phone_outlined, size: 13, color: AppColors.textHint),
                                    const SizedBox(width: 4),
                                    Text(
                                      lead.phone.isNotEmpty ? lead.phone : 'No Phone',
                                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                                    ),
                                    if (lead.phone.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () {
                                          Clipboard.setData(ClipboardData(text: lead.phone));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Phone number copied to clipboard'),
                                              duration: Duration(seconds: 2),
                                              backgroundColor: AppColors.primary,
                                            ),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(4),
                                        child: const Padding(
                                          padding: EdgeInsets.all(2.0),
                                          child: Icon(
                                            Icons.copy_rounded,
                                            size: 14,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (lead.companyName.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    lead.companyName,
                                    style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ─── STATUS DROPDOWN & RESCHEDULE BUTTON ROW ────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        children: [
                          // 1st: Status Dropdown
                          Expanded(
                            child: _buildStatusDropdown(context, lead),
                          ),
                          const SizedBox(width: 10),
                          // 2nd: Reschedule Button
                          Expanded(
                            child: _buildRescheduleButton(context, lead),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                  // Tab Bar Headers
                  _buildTabBar(state),

                  // Active Tab Content
                  Expanded(
                    child: IndexedStack(
                      index: _activeTabIndex,
                      children: [
                        _buildOverviewTab(lead),
                        _buildActivitiesTab(state),
                        _buildServerCallLogTab(state),
                        _buildDocumentsTab(state),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return const SizedBox();
        },
      ),
    )
    );
  }

  Widget _buildStatusDropdown(BuildContext context, LeadDetail lead) {
    final currentStatusId = lead.status?.id;
    final statusColor = lead.status?.color != null 
        ? _hexToColor(lead.status!.color) 
        : AppColors.primary;

    final isCurrentInList = currentStatusId != null && _availableStatuses.any((s) => s.id == currentStatusId);

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderEnabled),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: isCurrentInList ? currentStatusId : null,
          isExpanded: true,
          hint: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  lead.status?.statusName ?? 'Select Status',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          icon: const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
          items: _availableStatuses.map((st) {
            final stColor = _hexToColor(st.color);
            return DropdownMenuItem<String>(
              value: st.id,
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: stColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      st.statusName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: st.id == currentStatusId ? FontWeight.bold : FontWeight.normal,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (newStatusId) {
            if (newStatusId != null && newStatusId != currentStatusId) {
              _updateLeadStatus(context, lead, newStatusId);
            }
          },
        ),
      ),
    );
  }

  Widget _buildRescheduleButton(BuildContext context, LeadDetail lead) {
    return SizedBox(
      height: 46,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: const Icon(Icons.event_repeat_rounded, size: 18, color: Colors.white),
        label: const Text(
          'Reschedule',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        onPressed: () async {
          final result = await AddFollowUpScreen.openFromRight(context, leadId: lead.id);
          if (result == true && context.mounted) {
            _wasEdited = true;
            context.read<LeadsBloc>().add(FetchLeadDetails(lead.id));
          }
        },
      ),
    );
  }

  void _updateLeadStatus(BuildContext context, LeadDetail lead, String newStatusId) {
    final leadData = {
      'firstName': lead.firstName,
      'lastName': lead.lastName,
      'companyName': lead.companyName,
      'email': lead.email,
      'phone': lead.phone,
      'alternatePhone': lead.alternatePhone,
      'sourceId': lead.source?.id,
      'statusId': newStatusId,
      'score': lead.score ?? 0,
      'priority': lead.priority,
      'industry': lead.industry,
      'annualRevenue': lead.annualRevenue ?? 0.0,
      'employeeSize': lead.employeeSize ?? 0,
      'website': lead.website,
      'country': lead.country,
      'state': lead.state,
      'city': lead.city,
      'postalCode': lead.postalCode,
      'address': lead.address,
      'description': lead.description,
      'ownerUserId': lead.ownerUserId,
    };
    leadData.removeWhere((key, value) => value == null);

    context.read<LeadsBloc>().add(UpdateLead(
      leadId: lead.id,
      leadData: leadData,
      filePaths: [],
    ));
    _wasEdited = true;
  }

  Widget _buildTabBar(LeadDetailsLoaded state) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderEnabled)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: List.generate(_tabs.length, (index) {
            final isSelected = index == _activeTabIndex;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _activeTabIndex = index;
                });
                if (index == 1 && state.auditLogs == null) {
                  context.read<LeadsBloc>().add(FetchLeadAuditLogs(state.leadDetail.id));
                } else if (index == 2) {
                  _fetchLocalRecordings(state.leadDetail.phone);
                  if (state.callLogs == null) {
                    context.read<LeadsBloc>().add(FetchLeadCallLogs(state.leadDetail.id));
                  }
                  if (state.audios == null) {
                    context.read<LeadsBloc>().add(FetchLeadAudios(state.leadDetail.id));
                  }
                  AutoCallRecordingUploader.autoScanAndUploadLeadRecordings(
                    context: context,
                    leadId: state.leadDetail.id,
                    phoneNumber: state.leadDetail.phone,
                    existingServerAudios: state.audios,
                    onUploadSuccess: () {
                      if (mounted) {
                        context.read<LeadsBloc>().add(FetchLeadAudios(state.leadDetail.id));
                        context.read<LeadsBloc>().add(FetchLeadCallLogs(state.leadDetail.id));
                      }
                    },
                  );
                } else if (index == 3 && state.attachments == null) {
                  context.read<LeadsBloc>().add(FetchLeadAttachments(state.leadDetail.id));
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected ? AppColors.primary : Colors.transparent,
                      width: 2.0,
                    ),
                  ),
                ),
                child: Text(
                  _tabs[index],
                  style: TextStyle(
                    color: isSelected ? AppColors.primary : AppColors.textHint,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildOverviewTab(LeadDetail lead) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Contact Info Card
          _buildInfoCard(
            'Contact Information',
            [
              _buildInfoRow(
                Icons.mail_outline, 
                'Email', 
                lead.email,
                onEditTap: () => _navigateToEditForm(context, lead, targetFieldKey: 'email'),
              ),
              _buildInfoRow(
                Icons.phone_outlined, 
                'Phone', 
                lead.phone,
                onEditTap: () => _navigateToEditForm(context, lead, targetFieldKey: 'phone'),
                trailing: lead.phone.isNotEmpty
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, color: AppColors.primary, size: 20),
                            tooltip: 'Copy Phone Number',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: lead.phone));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Phone number copied to clipboard'),
                                  duration: Duration(seconds: 2),
                                  backgroundColor: AppColors.primary,
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.phone, color: AppColors.primary, size: 20),
                            tooltip: 'Call Lead',
                            onPressed: () async {
                              _lastCallTimestamp = DateTime.now().millisecondsSinceEpoch;
                              AutoCallRecordingUploader.makeCallAndAutoUpload(
                                context: context,
                                leadId: lead.id,
                                phoneNumber: lead.phone,
                                leadName: '${lead.firstName} ${lead.lastName}',
                                onUploadSuccess: () {
                                  if (context.mounted) {
                                    context.read<LeadsBloc>().add(FetchLeadAudios(lead.id));
                                    _fetchLocalRecordings(lead.phone);
                                  }
                                },
                              );
                            },
                          ),
                        ],
                      )
                    : null,
              ),
              if (lead.alternatePhone != null && lead.alternatePhone!.isNotEmpty)
                _buildInfoRow(
                  Icons.phone_iphone_outlined, 
                  'Alternate Phone', 
                  lead.alternatePhone!,
                  onEditTap: () => _navigateToEditForm(context, lead, targetFieldKey: 'alternatePhone'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: AppColors.primary, size: 20),
                        tooltip: 'Copy Alternate Phone',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: lead.alternatePhone!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Alternate phone copied to clipboard'),
                              duration: Duration(seconds: 2),
                              backgroundColor: AppColors.primary,
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.phone, color: AppColors.primary, size: 20),
                        tooltip: 'Call Alternate Phone',
                        onPressed: () async {
                          _lastCallTimestamp = DateTime.now().millisecondsSinceEpoch;
                          AutoCallRecordingUploader.makeCallAndAutoUpload(
                            context: context,
                            leadId: lead.id,
                            phoneNumber: lead.alternatePhone!,
                            leadName: '${lead.firstName} ${lead.lastName}',
                            onUploadSuccess: () {
                              if (context.mounted) {
                                context.read<LeadsBloc>().add(FetchLeadAudios(lead.id));
                                _fetchLocalRecordings(lead.alternatePhone!);
                              }
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              if (lead.website != null && lead.website!.isNotEmpty)
                _buildInfoRow(
                  Icons.language_outlined, 
                  'Website', 
                  lead.website!,
                  onEditTap: () => _navigateToEditForm(context, lead, targetFieldKey: 'website'),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Address Info Card
          _buildInfoCard(
            'Address Information',
            [
              _buildInfoRow(
                Icons.map_outlined,
                'Address',
                lead.address ?? '',
                subvalue: '${lead.city ?? ''}${lead.city != null && lead.state != null ? ", " : ""}${lead.state ?? ''} ${lead.postalCode ?? ''}\n${lead.country ?? ''}',
                onEditTap: () => _navigateToEditForm(context, lead, targetFieldKey: 'address'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Additional Details Card
          _buildInfoCard(
            'Additional Information',
            [
              _buildInfoRow(
                Icons.person_outline, 
                'Owner', 
                lead.ownerUserName ?? 'Unassigned',
                onEditTap: () => _navigateToEditForm(context, lead, targetFieldKey: 'ownerUserId'),
              ),
              if (lead.priority != null)
                _buildInfoRow(
                  Icons.flag_outlined, 
                  'Priority', 
                  lead.priority!,
                  onEditTap: () => _navigateToEditForm(context, lead, targetFieldKey: 'priority'),
                ),
              if (lead.source?.name != null)
                _buildInfoRow(
                  Icons.share_outlined, 
                  'Source', 
                  lead.source!.name,
                  onEditTap: () => _navigateToEditForm(context, lead, targetFieldKey: 'sourceId'),
                ),
              if (lead.createdAt != null)
                _buildInfoRow(
                  Icons.calendar_today_outlined, 
                  'Created At', 
                  DateFormat('MMM dd, yyyy, hh:mm a').format(lead.createdAt!.toLocal()),
                ),
              if (lead.description != null && lead.description!.isNotEmpty)
                _buildInfoRow(
                  Icons.description_outlined, 
                  'Description', 
                  lead.description!,
                  onEditTap: () => _navigateToEditForm(context, lead, targetFieldKey: 'description'),
                ),
            ],
          ),

          if (lead.customFields.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildInfoCard(
              'Custom Fields',
              lead.customFields.map((field) {
                final isAttachment = field.fieldType.toUpperCase() == 'ATTACHMENT' || field.fieldType.toUpperCase() == 'FILE';
                final icon = isAttachment ? Icons.attach_file_outlined : Icons.toc_outlined;
                final valStr = field.value?.toString() ?? '';
                return _buildInfoRow(
                  icon, 
                  field.label, 
                  valStr.isNotEmpty ? valStr : '-',
                  onEditTap: () => _navigateToEditForm(context, lead, targetFieldKey: 'customField_${field.fieldId}'),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }


  String _cleanAudioTitle(String rawName, {bool isIncoming = false, bool isUnanswered = false}) {
    final lowerRaw = rawName.toLowerCase();
    if (lowerRaw.startsWith('missed_') || lowerRaw.contains('missed') || lowerRaw.contains('unanswered')) {
      return isIncoming ? 'Missed Call' : 'Unanswered Call';
    }
    var name = rawName;
    while (true) {
      final old = name;
      name = name
          .replaceAll(RegExp(r'^REC_', caseSensitive: false), '')
          .replaceAll(RegExp(r'^INCOMING_', caseSensitive: false), '')
          .replaceAll(RegExp(r'^OUTGOING_', caseSensitive: false), '')
          .replaceAll(RegExp(r'^INBOUND_', caseSensitive: false), '')
          .replaceAll(RegExp(r'^OUTBOUND_', caseSensitive: false), '');
      if (name == old) break;
    }
    if (name.trim().isEmpty || RegExp(r'^\d+$').hasMatch(name.trim())) {
      if (isUnanswered) {
        return isIncoming ? 'Missed Call' : 'Unanswered Call';
      }
    }
    return name.isEmpty ? rawName : name;
  }

  int _getEffectiveTimestamp(LeadAudio audio) {
    final name = audio.displayName.isNotEmpty ? audio.displayName : audio.fileName;

    // Priority 1: Parse exact timestamp from file name
    final parsed = AutoCallRecordingUploader.parseTimestampFromFileName(name);
    if (parsed != null && parsed > 0) {
      return parsed;
    }

    // Priority 2: Try parsing date + startTimeStr if startTimeStr is valid
    if (audio.startTimeStr != null && audio.startTimeStr!.isNotEmpty && audio.startTimeStr != 'null' && audio.startTimeStr != '--:--') {
      try {
        final dateBase = audio.createdAt?.toLocal() ?? DateTime.now();
        var st = audio.startTimeStr!.trim();
        if (st.contains('T')) st = st.split('T').last;
        final parts = st.split(':');
        if (parts.length >= 2) {
          final hh = int.tryParse(parts[0]) ?? dateBase.hour;
          final mm = int.tryParse(parts[1]) ?? dateBase.minute;
          final ss = parts.length > 2 ? (int.tryParse(parts[2].split('.')[0]) ?? dateBase.second) : 0;
          final dt = DateTime(dateBase.year, dateBase.month, dateBase.day, hh, mm, ss);
          return dt.millisecondsSinceEpoch;
        }
      } catch (_) {}
    }

    // Priority 3: Fallback to createdAt timestamp
    if (audio.createdAt != null) {
      return audio.createdAt!.toLocal().millisecondsSinceEpoch;
    }

    return 0;
  }

  int _compareByLatest(LeadAudio a, LeadAudio b) {
    final timeA = _getEffectiveTimestamp(a);
    final timeB = _getEffectiveTimestamp(b);
    if (timeA != timeB) {
      return timeB.compareTo(timeA); // Descending (latest / most recent call first)
    }
    return b.id.compareTo(a.id);
  }



  Widget _buildAudioCardItem(_CallCardData item) {
    final isIncoming = item.isIncoming;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: item.isUnanswered ? const Color(0xFFFDE68A) : AppColors.borderEnabled,
        ),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── CARD HEADER ───────────────────────────────
            Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: item.isUnanswered
                      ? const Color(0xFFFEF3C7)
                      : (isIncoming ? const Color(0xFFD1FAE5) : const Color(0xFFFFE4E6)),
                  child: Icon(
                    item.isUnanswered
                        ? Icons.phone_missed_rounded
                        : (isIncoming ? Icons.call_received_rounded : Icons.call_made_rounded),
                    size: 15,
                    color: item.isUnanswered
                        ? const Color(0xFFD97706)
                        : (isIncoming ? const Color(0xFF059669) : const Color(0xFFE11D48)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: item.isUnanswered
                        ? const Color(0xFFFFFBEB)
                        : (isIncoming ? const Color(0xFFECFDF5) : const Color(0xFFFFF1F2)),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: item.isUnanswered
                          ? const Color(0xFFFDE68A)
                          : (isIncoming ? const Color(0xFFA7F3D0) : const Color(0xFFFECDD3)),
                    ),
                  ),
                  child: Text(
                    isIncoming
                        ? (item.isUnanswered ? 'INCOMING • MISSED' : 'INCOMING')
                        : (item.isUnanswered ? 'OUTGOING • UNANSWERED' : 'OUTGOING'),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: item.isUnanswered
                          ? const Color(0xFFD97706)
                          : (isIncoming ? const Color(0xFF059669) : const Color(0xFFE11D48)),
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                if (item.audio != null) ...[
                  // Listen Button
                  InkWell(
                    onTap: () => _playLeadAudio(context, item.audio!),
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(4.0),
                      child: Icon(Icons.play_circle_fill, color: AppColors.primary, size: 26),
                    ),
                  ),
                  // Download Button
                  InkWell(
                    onTap: () => _downloadLeadAudio(context, item.audio!),
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(4.0),
                      child: Icon(Icons.download_rounded, color: AppColors.primary, size: 20),
                    ),
                  ),
                ]
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            const SizedBox(height: 8),

            // ─── CARD DETAILS ──────────────────────────────
            // 1. From & To Phone Numbers
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isIncoming ? Icons.call_received_rounded : Icons.call_made_rounded,
                  size: 14,
                  color: isIncoming ? const Color(0xFF059669) : const Color(0xFFE11D48),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'From: ',
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 12),
                        ),
                        TextSpan(
                          text: '${item.fromPhone}   ',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF111827), fontSize: 12),
                        ),
                        const TextSpan(
                          text: '➔   To: ',
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 12),
                        ),
                        TextSpan(
                          text: item.toPhone,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF111827), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // 2. Start & End Times + Duration
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.access_time_rounded, size: 14, color: AppColors.textHint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Start: ',
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 11.5),
                        ),
                        TextSpan(
                          text: '${item.startTimeStr}   ',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF374151), fontSize: 11.5),
                        ),
                        const TextSpan(
                          text: '•   End: ',
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 11.5),
                        ),
                        TextSpan(
                          text: '${item.endTimeStr}   ',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF374151), fontSize: 11.5),
                        ),
                        if (item.durationStr.isNotEmpty && !item.isUnanswered)
                          TextSpan(
                            text: '(${item.durationStr})',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: item.isUnanswered ? const Color(0xFFD97706) : AppColors.primary,
                              fontSize: 11.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // 3. Date & Size Info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item.dateStr,
                  style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                ),
                Text(
                  item.sizeStr,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
              ],
            ),

            if (item.audio != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.audiotrack_rounded, color: AppColors.primary, size: 18),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Recording Available',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _playLeadAudio(context, item.audio!),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _downloadLeadAudio(context, item.audio!),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
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
              ),
            ],
          ],
        ),
      ),
    );
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
    final isUnansweredLog = statusUpper == 'MISSED' ||
        statusUpper == 'REJECTED' ||
        statusUpper == 'UNANSWERED' ||
        statusUpper == 'NOT_CONNECTED' ||
        log.duration == '0s' || log.duration == '0' || log.duration == '00:00:00' || log.duration.trim().isEmpty;

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
    final isMissed = statusUpper == 'MISSED' ||
        statusUpper == 'REJECTED' ||
        statusUpper == 'UNANSWERED' ||
        statusUpper == 'NOT_CONNECTED' ||
        log.duration == '0s' || log.duration == '0' || log.duration == '00:00:00' || log.duration.trim().isEmpty;

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

  Widget _buildServerCallLogTab(LeadDetailsLoaded state) {
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
    if (callLogs.callHistory.isEmpty) {
      return const Center(
        child: Text(
          'No call logs found for this lead.',
          style: TextStyle(color: AppColors.textHint, fontSize: 16),
        ),
      );
    }

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
                  callLogs.totalCalls.toString(),
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
                  callLogs.totalInboundCalls.toString(),
                  Icons.call_received,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCallLogSummaryCard(
                  'Outbound',
                  callLogs.totalOutboundCalls.toString(),
                  Icons.call_made,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCallLogSummaryCard(
                  'Missed',
                  callLogs.totalMissedCalls.toString(),
                  Icons.call_missed,
                  Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Call History',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),

          Builder(
            builder: (context) {
              // Group call logs by relative date header (Today, Yesterday, Date)
              final Map<String, List<LeadCallLog>> groupedLogs = {};
              for (final log in callLogs.callHistory) {
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
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
    final isMissed = statusUpper == 'MISSED' ||
        statusUpper == 'REJECTED' ||
        statusUpper == 'UNANSWERED' ||
        statusUpper == 'NOT_CONNECTED' ||
        log.duration == '0s' || log.duration == '0' || log.duration == '00:00:00' || log.duration.trim().isEmpty;
    
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              displayDateTime,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textHint,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (cardData.audio != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.mic_rounded, color: AppColors.primary, size: 12),
                                        SizedBox(width: 3),
                                        Text(
                                          'Audio',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                  color: isExpanded ? AppColors.primary : AppColors.textHint,
                                  size: 22,
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
              child: Column(
                children: [
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  const SizedBox(height: 8),
                  _buildAudioCardItem(cardData),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds == 0) return '0s';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    
    if (h > 0) {
      return '${h}h ${m}m';
    } else if (m > 0) {
      return '${m}m ${s}s';
    } else {
      return '${s}s';
    }
  }




  Widget _buildDocumentsTab(LeadDetailsLoaded state) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: _buildAttachmentsBody(state),
          ),
          const SizedBox(height: 12),
          
          // Upload Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              icon: state.isAttachmentsLoading 
                  ? const SizedBox(
                      width: 18, 
                      height: 18, 
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    )
                  : const Icon(Icons.upload_file_outlined),
              label: Text(
                state.isAttachmentsLoading ? 'Uploading...' : 'Upload Document',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              onPressed: state.isAttachmentsLoading 
                  ? null 
                  : () => _pickAndUploadFile(context, state.leadDetail.id),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsBody(LeadDetailsLoaded state) {
    if (state.isAttachmentsLoading && state.attachments == null) {
      return const Center(child: SpinningLogo(size: 40));
    }
    if (state.attachmentsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                state.attachmentsError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.primary, fontSize: 14),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  context.read<LeadsBloc>().add(FetchLeadAttachments(state.leadDetail.id));
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final serverAttachments = state.attachments ?? [];
    final List<Attachment> allDocuments = List.from(serverAttachments);
    final seenDocIds = serverAttachments.map((a) => a.id).toSet();
    final seenDocNames = serverAttachments.map((a) => a.fileName.toLowerCase()).toSet();

    for (final cf in state.leadDetail.customFields) {
      final valStr = cf.value?.toString().trim() ?? '';
      if (valStr.isEmpty) continue;
      final typeUpper = cf.fieldType.toUpperCase();
      final lowerVal = valStr.toLowerCase();
      final isFileField = typeUpper == 'FILE' ||
          typeUpper == 'ATTACHMENT' ||
          typeUpper == 'DOCUMENT' ||
          typeUpper == 'IMAGE' ||
          lowerVal.endsWith('.pdf') ||
          lowerVal.endsWith('.doc') ||
          lowerVal.endsWith('.docx') ||
          lowerVal.endsWith('.xls') ||
          lowerVal.endsWith('.xlsx') ||
          lowerVal.endsWith('.png') ||
          lowerVal.endsWith('.jpg') ||
          lowerVal.endsWith('.jpeg') ||
          lowerVal.endsWith('.csv') ||
          lowerVal.endsWith('.txt') ||
          lowerVal.endsWith('.zip');

      if (isFileField && !seenDocNames.contains(lowerVal)) {
        seenDocNames.add(lowerVal);
        final docId = 'cf_${cf.fieldId}';
        if (!seenDocIds.contains(docId)) {
          seenDocIds.add(docId);
          allDocuments.add(Attachment(
            id: docId,
            leadId: state.leadDetail.id,
            fileName: '${cf.label}: $valStr',
            fileType: cf.fieldType,
            filePath: valStr,
            createdAt: state.leadDetail.createdAt,
          ));
        }
      }
    }

    if (allDocuments.isEmpty) {
      return const Center(
        child: Text(
          'No documents uploaded yet.',
          style: TextStyle(color: AppColors.textHint, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: allDocuments.length,
      itemBuilder: (context, index) {
        final doc = allDocuments[index];
        
        // Define file type icon
        IconData fileIcon = Icons.insert_drive_file_outlined;
        Color fileColor = Colors.grey;

        final lowerType = doc.fileType.toLowerCase();
        final lowerName = doc.fileName.toLowerCase();
        
        if (lowerType.contains('image') || lowerName.endsWith('.png') || lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) {
          fileIcon = Icons.image_outlined;
          fileColor = Colors.blue;
        } else if (lowerType.contains('pdf') || lowerName.endsWith('.pdf')) {
          fileIcon = Icons.picture_as_pdf_outlined;
          fileColor = Colors.red;
        } else if (lowerType.contains('word') || lowerName.endsWith('.doc') || lowerName.endsWith('.docx')) {
          fileIcon = Icons.description_outlined;
          fileColor = Colors.indigo;
        } else if (lowerType.contains('excel') || lowerName.endsWith('.xls') || lowerName.endsWith('.xlsx') || lowerName.endsWith('.csv')) {
          fileIcon = Icons.table_chart_outlined;
          fileColor = Colors.green;
        }

        final dateStr = doc.createdAt != null 
            ? DateFormat('MMM dd, yyyy').format(doc.createdAt!) 
            : 'Unknown Date';

        return Card(
          margin: const EdgeInsets.only(bottom: 12.0),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.borderEnabled),
          ),
          color: Colors.white,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _downloadAttachment(context, doc),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: fileColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(fileIcon, color: fileColor, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.fileName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Uploaded on $dateStr',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_rounded, color: AppColors.primary, size: 22),
                    tooltip: 'Download',
                    onPressed: () => _downloadAttachment(context, doc),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _downloadAttachment(BuildContext context, Attachment doc) async {
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
                'Downloading ${doc.fileName}...',
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
      final displayFileName = doc.fileName.isNotEmpty ? doc.fileName : 'attachment_${doc.id}';
      final sanitizedName = displayFileName.replaceAll(RegExp(r'[^\w.\- ]'), '_');
      final tempFile = File('${tempDir.path}/$sanitizedName');

      final leadsBaseUrl = ApiUrl.leadService;
      String downloadUrl = '$leadsBaseUrl/leads/attachments/${doc.id}/download';
      if (doc.id.startsWith('cf_')) {
        downloadUrl = '$leadsBaseUrl/leads/attachments/${doc.fileName}/download';
      }
      try {
        await sl<ApiClient>().download(
          downloadUrl,
          tempFile.path,
        );
      } catch (_) {
        final fallbackUrl = '$leadsBaseUrl/leads/${doc.leadId}/attachments/${doc.fileName}/download';
        await sl<ApiClient>().download(
          fallbackUrl,
          tempFile.path,
        );
      }

      if (await tempFile.exists() && (await tempFile.length()) > 0) {
        String? finalPath;
        if (Platform.isAndroid) {
          try {
            finalPath = await const MethodChannel('com.example.crm_mobile/call_recording').invokeMethod<String>(
              'saveToDownloads',
              {
                'filePath': tempFile.path,
                'fileName': sanitizedName,
                'mimeType': doc.fileType,
              },
            );
          } catch (e) {
            debugPrint('Error invoking saveToDownloads: $e');
          }
        }

        // Close download loader dialog
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

        final savedFile = (finalPath != null && !finalPath.startsWith('content://')) ? File(finalPath) : tempFile;

        if (context.mounted) {
          final String shortName = doc.fileName.length > 25 
              ? '${doc.fileName.substring(0, 12)}...${doc.fileName.substring(doc.fileName.length - 10)}' 
              : doc.fileName;
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
                            'mimeType': doc.fileType,
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
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
        if (context.mounted) {
          final String shortName = doc.fileName.length > 25 
              ? '${doc.fileName.substring(0, 12)}...${doc.fileName.substring(doc.fileName.length - 10)}' 
              : doc.fileName;
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
      debugPrint('Download error: $e');
      if (context.mounted) {
        final String shortName = doc.fileName.length > 25 
            ? '${doc.fileName.substring(0, 12)}...${doc.fileName.substring(doc.fileName.length - 10)}' 
            : doc.fileName;
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

  void _pickAndUploadFile(BuildContext context, String leadId) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      
      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        if (context.mounted) {
          context.read<LeadsBloc>().add(UploadLeadAttachment(
            leadId: leadId,
            filePath: filePath,
          ));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick file: $e')),
        );
      }
    }
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

  void _renameAudio(BuildContext context, LeadAudio audio) {
    final TextEditingController controller = TextEditingController(text: audio.displayName);
    bool isLoading = false;
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Rename Audio', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Enter new name',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              enabled: !isLoading,
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(ctx),
                child: const Text('CANCEL', style: TextStyle(color: AppColors.textHint)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: isLoading
                    ? null
                    : () async {
                        final newName = controller.text.trim();
                        if (newName.isNotEmpty && newName != audio.displayName) {
                          setState(() => isLoading = true);
                          try {
                            final result = await sl<LeadsRepository>().renameLeadAudio(audio.id, newName);
                            result.fold(
                              (failure) {
                                setState(() => isLoading = false);
                                if (!ctx.mounted) return;
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text(failure.message), backgroundColor: AppColors.primary),
                                );
                              },
                              (_) {
                                if (!ctx.mounted) return;
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('Audio renamed successfully'), backgroundColor: Colors.green),
                                );
                                // Refresh the lead details
                                sl<LeadsBloc>().add(FetchLeadDetails(audio.leadId));
                              },
                            );
                          } catch (e) {
                            setState(() => isLoading = false);
                            if (!ctx.mounted) return;
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.primary),
                            );
                          }
                        } else {
                          Navigator.pop(ctx);
                        }
                      },
                child: isLoading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('SAVE'),
              ),
            ],
          );
        }
      ),
    );
  }

  void _playLeadAudio(BuildContext context, LeadAudio audio) async {
    // Helper to update duration
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

  void _pickAndUploadAudio(BuildContext context, String leadId) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', '3gp', 'amr', 'ogg', 'opus'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Uploading ${result.files.single.name}...'),
              duration: const Duration(seconds: 3),
            ),
          );
          context.read<LeadsBloc>().add(UploadLeadAudio(leadId: leadId, filePath: filePath));
        }
      }
    } catch (e) {
      debugPrint('Error picking audio file: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to pick audio file'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    }
  }

  Widget _buildActivitiesTab(LeadDetailsLoaded state) {
    if (state.isAuditLogsLoading) {
      return const Center(child: SpinningLogo(size: 40));
    }
    if (state.auditLogsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                state.auditLogsError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.primary, fontSize: 14),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  context.read<LeadsBloc>().add(FetchLeadAuditLogs(state.leadDetail.id));
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final logs = state.auditLogs?.content ?? [];
    if (logs.isEmpty) {
      return const Center(
        child: Text(
          'No activities recorded yet.',
          style: TextStyle(color: AppColors.textHint, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        
        // Define action icons and colors
        IconData actionIcon = Icons.info_outline;
        Color actionColor = Colors.blue;
        
        if (log.actionType == 'CREATE') {
          actionIcon = Icons.add_circle_outline;
          actionColor = Colors.green;
        } else if (log.actionType == 'UPDATE') {
          actionIcon = Icons.edit_outlined;
          actionColor = Colors.orange;
        } else if (log.actionType == 'DELETE') {
          actionIcon = Icons.delete_outline;
          actionColor = Colors.red;
        }

        final timeStr = log.actionAt != null 
            ? DateFormat('MMM dd, yyyy  •  h:mm a').format(log.actionAt!) 
            : 'Just now';

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline line & icon
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: actionColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(actionIcon, color: actionColor, size: 18),
                ),
                if (index < logs.length - 1)
                  Container(
                    width: 2,
                    height: 50,
                    color: AppColors.borderEnabled,
                  ),
              ],
            ),
            const SizedBox(width: 16),
            
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.message,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'By ${log.actionByName.trim()}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textHint,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.textHint, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textHint,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoCard(String title, List<Widget> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderEnabled),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (context, index) => const SizedBox(height: 16),
            itemBuilder: (context, index) => rows[index],
          ),
        ],
      ),
    );
  }

  void _navigateToEditForm(BuildContext context, LeadDetail lead, {String? targetFieldKey}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BlocProvider(
          create: (_) => sl<LeadsBloc>(),
          child: AddLeadScreen(
            leadToEdit: lead,
            targetFieldKey: targetFieldKey,
          ),
        ),
      ),
    ).then((changed) {
      if (changed == true && context.mounted) {
        _wasEdited = true;
        context.read<LeadsBloc>().add(FetchLeadDetails(lead.id));
      }
    });
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {String? subvalue, Widget? trailing, VoidCallback? onEditTap}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.textHint, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: AppColors.textHint),
              ),
              const SizedBox(height: 2),
              Text(
                value.isNotEmpty ? value : '-',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
              ),
              if (subvalue != null && subvalue.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subvalue,
                  style: const TextStyle(fontSize: 13, color: AppColors.textHint),
                ),
              ]
            ],
          ),
        ),
        if (trailing != null) trailing,
        if (onEditTap != null)
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textHint),
            onPressed: onEditTap,
            tooltip: 'Edit $label',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
      ],
    );
  }
}

class _CallCardData {
  final LeadAudio? audio;
  final CallHistory? history;
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
    this.history,
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

