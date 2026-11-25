import 'package:crm_mobile/repositories/followups_repository.dart';
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
import 'package:crm_mobile/screens/followups/edit_followup_screen.dart';
import 'package:crm_mobile/models/follow_up.dart';
import 'package:crm_mobile/usecases/get_lead_sources_usecase.dart';
import 'package:crm_mobile/usecases/get_staff_users_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_priorities_usecase.dart';
import 'package:crm_mobile/models/staff_user.dart';
import 'package:crm_mobile/screens/leads/widgets/lead_activities_tab.dart';
import 'package:crm_mobile/screens/leads/widgets/lead_call_logs_tab.dart';
import 'package:crm_mobile/screens/leads/widgets/lead_documents_tab.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/widgets/confirmation_dialog.dart';
import 'package:crm_mobile/widgets/call_number_picker_sheet.dart';

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
      create: (_) => sl<LeadsBloc>()..add(FetchLeadDetails(leadId)),
      child: LeadDetailsView(leadId: leadId, isActive: isActive),
    );
  }
}

class LeadDetailsView extends StatefulWidget {
  final String leadId;
  final bool isActive;
  const LeadDetailsView({
    super.key,
    required this.leadId,
    this.isActive = true,
  });

  @override
  State<LeadDetailsView> createState() => _LeadDetailsViewState();
}

class _LeadDetailsViewState extends State<LeadDetailsView>
    with WidgetsBindingObserver {
  int _activeTabIndex = 0;
  final List<String> _tabs = [
    'Overview',
    'Follow-up',
    'Activities',
    'Call Logs',
    'Documents',
  ];
  FollowUp? _leadFollowUp;
  List<FollowUp> _allLeadFollowUps = [];
  bool _isLoadingFollowUp = false;
  bool _hasFetchedFollowUp = false;
  String? _followUpError;
  String _selectedFollowUpFilter = 'Today';
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
  bool _localRecordingsFetched = false;
  final Set<String> _scannedLeadIds = {};
  LeadDetail? _lastLeadDetail;
  LeadDetailsLoaded? _lastDetailsLoadedState;
  bool _isRescheduleLoading = false;
  String? _editingFieldKey;
  final TextEditingController _inlineEditController = TextEditingController();
  String? _selectedDropdownValue;

  List<LeadSource> _availableSources = [];
  List<StaffUser> _availableOwners = [];
  List<String> _availablePriorities = ['HIGH', 'MEDIUM', 'LOW'];

  Future<void> _initiateLeadDetailCall({
    required LeadDetail lead,
    required String leadName,
    String? fallbackPhone,
    String? preferredPhone,
  }) async {
    final customPhoneOptions = extractLeadDetailCustomPhoneOptions(
      lead.customFields,
    );
    final effectivePrimary = isUsablePhoneNumber(lead.phone)
        ? lead.phone
        : (fallbackPhone ?? '');

    await LeadCallHelper.initiateLeadCall(
      context: context,
      leadId: lead.id,
      primaryPhone: effectivePrimary,
      alternatePhone: lead.alternatePhone,
      extraOptions: customPhoneOptions,
      leadName: leadName,
      preferredPhone: preferredPhone,
      onBeforeDial: () {
        _lastCallTimestamp = DateTime.now().millisecondsSinceEpoch;
      },
      onDial: (selectedNumber) async {
        if (!mounted) return;
        AutoCallRecordingUploader.makeCallAndAutoUpload(
          context: context,
          leadId: lead.id,
          phoneNumber: selectedNumber,
          leadName: leadName,
          onUploadSuccess: () {
            if (mounted) {
              context.read<LeadsBloc>().add(FetchLeadAudios(lead.id));
              context.read<LeadsBloc>().add(FetchLeadCallLogs(lead.id));
              _fetchLocalRecordings(
                selectedNumber,
                _collectUsableLeadPhones(lead),
              );
            }
          },
        );
      },
    );
  }

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
      for (final c in _trackedCallHistory) {
        if (AutoCallRecordingUploader.phonesMatch(c.phoneNumber, phoneNumber)) {
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
    _loadDropdownData();
    StaffPhoneResolver.getOrFetchStaffPhone().then((phone) {
      if (mounted) setState(() {});
    });
  }

  void _loadDropdownData() async {
    try {
      final cachedSources = LeadsBloc.cachedSources;
      if (cachedSources != null && cachedSources.isNotEmpty) {
        if (mounted) setState(() => _availableSources = List<LeadSource>.from(cachedSources));
      } else if (sl.isRegistered<GetLeadSourcesUseCase>()) {
        final res = await sl<GetLeadSourcesUseCase>()();
        res.fold((_) {}, (sources) {
          if (mounted) setState(() => _availableSources = sources);
        });
      }

      final cachedOwners = LeadsBloc.cachedOwners;
      if (cachedOwners != null && cachedOwners.isNotEmpty) {
        final sortedOwners = cachedOwners.cast<StaffUser>().toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        if (mounted) setState(() => _availableOwners = sortedOwners);
      } else if (sl.isRegistered<GetStaffUsersUseCase>()) {
        final res = await sl<GetStaffUsersUseCase>()();
        res.fold((_) {}, (owners) {
          final sortedOwners = List<StaffUser>.from(owners)
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
          if (mounted) setState(() => _availableOwners = sortedOwners);
        });
      }

      final cachedPriorities = LeadsBloc.cachedPriorities;
      if (cachedPriorities != null && cachedPriorities.isNotEmpty) {
        if (mounted) setState(() => _availablePriorities = List<String>.from(cachedPriorities));
      } else if (sl.isRegistered<GetLeadPrioritiesUseCase>()) {
        final res = await sl<GetLeadPrioritiesUseCase>()();
        res.fold((_) {}, (priorities) {
          if (mounted && priorities.isNotEmpty) {
            setState(() => _availablePriorities = priorities);
          }
        });
      }
    } catch (_) {}
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
      _triggerAutoSync();
    }
  }

  void _triggerAutoSync() {
    if (!mounted) return;
    final blocState = context.read<LeadsBloc>().state;
    final detailsState = blocState is LeadDetailsLoaded
        ? blocState
        : _lastDetailsLoadedState;
    final lead = detailsState?.leadDetail ?? _lastLeadDetail;

    if (lead != null) {
      _triggerFastResumeRecordingSync(lead, detailsState);
    }
  }

  bool _isResumeSyncInProgress = false;

  void _triggerFastResumeRecordingSync(
    LeadDetail lead,
    LeadDetailsLoaded? blocState,
  ) {
    if (_isResumeSyncInProgress) return;
    final phones = _collectUsableLeadPhones(lead);
    if (phones.isEmpty) return;
    _isResumeSyncInProgress = true;

    Future.delayed(const Duration(milliseconds: 2000), () async {
      if (!mounted) {
        _isResumeSyncInProgress = false;
        return;
      }
      try {
        for (final scanPhone in phones) {
          if (!mounted) break;
          await AutoCallRecordingUploader.autoScanAndUploadLeadRecordings(
            context: context,
            leadId: lead.id,
            phoneNumber: scanPhone,
            existingServerAudios: blocState?.audios,
            existingServerCallLogs: blocState?.callLogs?.callHistory,
            onUploadSuccess: () {
              if (mounted) {
                context.read<LeadsBloc>().add(FetchLeadAudios(lead.id));
                context.read<LeadsBloc>().add(FetchLeadCallLogs(lead.id));
                _fetchLocalRecordings(scanPhone, phones);
              }
            },
          );
        }
      } finally {
        _isResumeSyncInProgress = false;
      }
    });
  }

  void _fetchLeadStatuses() async {
    final cached = LeadsBloc.cachedStatuses;
    if (cached != null && cached.isNotEmpty) {
      if (mounted) {
        setState(() {
          _availableStatuses = cached.cast<LeadStatus>().toList();
        });
      }
      return;
    }
    final result = await sl<SettingsRepository>().getLeadStatuses();
    result.fold((_) {}, (statuses) {
      if (mounted) {
        setState(() {
          _availableStatuses = statuses;
        });
      }
    });
  }

  List<String> _collectUsableLeadPhones(LeadDetail? lead) {
    if (lead == null) return const [];
    final seenKeys = <String>{};
    final result = <String>[];
    void addIfUsable(String? raw) {
      if (!AutoCallRecordingUploader.isUsablePhone(raw)) return;
      final trimmed = raw!.trim();
      final digits = AutoCallRecordingUploader.usablePhoneDigits(trimmed);
      final key = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
      if (seenKeys.add(key)) {
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

  void _fetchLocalRecordings(
    String phoneNumber, [
    List<String>? allLeadPhones,
  ]) async {
    if (_isLoadingRecordings) return;
    final phonesToQuery = <String>[];
    final seenKeys = <String>{};
    for (final raw in [phoneNumber, ...?allLeadPhones]) {
      if (!AutoCallRecordingUploader.isUsablePhone(raw)) continue;
      final digits = AutoCallRecordingUploader.usablePhoneDigits(raw);
      final key = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
      if (seenKeys.add(key)) {
        phonesToQuery.add(raw.trim());
      }
    }
    if (phonesToQuery.isEmpty) {
      if (mounted && _localRecordings.isNotEmpty) {
        setState(() => _localRecordings = []);
      }
      return;
    }

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
        final merged = <Map<String, dynamic>>[];
        final seenPaths = <String>{};
        for (final queryPhone in phonesToQuery) {
          final paths = await callRecordingService.getAllSystemRecordings(
            queryPhone,
          );
          for (final rec in paths) {
            final recPath = rec['path']?.toString() ?? '';
            if (recPath.isNotEmpty && seenPaths.add(recPath)) {
              merged.add(rec);
            }
          }
        }
        if (!mounted) return;
        setState(() {
          _localRecordings = merged;
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
        if (diff1 < 8000 || diff2 < 8000) {
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
        if (sysStart > 0 && (sysStart - audioMs).abs() < 8000) {
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

  String _resolveLeadPhone(LeadDetail? lead) {
    final phones = _collectUsableLeadPhones(lead);
    return phones.isNotEmpty ? phones.first : '';
  }


  @override
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
                if (state is LeadDetailsLoaded) {
                  _lastLeadDetail = state.leadDetail;
                  _lastDetailsLoadedState = state;
                }
                final effectiveLead = state is LeadDetailsLoaded
                    ? state.leadDetail
                    : _lastLeadDetail;
                final leadPhone = _resolveLeadPhone(effectiveLead);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.phone, color: AppColors.primary),
                      tooltip: 'Call Lead',
                      onPressed: () async {
                        if (effectiveLead != null && leadPhone.isNotEmpty) {
                          await _initiateLeadDetailCall(
                            lead: effectiveLead,
                            leadName:
                                '${effectiveLead.firstName} ${effectiveLead.lastName}'
                                    .trim(),
                            fallbackPhone: leadPhone,
                          );
                        } else if (effectiveLead != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'No phone number available for this lead',
                              ),
                              backgroundColor: AppColors.primary,
                            ),
                          );
                        }
                      },
                    ),
                    if (sl<PrivilegeService>().hasPrivilege('LEAD_UPDATE'))
                      IconButton(
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: AppColors.textPrimary,
                        ),
                        tooltip: 'Edit Lead',
                        onPressed: () {
                          if (effectiveLead != null) {
                            _navigateToEditForm(
                              context,
                              effectiveLead,
                              targetFieldKey: null,
                            );
                          }
                        },
                      ),
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert,
                        color: AppColors.textPrimary,
                      ),
                      tooltip: 'More options',
                      onSelected: (value) async {
                        if (value == 'toggle_status' && effectiveLead != null) {
                          final isDeactivating = widget.isActive;
                          final action = isDeactivating
                              ? 'Deactivate'
                              : 'Activate';
                          final leadName =
                              '${effectiveLead.firstName} ${effectiveLead.lastName}'
                                  .trim();
                          final confirmed = await ConfirmationDialog.show(
                            context,
                            title: '$action Lead',
                            message:
                                'Are you sure you want to ${action.toLowerCase()}${leadName.isNotEmpty ? ' $leadName' : ' this lead'}?',
                            confirmLabel: action,
                            isDestructive: isDeactivating,
                          );

                          if (confirmed == true && context.mounted) {
                            context.read<LeadsBloc>().add(
                              UpdateLeadActiveStatus(
                                leadId: effectiveLead.id,
                                isActive: !widget.isActive,
                              ),
                            );
                          }
                        }
                      },
                      itemBuilder: (context) => [
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
              if (state.leadDetail.id != widget.leadId) return;
              final leadId = state.leadDetail.id;
              if (!_hasFetchedFollowUp &&
                  !_isLoadingFollowUp &&
                  _followUpError == null) {
                _fetchFollowUpDetails(leadId);
              }
              if (state.audios != null &&
                  state.callLogs != null &&
                  !_scannedLeadIds.contains(leadId)) {
                _scannedLeadIds.add(leadId);
                _triggerAutoSync();
              }
            } else if (state is LeadActionSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.green,
                ),
              );
              if (state.message.toLowerCase().contains('activate')) {
                Navigator.pop(context, true);
              }
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
            final matchingLoadedState =
                (state is LeadDetailsLoaded &&
                        state.leadDetail.id == widget.leadId)
                    ? state
                    : null;
            if (matchingLoadedState != null) {
              _lastLeadDetail = matchingLoadedState.leadDetail;
              _lastDetailsLoadedState = matchingLoadedState;
            }

            final effectiveState =
                matchingLoadedState ?? _lastDetailsLoadedState;

            if (_lastLeadDetail == null || effectiveState == null) {
              if (state is LeadDetailsLoading || state is LeadActionLoading) {
                return const Center(child: SpinningLogo(size: 60));
              } else if (state is LeadDetailsError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          state.message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey.shade200,
                                foregroundColor: Colors.black87,
                              ),
                              child: const Text('Go Back'),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: () {
                                context.read<LeadsBloc>().add(
                                  FetchLeadDetails(widget.leadId),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }
              return const Center(child: SpinningLogo(size: 60));
            }

            final lead = _lastLeadDetail!;
            final fullName = '${lead.firstName} ${lead.lastName}'.trim();
            final displayName = fullName.isNotEmpty
                ? fullName
                : (lead.companyName.isNotEmpty
                      ? lead.companyName
                      : 'Unnamed Lead');

            final statusColor = lead.status?.color != null
                ? _hexToColor(lead.status!.color)
                : AppColors.primary;

            final initials =
                (lead.firstName.isNotEmpty ? lead.firstName[0] : '') +
                (lead.lastName.isNotEmpty ? lead.lastName[0] : '');
            final effectiveInitials = initials.isNotEmpty
                ? initials
                : (displayName.isNotEmpty ? displayName[0] : 'L');

            final leadPhone = _resolveLeadPhone(lead);

            return SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── PROFILE HEADER CARD ───
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 6.0,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderEnabled),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            backgroundColor: const Color(0xFFFDE8E1),
                            radius: 18,
                            child: Text(
                              effectiveInitials.toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFFD97706),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (leadPhone.isNotEmpty && leadPhone != '-')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      leadPhone,
                                      style: const TextStyle(
                                        color: AppColors.textHint,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  lead.status?.statusName ?? 'Unknown',
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              if (leadPhone.isNotEmpty && leadPhone != '-') ...[
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () async {
                                    await _initiateLeadDetailCall(
                                      lead: lead,
                                      leadName: displayName,
                                      fallbackPhone: leadPhone,
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.phone,
                                      size: 18,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Tab Bar Headers
                  _buildTabBar(effectiveState),

                  // Active Tab Content
                  Expanded(
                    child: IndexedStack(
                      index: _activeTabIndex,
                      children: [
                        _buildOverviewTab(lead),
                        _buildFollowUpTab(lead),
                        LeadActivitiesTab(state: effectiveState),
                        LeadCallLogsTab(state: effectiveState),
                        LeadDocumentsTab(state: effectiveState),
                      ],
                    ),
                  ),
                ],
              ),
            );
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
          onChanged: (newStatusId) async {
            if (newStatusId != null && newStatusId != currentStatusId) {
              final currentStatus = _availableStatuses.firstWhere(
                (s) => s.id == currentStatusId,
                orElse: () =>
                    lead.status ??
                    const LeadStatusModel(
                      id: '',
                      statusName: '',
                      color: '',
                      isDefault: false,
                      isClosed: false,
                      displayOrder: 0,
                    ),
              );
              final targetStatus = _availableStatuses.firstWhere(
                (s) => s.id == newStatusId,
                orElse: () => const LeadStatusModel(
                  id: '',
                  statusName: '',
                  color: '',
                  isDefault: false,
                  isClosed: false,
                  displayOrder: 0,
                ),
              );

              // Only Admin & Superadmin can change from 3rd step to 1st step with confirmation
              if (currentStatus.level == 3 && targetStatus.level == 1) {
                final isAdmin = sl<PrivilegeService>().isAdminOrSuperAdmin();
                if (!isAdmin) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Only Admin and Super Admin can change status from Stage 3 to Stage 1.',
                        ),
                        backgroundColor: AppColors.primary,
                      ),
                    );
                  }
                  return;
                }
                final confirmed = await ConfirmationDialog.show(
                  context,
                  title: 'Confirm Status Change',
                  message:
                      'Are you sure you want to change status from "${currentStatus.statusName}" (Stage 3) back to "${targetStatus.statusName}" (Stage 1)?',
                  confirmLabel: 'Confirm Change',
                  isDestructive: false,
                );
                if (confirmed != true) return;
              }

              if (context.mounted) {
                _updateLeadStatus(context, lead, newStatusId);
              }
            }
          },
        ),
      ),
    );
  }

  Future<void> _openRescheduleScreen(
    LeadDetail lead, {
    FollowUp? selectedFollowUp,
  }) async {
    setState(() {
      _isRescheduleLoading = true;
    });

    try {
      if (selectedFollowUp == null && _allLeadFollowUps.isNotEmpty) {
        selectedFollowUp = _leadFollowUp ?? _allLeadFollowUps.first;
      }

      if (selectedFollowUp == null) {
        if (!mounted) return;
        _navigateToEditForm(context, lead, targetFieldKey: 'followup');
        return;
      }

      FollowUp? targetFollowUp = selectedFollowUp;

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EditFollowUpScreen(
            followUp: targetFollowUp!,
            leadDetail: lead,
            showOnlyLeadUpdate: true,
          ),
        ),
      );

      if (result == true && mounted) {
        _wasEdited = true;
        context.read<LeadsBloc>().add(FetchLeadDetails(lead.id));
        context.read<LeadsBloc>().add(FetchLeadAuditLogs(lead.id));
        _fetchFollowUpDetails(lead.id);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRescheduleLoading = false;
        });
      }
    }
  }

  Future<void> _fetchFollowUpDetails(String leadId) async {
    if (_isLoadingFollowUp) return;
    setState(() {
      _isLoadingFollowUp = true;
      _followUpError = null;
    });

    try {
      final repo = sl<FollowUpsRepository>();
      final res = await repo.getLeadFollowUps(leadId);

      if (!mounted) return;

      res.fold(
        (failure) {
          setState(() {
            _isLoadingFollowUp = false;
            _followUpError = failure.message;
          });
        },
        (leadFollowUps) {
          final list = leadFollowUps.followups;
          FollowUp? target;
          if (list.isNotEmpty) {
            final pendingList = list.where((f) {
              final st = f.followUpStatus.toUpperCase();
              return st != 'COMPLETED' && st != 'DONE';
            }).toList();
            target = pendingList.isNotEmpty ? pendingList.first : list.first;
          }

          setState(() {
            _isLoadingFollowUp = false;
            _hasFetchedFollowUp = true;
            _allLeadFollowUps = list;
            _leadFollowUp = target;
            if (list.isNotEmpty) {
              if (_getCategoryCount(_selectedFollowUpFilter) == 0) {
                if (_getCategoryCount('Today') > 0) {
                  _selectedFollowUpFilter = 'Today';
                } else if (_getCategoryCount('Upcoming') > 0) {
                  _selectedFollowUpFilter = 'Upcoming';
                } else if (_getCategoryCount('Missed') > 0) {
                  _selectedFollowUpFilter = 'Missed';
                } else {
                  _selectedFollowUpFilter = 'All';
                }
              }
            } else {
              _selectedFollowUpFilter = 'Today';
            }
          });
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFollowUp = false;
          _followUpError = e.toString();
        });
      }
    }
  }

  String _getFollowUpCategory(FollowUp f) {
    final status = f.followUpStatus.toUpperCase();
    if (status == 'COMPLETED' || status == 'DONE') return 'Completed';

    if (f.followUpType != null && f.followUpType!.isNotEmpty) {
      final type = f.followUpType!.toUpperCase();
      if (type == 'MISSED') return 'Missed';
      if (type == 'TODAY') return 'Today';
      if (type == 'UPCOMING') return 'Upcoming';
    }

    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    try {
      final d = DateTime.parse(f.followUpDate);
      final fDate = DateTime(d.year, d.month, d.day);
      if (fDate.isBefore(todayDate)) return 'Missed';
      if (fDate.isAtSameMomentAs(todayDate)) return 'Today';
      if (fDate.isAfter(todayDate)) return 'Upcoming';
    } catch (_) {}

    return 'Upcoming';
  }

  List<FollowUp> _getFilteredFollowUps() {
    if (_selectedFollowUpFilter == 'All') return _allLeadFollowUps;
    return _allLeadFollowUps
        .where((f) => _getFollowUpCategory(f) == _selectedFollowUpFilter)
        .toList();
  }

  int _getCategoryCount(String category) {
    if (category == 'All') return _allLeadFollowUps.length;
    return _allLeadFollowUps
        .where((f) => _getFollowUpCategory(f) == category)
        .length;
  }

  String _formatFollowUpDate(String dateStr) {
    if (dateStr.isEmpty) return 'Date not set';
    try {
      final parsed = DateTime.parse(dateStr);
      return DateFormat('dd MMM yyyy').format(parsed);
    } catch (_) {
      return dateStr;
    }
  }

  Widget _buildFollowUpTab(LeadDetail lead) {
    if (_isLoadingFollowUp) {
      return const Center(child: SpinningLogo(size: 40));
    }

    if (_followUpError != null && _allLeadFollowUps.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF1F2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.event_note_rounded,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Could Not Load Follow-ups',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _followUpError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _fetchFollowUpDetails(lead.id),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _navigateToEditForm(
                      context,
                      lead,
                      targetFieldKey: 'followup',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(
                      Icons.add_task_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    label: const Text(
                      'Schedule Follow-up',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final categories = ['Missed', 'Today', 'Upcoming', 'Completed', 'All'];
    final filteredFollowUps = _getFilteredFollowUps();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── CATEGORY FILTER CHIPS ROW ──────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final isSelected = _selectedFollowUpFilter == cat;
                final count = _getCategoryCount(cat);
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedFollowUpFilter = cat;
                      });
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.secondary
                            : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.borderEnabled,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            cat,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary
                                  : const Color(0xFFF1F5F9),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // ─── 3. FOLLOW-UPS ITEM LIST / EMPTY STATE ─────────────────────────────
          if (filteredFollowUps.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderEnabled),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.event_available_rounded,
                      size: 36,
                      color: AppColors.textHint,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _selectedFollowUpFilter == 'All'
                        ? 'No Follow-ups'
                        : 'No $_selectedFollowUpFilter Follow-ups',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedFollowUpFilter == 'All'
                        ? 'There are currently no follow-ups scheduled for this lead.'
                        : 'There are currently no ${_selectedFollowUpFilter.toLowerCase()} follow-ups scheduled for this lead.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (_allLeadFollowUps.isNotEmpty &&
                      _selectedFollowUpFilter != 'All') ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => _selectedFollowUpFilter = 'All'),
                      icon: const Icon(Icons.list_alt_rounded, size: 16),
                      label: Text(
                        'View All Follow-ups (${_allLeadFollowUps.length})',
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _navigateToEditForm(
                        context,
                        lead,
                        targetFieldKey: 'followup',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(
                        Icons.add_task_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      label: const Text(
                        'Schedule Follow-up',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredFollowUps.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = filteredFollowUps[index];
                return _buildFollowUpItemCard(lead, item);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFollowUpItemCard(LeadDetail lead, FollowUp item) {
    final cat = _getFollowUpCategory(item);

    Color catBg;
    Color catFg;
    if (cat == 'Today') {
      catBg = const Color(0xFFFEF3C7);
      catFg = const Color(0xFFD97706);
    } else if (cat == 'Missed') {
      catBg = AppColors.secondary;
      catFg = AppColors.primary;
    } else if (cat == 'Upcoming') {
      catBg = const Color(0xFFE0F2FE);
      catFg = const Color(0xFF0284C7);
    } else {
      catBg = const Color(0xFFDCFCE7);
      catFg = const Color(0xFF16A34A);
    }

    final formattedDate = _formatFollowUpDate(item.followUpDate);
    final statusText = item.followUpStatus.isNotEmpty
        ? item.followUpStatus
        : (item.leadStatus?.statusName ?? 'ADDED TO FOLLOW UP');

    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderEnabled),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.calendar_today_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          formattedDate,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (item.followUpTime.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color: AppColors.textHint,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            item.followUpTime,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: catBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            cat.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: catFg,
                            ),
                          ),
                        ),
                        if (item.leadTask.isNotEmpty &&
                            !item.leadTask.toLowerCase().contains(
                              'no follow',
                            ) &&
                            item.leadTask.toLowerCase().trim() !=
                                statusText.toLowerCase().trim())
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6FFFA),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF99F6E4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF0D9488),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  item.leadTask,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0D9488),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (item.reminder.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.borderEnabled),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  size: 14,
                  color: AppColors.textHint,
                ),
                const SizedBox(width: 4),
                Text(
                  'Reminder: ${item.reminder}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.borderEnabled),
                ),
                child: Text(
                  statusText.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    _openRescheduleScreen(lead, selectedFollowUp: item),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.borderEnabled),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(
                  Icons.sync_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                label: const Text(
                  'Reschedule',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
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
      // 'priority': lead.priority,
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
      // 'ownerUserId': lead.ownerUserId,
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
                if (index == 1 && !_hasFetchedFollowUp && !_isLoadingFollowUp) {
                  _fetchFollowUpDetails(state.leadDetail.id);
                } else if (index == 2 &&
                    state.auditLogs == null &&
                    !state.isAuditLogsLoading) {
                  context.read<LeadsBloc>().add(
                    FetchLeadAuditLogs(state.leadDetail.id),
                  );
                } else if (index == 3) {
                  _fetchLocalRecordings(
                    _resolveLeadPhone(state.leadDetail),
                    _collectUsableLeadPhones(state.leadDetail),
                  );
                  if (state.callLogs == null && !state.isCallLogsLoading) {
                    context.read<LeadsBloc>().add(
                      FetchLeadCallLogs(state.leadDetail.id),
                    );
                  }
                  if (state.audios == null && !state.isAudiosLoading) {
                    context.read<LeadsBloc>().add(
                      FetchLeadAudios(state.leadDetail.id),
                    );
                  }
                } else if (index == 4 &&
                    state.attachments == null &&
                    !state.isAttachmentsLoading) {
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
              fieldKey: 'email',
              lead: lead,
            ),
            _buildInfoRow(
              Icons.phone_outlined,
              'Phone',
              lead.phone,
              fieldKey: 'phone',
              lead: lead,
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
                            await _initiateLeadDetailCall(
                              lead: lead,
                              leadName: '${lead.firstName} ${lead.lastName}'
                                  .trim(),
                              preferredPhone: lead.phone,
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
                fieldKey: 'alternatePhone',
                lead: lead,
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
                        await _initiateLeadDetailCall(
                          lead: lead,
                          leadName: '${lead.firstName} ${lead.lastName}'.trim(),
                          preferredPhone: lead.alternatePhone,
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
                fieldKey: 'website',
                lead: lead,
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
              fieldKey: 'address',
              lead: lead,
            ),
          ]),
          const SizedBox(height: 16),

          // Additional Details Card
          _buildInfoCard('Additional Information', [
            _buildInfoRow(
              Icons.person_outline,
              'Owner',
              lead.ownerUserName ?? 'Unassigned',
              fieldKey: sl<PrivilegeService>().canAssignLeads()
                  ? 'ownerUserId'
                  : null,
              lead: lead,
            ),
            if (lead.priority != null)
              _buildInfoRow(
                Icons.flag_outlined,
                'Priority',
                lead.priority!,
                fieldKey: 'priority',
                lead: lead,
              ),
            if (lead.source?.name != null)
              _buildInfoRow(
                Icons.share_outlined,
                'Source',
                lead.source!.name,
                fieldKey: 'sourceId',
                lead: lead,
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
                fieldKey: 'description',
                lead: lead,
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
                  fieldKey: isAttachment
                      ? null
                      : 'customField_${field.fieldId}',
                  onEditTap: isAttachment
                      ? () => _navigateToEditForm(
                          context,
                          lead,
                          targetFieldKey: 'customField_${field.fieldId}',
                        )
                      : null,
                  lead: lead,
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
        lowerRaw.contains('unanswered') ||
        lowerRaw.contains('not_connected')) {
      return isIncoming ? 'Missed Call' : 'Not Connected Call';
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
        return isIncoming ? 'Missed Call' : 'Not Connected Call';
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
    if (!sl<PrivilegeService>().hasPrivilege('LEAD_UPDATE')) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider<LeadsBloc>(
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
        context.read<LeadsBloc>().add(FetchLeadAuditLogs(lead.id));
        _fetchFollowUpDetails(lead.id);
      }
    });
  }

  void _startEditingField(
    String fieldKey,
    String currentValue,
    LeadDetail? lead,
  ) {
    setState(() {
      _editingFieldKey = fieldKey;
      if (fieldKey == 'ownerUserId') {
        _selectedDropdownValue =
            lead?.ownerUserId ??
            (_availableOwners.isNotEmpty
                ? _availableOwners.first.userId
                : null);
      } else if (fieldKey == 'priority') {
        final p = (lead?.priority ?? currentValue).toUpperCase();
        _selectedDropdownValue =
            _availablePriorities.map((x) => x.toUpperCase()).contains(p)
            ? p
            : (_availablePriorities.isNotEmpty
                  ? _availablePriorities.first.toUpperCase()
                  : 'LOW');
      } else if (fieldKey == 'sourceId') {
        _selectedDropdownValue =
            lead?.source?.id ??
            (_availableSources.isNotEmpty ? _availableSources.first.id : null);
      } else {
        _inlineEditController.text = currentValue;
      }
    });
  }

  String _getEditingValue(String fieldKey) {
    if (fieldKey == 'ownerUserId' ||
        fieldKey == 'priority' ||
        fieldKey == 'sourceId') {
      return _selectedDropdownValue ?? '';
    }
    return _inlineEditController.text;
  }

  Widget _buildInlineEditorWidget(String fieldKey, LeadDetail? lead) {
    if (fieldKey == 'ownerUserId') {
      return Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary, width: 1.5),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value:
                _selectedDropdownValue != null &&
                    _availableOwners.any(
                      (o) => o.userId == _selectedDropdownValue,
                    )
                ? _selectedDropdownValue
                : (_availableOwners.isNotEmpty
                      ? _availableOwners.first.userId
                      : null),
            isExpanded: true,
            isDense: true,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            onChanged: (val) {
              if (val != null) setState(() => _selectedDropdownValue = val);
            },
            items:
                (_availableOwners.toList()..sort(
                      (a, b) =>
                          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                    ))
                    .map((owner) {
                      return DropdownMenuItem<String>(
                        value: owner.userId,
                        child: Text(
                          owner.name,
                          style: const TextStyle(fontSize: 14),
                        ),
                      );
                    })
                    .toList(),
          ),
        ),
      );
    }

    if (fieldKey == 'priority') {
      return Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary, width: 1.5),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value:
                _selectedDropdownValue != null &&
                    _availablePriorities
                        .map((p) => p.toUpperCase())
                        .contains(_selectedDropdownValue!.toUpperCase())
                ? _selectedDropdownValue!.toUpperCase()
                : (_availablePriorities.isNotEmpty
                      ? _availablePriorities.first.toUpperCase()
                      : 'LOW'),
            isExpanded: true,
            isDense: true,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            onChanged: (val) {
              if (val != null) setState(() => _selectedDropdownValue = val);
            },
            items: _availablePriorities.map((priority) {
              final upper = priority.toUpperCase();
              return DropdownMenuItem<String>(
                value: upper,
                child: Text(upper, style: const TextStyle(fontSize: 14)),
              );
            }).toList(),
          ),
        ),
      );
    }

    if (fieldKey == 'sourceId') {
      return Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary, width: 1.5),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value:
                _selectedDropdownValue != null &&
                    _availableSources.any((s) => s.id == _selectedDropdownValue)
                ? _selectedDropdownValue
                : (_availableSources.isNotEmpty
                      ? _availableSources.first.id
                      : null),
            isExpanded: true,
            isDense: true,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            onChanged: (val) {
              if (val != null) setState(() => _selectedDropdownValue = val);
            },
            items: _availableSources.map((source) {
              return DropdownMenuItem<String>(
                value: source.id,
                child: Text(source.name, style: const TextStyle(fontSize: 14)),
              );
            }).toList(),
          ),
        ),
      );
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: TextField(
        controller: _inlineEditController,
        autofocus: true,
        style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  void _saveInlineEdit(
    BuildContext context,
    LeadDetail lead,
    String fieldKey,
    String newValue,
  ) {
    final leadData = <String, dynamic>{
      'firstName': lead.firstName,
      'lastName': lead.lastName,
      'companyName': lead.companyName,
      'email': lead.email,
      'phone': lead.phone,
      'alternatePhone': lead.alternatePhone,
      'sourceId': lead.source?.id,
      'statusId': lead.status?.id,
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

    if (fieldKey.startsWith('customField_')) {
      final fieldId = fieldKey.replaceFirst('customField_', '');
      final List<Map<String, dynamic>> updatedCustomFields = [];
      for (final cf in lead.customFields) {
        if (cf.fieldId == fieldId) {
          updatedCustomFields.add({
            'fieldId': cf.fieldId,
            'label': cf.label,
            'fieldType': cf.fieldType,
            'value': newValue.trim(),
          });
        } else {
          updatedCustomFields.add({
            'fieldId': cf.fieldId,
            'label': cf.label,
            'fieldType': cf.fieldType,
            'value': cf.value,
          });
        }
      }
      leadData['customFields'] = updatedCustomFields;
    } else {
      leadData[fieldKey] = newValue.trim();
    }

    leadData.removeWhere((key, value) => value == null);

    context.read<LeadsBloc>().add(
      UpdateLead(leadId: lead.id, leadData: leadData, filePaths: []),
    );
    setState(() {
      _editingFieldKey = null;
    });
    _wasEdited = true;
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    String? subvalue,
    Widget? trailing,
    String? fieldKey,
    LeadDetail? lead,
    VoidCallback? onEditTap,
  }) {
    final bool isEditing = fieldKey != null && _editingFieldKey == fieldKey;

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
              const SizedBox(height: 4),
              if (isEditing)
                Row(
                  children: [
                    Expanded(child: _buildInlineEditorWidget(fieldKey, lead)),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        if (lead != null && fieldKey != null) {
                          _saveInlineEdit(
                            context,
                            lead,
                            fieldKey,
                            _getEditingValue(fieldKey),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _editingFieldKey = null;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE2E8F0),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: AppColors.textSecondary,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                )
              else ...[
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
            ],
          ),
        ),
        if (!isEditing && trailing != null) trailing,
        if (!isEditing &&
            sl<PrivilegeService>().hasPrivilege('LEAD_UPDATE') &&
            (fieldKey != 'ownerUserId' ||
                sl<PrivilegeService>().canAssignLeads()) &&
            (fieldKey != null || onEditTap != null))
          IconButton(
            icon: const Icon(
              Icons.edit_outlined,
              size: 18,
              color: AppColors.textHint,
            ),
            onPressed: () {
              if (fieldKey != null) {
                _startEditingField(fieldKey, value, lead);
              } else if (onEditTap != null) {
                onEditTap();
              }
            },
            tooltip: 'Edit $label',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
      ],
    );
  }
}
