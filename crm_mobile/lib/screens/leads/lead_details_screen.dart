import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/blocs/leads_event.dart';
import 'package:crm_mobile/blocs/leads_state.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/models/lead_detail.dart';
import 'package:crm_mobile/models/lead_audio.dart';
import 'package:crm_mobile/core/services/call_recording_service.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';
import 'package:crm_mobile/models/call_history.dart';
import 'package:crm_mobile/core/services/call_history_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';
import 'package:crm_mobile/core/utils/staff_phone_resolver.dart';
import 'package:crm_mobile/screens/leads/add_lead_screen.dart';
import 'package:crm_mobile/screens/followups/add_followup_screen.dart';
import 'package:crm_mobile/screens/leads/widgets/lead_activities_tab.dart';
import 'package:crm_mobile/screens/leads/widgets/lead_call_logs_tab.dart';
import 'package:crm_mobile/screens/leads/widgets/lead_documents_tab.dart';

class LeadDetailsScreen extends StatelessWidget {
  final String leadId;
  final bool isActive;
  const LeadDetailsScreen({
    super.key,
    required this.leadId,
    this.isActive = true,
  });

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

class _LeadDetailsViewState extends State<LeadDetailsView>
    with WidgetsBindingObserver {
  int _activeTabIndex = 0;
  final List<String> _tabs = [
    'Overview',
    'Activities',
    'Call Logs',
    'Documents',
  ];
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
    if (nameLower.contains('outgoing') ||
        nameLower.contains('outbound') ||
        nameLower.contains('call_out') ||
        nameLower.contains('_outg_') ||
        nameLower.startsWith('outgoing_') ||
        nameLower.startsWith('outbound_') ||
        nameLower.contains('missed_out')) {
      _resolvedCallTypes[audio.id] = 'outbound';
      return 'outbound';
    }
    if (nameLower.contains('incoming') ||
        nameLower.contains('inbound') ||
        nameLower.contains('call_in') ||
        nameLower.contains('_inc_') ||
        nameLower.startsWith('incoming_') ||
        nameLower.startsWith('inbound_') ||
        nameLower.contains('missed_in')) {
      _resolvedCallTypes[audio.id] = 'inbound';
      return 'inbound';
    }

    if (audio.bound != null && audio.bound!.isNotEmpty) {
      final b = audio.bound!.toUpperCase();
      if (b == 'IN' || b == 'INBOUND' || b == 'INCOMING' || b.contains('IN')) {
        _resolvedCallTypes[audio.id] = 'inbound';
        return 'inbound';
      }
      if (b == 'OUT' ||
          b == 'OUTBOUND' ||
          b == 'OUTGOING' ||
          b.contains('OUT')) {
        _resolvedCallTypes[audio.id] = 'outbound';
        return 'outbound';
      }
    }

    if (audio.hasExplicitDirection) {
      _resolvedCallTypes[audio.id] = audio.callType.toLowerCase();
      return audio.callType.toLowerCase();
    }

    if (_localRecordings.isNotEmpty) {
      final cleanServerName = AutoCallRecordingUploader.cleanFileName(
        audio.displayName.toLowerCase(),
      );
      for (final local in _localRecordings) {
        final localPath = local['path']?.toString() ?? '';
        final localName = AutoCallRecordingUploader.cleanFileName(
          localPath.split('/').last.split('\\').last.toLowerCase(),
        );
        final localType = local['callType']?.toString() ?? '';
        if (localType.isNotEmpty &&
            (localName == cleanServerName ||
                localPath.contains(cleanServerName))) {
          _resolvedCallTypes[audio.id] = localType.toLowerCase();
          return localType.toLowerCase();
        }
      }
    }

    final audioMs = _getEffectiveTimestamp(audio);

    // 1. Check tracked call history for matching call timestamp within 1 minute
    if (_trackedCallHistory.isNotEmpty && audioMs > 0) {
      final cleanLeadPhone = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
      final leadLast10 = cleanLeadPhone.length >= 10
          ? cleanLeadPhone.substring(cleanLeadPhone.length - 10)
          : cleanLeadPhone;

      for (final c in _trackedCallHistory) {
        final cleanCPhone = c.phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
        final cLast10 = cleanCPhone.length >= 10
            ? cleanCPhone.substring(cleanCPhone.length - 10)
            : cleanCPhone;

        final isPhoneMatch =
            cleanLeadPhone.isEmpty ||
            cLast10 == leadLast10 ||
            cleanCPhone.contains(leadLast10) ||
            leadLast10.contains(cLast10);
        if (isPhoneMatch) {
          final diff1 = (c.timestamp - audioMs).abs();
          final diff2 = (c.startTime - audioMs).abs();

          if (diff1 < 60 * 1000 || diff2 < 60 * 1000) {
            final typeStr = c.callType.toLowerCase();
            final resolved = (typeStr == 'outgoing' || typeStr == 'outbound')
                ? 'outbound'
                : 'inbound';
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

    final fallback =
        (audio.callType.isNotEmpty && audio.callType.toLowerCase() != 'unknown')
        ? audio.callType.toLowerCase()
        : 'inbound';
    _resolvedCallTypes[audio.id] = fallback;
    return fallback;
  }

  void _resolveAudioDirectionFromCallLog(
    LeadAudio audio,
    String phoneNumber,
  ) async {
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
      if (mounted &&
          detected.isNotEmpty &&
          _resolvedCallTypes[audio.id] != detected) {
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
                  context.read<LeadsBloc>().add(FetchLeadCallLogs(lead.id));
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
        final paths = await callRecordingService.getAllSystemRecordings(
          phoneNumber,
        );
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
    if (rawTime == null ||
        rawTime.isEmpty ||
        rawTime == 'null' ||
        rawTime == '--:--')
      return null;
    try {
      var clean = rawTime.trim();
      if (clean.contains('T')) {
        clean = clean.split('T').last;
      }
      if (clean.contains('AM') ||
          clean.contains('PM') ||
          clean.contains('am') ||
          clean.contains('pm')) {
        return clean;
      }
      final parts = clean.split(':');
      if (parts.length >= 2) {
        final hh = int.tryParse(parts[0]) ?? 0;
        final mm = int.tryParse(parts[1]) ?? 0;
        final ss = parts.length > 2
            ? (int.tryParse(parts[2].split('.')[0]) ?? 0)
            : 0;
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

    final prefs = sl.isRegistered<SharedPreferences>()
        ? sl<SharedPreferences>()
        : null;
    final savedName = prefs?.getString('userName')?.trim();
    final savedPhone = prefs?.getString('userPhone')?.trim();

    final staffUser = (savedPhone != null && savedPhone.isNotEmpty)
        ? savedPhone
        : ((savedName != null && savedName.isNotEmpty) ? savedName : 'Staff');

    final cleanLeadPhone = leadPhone.isNotEmpty ? leadPhone : 'Lead';

    if (audio.fromNumber != null &&
        audio.fromNumber!.isNotEmpty &&
        audio.fromNumber != 'null' &&
        audio.fromNumber != 'Unknown') {
      fromPhone = audio.fromNumber!;
    }
    if (audio.toNumber != null &&
        audio.toNumber!.isNotEmpty &&
        audio.toNumber != 'null' &&
        audio.toNumber != 'Unknown') {
      toPhone = audio.toNumber!;
    }

    if (fromPhone.isEmpty ||
        fromPhone == 'Staff' ||
        fromPhone == 'null' ||
        fromPhone == 'Unknown') {
      if (isIncoming) {
        fromPhone = cleanLeadPhone;
      } else {
        fromPhone = staffUser;
      }
    }

    if (toPhone.isEmpty ||
        toPhone == 'Staff' ||
        toPhone == 'null' ||
        toPhone == 'Unknown') {
      if (isIncoming) {
        toPhone = staffUser;
      } else {
        toPhone = cleanLeadPhone;
      }
    }

    String startStr = '--:--';
    String endStr = '--:--';
    String durationStr = '';

    final startDt = (audio.createdAt != null)
        ? audio.createdAt!.toLocal()
        : DateTime.now();
    startStr = DateFormat('hh:mm:ss a').format(startDt);

    DateTime baseStartDt = startDt;

    if (audio.startTimeStr != null &&
        audio.startTimeStr!.isNotEmpty &&
        audio.startTimeStr != 'null' &&
        audio.startTimeStr != '--:--') {
      final formattedStart = _formatTimeString(audio.startTimeStr);
      if (formattedStart != null) startStr = formattedStart;

      final parts = audio.startTimeStr!.split(':');
      if (parts.length >= 2) {
        final hh = int.tryParse(parts[0]) ?? startDt.hour;
        final mm = int.tryParse(parts[1]) ?? startDt.minute;
        final ss = parts.length > 2
            ? (int.tryParse(parts[2].split('.')[0]) ?? startDt.second)
            : 0;
        baseStartDt = DateTime(
          startDt.year,
          startDt.month,
          startDt.day,
          hh,
          mm,
          ss,
        );
      }
    }

    if (audio.endTimeStr != null &&
        audio.endTimeStr!.isNotEmpty &&
        audio.endTimeStr != 'null' &&
        audio.endTimeStr != '--:--') {
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
        final cleanServerName = AutoCallRecordingUploader.cleanFileName(
          audio.displayName.toLowerCase(),
        );
        for (final local in effectiveLocals) {
          final localPath = local['path']?.toString() ?? '';
          final localName = AutoCallRecordingUploader.cleanFileName(
            localPath.split('/').last.split('\\').last.toLowerCase(),
          );
          final localDurMs = (local['durationMs'] as num?)?.toInt() ?? 0;
          final lowerPath = localPath.toLowerCase();
          final rawFileName = audio.fileName.toLowerCase();

          final isNameMatch =
              localName == cleanServerName ||
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
        if (diff1 < 60000 || diff2 < 60000) {
          // 1 minute tolerance
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
        if (sysStart > 0 && (sysStart - audioMs).abs() < 60000) {
          // 1 minute tolerance
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
            BlocBuilder<LeadsBloc, LeadsState>(
              builder: (context, state) {
                final leadPhone = state is LeadDetailsLoaded
                    ? state.leadDetail.phone
                    : '';
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
                            _lastCallTimestamp =
                                DateTime.now().millisecondsSinceEpoch;
                            AutoCallRecordingUploader.makeCallAndAutoUpload(
                              context: context,
                              leadId: lead.id,
                              phoneNumber: lead.phone,
                              leadName: '${lead.firstName} ${lead.lastName}',
                              onUploadSuccess: () {
                                if (context.mounted) {
                                  context.read<LeadsBloc>().add(
                                    FetchLeadAudios(lead.id),
                                  );
                                  _fetchLocalRecordings(lead.phone);
                                }
                              },
                            );
                          }
                        },
                      ),
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_horiz,
                        color: AppColors.textPrimary,
                      ),
                      onSelected: (value) {
                        if (value == 'edit') {
                          if (state is LeadDetailsLoaded) {
                            _navigateToEditForm(
                              context,
                              state.leadDetail,
                              targetFieldKey: null,
                            );
                          }
                        } else if (value == 'toggle_status') {
                          if (state is LeadDetailsLoaded) {
                            context.read<LeadsBloc>().add(
                              UpdateLeadActiveStatus(
                                leadId: state.leadDetail.id,
                                isActive: !widget.isActive,
                              ),
                            );
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
                          child: Text(
                            widget.isActive
                                ? 'Deactivate Lead'
                                : 'Activate Lead',
                          ),
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
            if (state is LeadDetailsLoaded) {
              if (_autoUploadedLeadId != state.leadDetail.id) {
                _autoUploadedLeadId = state.leadDetail.id;
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
              }
            } else if (state is LeadActionSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.green,
                ),
              );
              Navigator.pop(
                context,
                true,
              ); // Pop out when activated/deactivated successfully
            } else if (state is LeadActionError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: AppColors.primary,
                ),
              );
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
                    Text(
                      state.message,
                      style: const TextStyle(color: AppColors.primary),
                    ),
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

              final initials =
                  (lead.firstName.isNotEmpty ? lead.firstName[0] : '') +
                  (lead.lastName.isNotEmpty ? lead.lastName[0] : '');

              return SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─── PROFILE HEADER: AVATAR ON LEFT BELOW BACK BUTTON ───────
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 4.0,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: statusColor,
                            child: Text(
                              initials.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
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
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                        color: AppColors.textHint,
                                      ),
                                      tooltip: 'Edit Name',
                                      onPressed: () => _navigateToEditForm(
                                        context,
                                        lead,
                                        targetFieldKey: 'name',
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      padding: const EdgeInsets.all(4),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.phone_outlined,
                                      size: 13,
                                      color: AppColors.textHint,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      lead.phone.isNotEmpty
                                          ? lead.phone
                                          : 'No Phone',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (lead.phone.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () {
                                          Clipboard.setData(
                                            ClipboardData(text: lead.phone),
                                          );
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Phone number copied to clipboard',
                                              ),
                                              duration: Duration(seconds: 2),
                                              backgroundColor:
                                                  AppColors.primary,
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
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
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
                          Expanded(child: _buildStatusDropdown(context, lead)),
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
                          LeadActivitiesTab(state: state),
                          LeadCallLogsTab(state: state),
                          LeadDocumentsTab(state: state),
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
      ),
    );
  }

  Widget _buildStatusDropdown(BuildContext context, LeadDetail lead) {
    final currentStatusId = lead.status?.id;
    final statusColor = lead.status?.color != null
        ? _hexToColor(lead.status!.color)
        : AppColors.primary;

    final isCurrentInList =
        currentStatusId != null &&
        _availableStatuses.any((s) => s.id == currentStatusId);

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
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  lead.status?.statusName ?? 'Select Status',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          icon: const Icon(
            Icons.arrow_drop_down,
            color: AppColors.textSecondary,
          ),
          items: _availableStatuses.map((st) {
            final stColor = _hexToColor(st.color);
            return DropdownMenuItem<String>(
              value: st.id,
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: stColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      st.statusName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: st.id == currentStatusId
                            ? FontWeight.bold
                            : FontWeight.normal,
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
        icon: const Icon(
          Icons.event_repeat_rounded,
          size: 18,
          color: Colors.white,
        ),
        label: const Text(
          'Reschedule',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        onPressed: () async {
          final result = await AddFollowUpScreen.openFromRight(
            context,
            leadId: lead.id,
          );
          if (result == true && context.mounted) {
            _wasEdited = true;
            context.read<LeadsBloc>().add(FetchLeadDetails(lead.id));
          }
        },
      ),
    );
  }

  void _updateLeadStatus(
    BuildContext context,
    LeadDetail lead,
    String newStatusId,
  ) {
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

    context.read<LeadsBloc>().add(
      UpdateLead(leadId: lead.id, leadData: leadData, filePaths: []),
    );
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
                  context.read<LeadsBloc>().add(
                    FetchLeadAuditLogs(state.leadDetail.id),
                  );
                } else if (index == 2) {
                  _fetchLocalRecordings(state.leadDetail.phone);
                  if (state.callLogs == null) {
                    context.read<LeadsBloc>().add(
                      FetchLeadCallLogs(state.leadDetail.id),
                    );
                  }
                  if (state.audios == null) {
                    context.read<LeadsBloc>().add(
                      FetchLeadAudios(state.leadDetail.id),
                    );
                  }
                  AutoCallRecordingUploader.autoScanAndUploadLeadRecordings(
                    context: context,
                    leadId: state.leadDetail.id,
                    phoneNumber: state.leadDetail.phone,
                    existingServerAudios: state.audios,
                    onUploadSuccess: () {
                      if (mounted) {
                        context.read<LeadsBloc>().add(
                          FetchLeadAudios(state.leadDetail.id),
                        );
                        context.read<LeadsBloc>().add(
                          FetchLeadCallLogs(state.leadDetail.id),
                        );
                      }
                    },
                  );
                } else if (index == 3 && state.attachments == null) {
                  context.read<LeadsBloc>().add(
                    FetchLeadAttachments(state.leadDetail.id),
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12.0,
                  horizontal: 16.0,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected
                          ? AppColors.primary
                          : Colors.transparent,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Overview Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: AppColors.primary),
                tooltip: 'Refresh Overview',
                onPressed: () {
                  context.read<LeadsBloc>().add(FetchLeadDetails(lead.id));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Refreshing lead overview...'),
                      duration: Duration(seconds: 1),
                      backgroundColor: AppColors.primary,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Contact Info Card
          _buildInfoCard('Contact Information', [
            _buildInfoRow(
              Icons.mail_outline,
              'Email',
              lead.email,
              onEditTap: () =>
                  _navigateToEditForm(context, lead, targetFieldKey: 'email'),
            ),
            _buildInfoRow(
              Icons.phone_outlined,
              'Phone',
              lead.phone,
              onEditTap: () =>
                  _navigateToEditForm(context, lead, targetFieldKey: 'phone'),
              trailing: lead.phone.isNotEmpty
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.copy_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          tooltip: 'Copy Phone Number',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: lead.phone));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Phone number copied to clipboard',
                                ),
                                duration: Duration(seconds: 2),
                                backgroundColor: AppColors.primary,
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.phone,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          tooltip: 'Call Lead',
                          onPressed: () async {
                            _lastCallTimestamp =
                                DateTime.now().millisecondsSinceEpoch;
                            AutoCallRecordingUploader.makeCallAndAutoUpload(
                              context: context,
                              leadId: lead.id,
                              phoneNumber: lead.phone,
                              leadName: '${lead.firstName} ${lead.lastName}',
                              onUploadSuccess: () {
                                if (context.mounted) {
                                  context.read<LeadsBloc>().add(
                                    FetchLeadAudios(lead.id),
                                  );
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
                onEditTap: () => _navigateToEditForm(
                  context,
                  lead,
                  targetFieldKey: 'alternatePhone',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.copy_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      tooltip: 'Copy Alternate Phone',
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: lead.alternatePhone!),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Alternate phone copied to clipboard',
                            ),
                            duration: Duration(seconds: 2),
                            backgroundColor: AppColors.primary,
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.phone,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      tooltip: 'Call Alternate Phone',
                      onPressed: () async {
                        _lastCallTimestamp =
                            DateTime.now().millisecondsSinceEpoch;
                        AutoCallRecordingUploader.makeCallAndAutoUpload(
                          context: context,
                          leadId: lead.id,
                          phoneNumber: lead.alternatePhone!,
                          leadName: '${lead.firstName} ${lead.lastName}',
                          onUploadSuccess: () {
                            if (context.mounted) {
                              context.read<LeadsBloc>().add(
                                FetchLeadAudios(lead.id),
                              );
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
                onEditTap: () => _navigateToEditForm(
                  context,
                  lead,
                  targetFieldKey: 'website',
                ),
              ),
          ]),
          const SizedBox(height: 16),

          // Address Info Card
          _buildInfoCard('Address Information', [
            _buildInfoRow(
              Icons.map_outlined,
              'Address',
              lead.address ?? '',
              subvalue:
                  '${lead.city ?? ''}${lead.city != null && lead.state != null ? ", " : ""}${lead.state ?? ''} ${lead.postalCode ?? ''}\n${lead.country ?? ''}',
              onEditTap: () =>
                  _navigateToEditForm(context, lead, targetFieldKey: 'address'),
            ),
          ]),
          const SizedBox(height: 16),

          // Additional Details Card
          _buildInfoCard('Additional Information', [
            _buildInfoRow(
              Icons.person_outline,
              'Owner',
              lead.ownerUserName ?? 'Unassigned',
              onEditTap: () => _navigateToEditForm(
                context,
                lead,
                targetFieldKey: 'ownerUserId',
              ),
            ),
            if (lead.priority != null)
              _buildInfoRow(
                Icons.flag_outlined,
                'Priority',
                lead.priority!,
                onEditTap: () => _navigateToEditForm(
                  context,
                  lead,
                  targetFieldKey: 'priority',
                ),
              ),
            if (lead.source?.name != null)
              _buildInfoRow(
                Icons.share_outlined,
                'Source',
                lead.source!.name,
                onEditTap: () => _navigateToEditForm(
                  context,
                  lead,
                  targetFieldKey: 'sourceId',
                ),
              ),
            if (lead.createdAt != null)
              _buildInfoRow(
                Icons.calendar_today_outlined,
                'Created At',
                DateFormat(
                  'MMM dd, yyyy, hh:mm a',
                ).format(lead.createdAt!.toLocal()),
              ),
            if (lead.description != null && lead.description!.isNotEmpty)
              _buildInfoRow(
                Icons.description_outlined,
                'Description',
                lead.description!,
                onEditTap: () => _navigateToEditForm(
                  context,
                  lead,
                  targetFieldKey: 'description',
                ),
              ),
          ]),

          if (lead.customFields.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildInfoCard(
              'Custom Fields',
              lead.customFields.map((field) {
                final isAttachment =
                    field.fieldType.toUpperCase() == 'ATTACHMENT' ||
                    field.fieldType.toUpperCase() == 'FILE';
                final icon = isAttachment
                    ? Icons.attach_file_outlined
                    : Icons.toc_outlined;
                final valStr = field.value?.toString() ?? '';
                return _buildInfoRow(
                  icon,
                  field.label,
                  valStr.isNotEmpty ? valStr : '-',
                  onEditTap: () => _navigateToEditForm(
                    context,
                    lead,
                    targetFieldKey: 'customField_${field.fieldId}',
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  String _cleanAudioTitle(
    String rawName, {
    bool isIncoming = false,
    bool isUnanswered = false,
  }) {
    final lowerRaw = rawName.toLowerCase();
    if (lowerRaw.startsWith('missed_') ||
        lowerRaw.contains('missed') ||
        lowerRaw.contains('unanswered')) {
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
    final name = audio.displayName.isNotEmpty
        ? audio.displayName
        : audio.fileName;

    // Priority 1: Parse exact timestamp from file name
    final parsed = AutoCallRecordingUploader.parseTimestampFromFileName(name);
    if (parsed != null && parsed > 0) {
      return parsed;
    }

    // Priority 2: Try parsing date + startTimeStr if startTimeStr is valid
    if (audio.startTimeStr != null &&
        audio.startTimeStr!.isNotEmpty &&
        audio.startTimeStr != 'null' &&
        audio.startTimeStr != '--:--') {
      try {
        final dateBase = audio.createdAt?.toLocal() ?? DateTime.now();
        var st = audio.startTimeStr!.trim();
        if (st.contains('T')) st = st.split('T').last;
        final parts = st.split(':');
        if (parts.length >= 2) {
          final hh = int.tryParse(parts[0]) ?? dateBase.hour;
          final mm = int.tryParse(parts[1]) ?? dateBase.minute;
          final ss = parts.length > 2
              ? (int.tryParse(parts[2].split('.')[0]) ?? dateBase.second)
              : 0;
          final dt = DateTime(
            dateBase.year,
            dateBase.month,
            dateBase.day,
            hh,
            mm,
            ss,
          );
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
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
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

  void _navigateToEditForm(
    BuildContext context,
    LeadDetail lead, {
    String? targetFieldKey,
  }) {
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

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    String? subvalue,
    Widget? trailing,
    VoidCallback? onEditTap,
  }) {
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
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              if (subvalue != null && subvalue.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subvalue,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing,
        if (onEditTap != null)
          IconButton(
            icon: const Icon(
              Icons.edit_outlined,
              size: 18,
              color: AppColors.textHint,
            ),
            onPressed: onEditTap,
            tooltip: 'Edit $label',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
      ],
    );
  }
}
