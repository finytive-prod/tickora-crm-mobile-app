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
import 'package:path_provider/path_provider.dart';
import 'package:crm_mobile/core/services/call_recording_service.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_constants.dart';
import 'package:crm_mobile/models/call_history.dart';
import 'package:crm_mobile/core/services/call_history_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';
import 'package:crm_mobile/screens/leads/add_lead_screen.dart';
import 'package:crm_mobile/screens/followups/add_followup_screen.dart';

class LeadDetailsScreen extends StatelessWidget {
  final String leadId;
  final bool isActive;
  const LeadDetailsScreen({super.key, required this.leadId, this.isActive = true});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<LeadsBloc>()..add(FetchLeadDetails(leadId)),
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
  final List<String> _tabs = ['Overview', 'Activities', 'Call Log(s)', 'Documents'];
  final TextEditingController _noteController = TextEditingController();
  
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

    // 1. Check tracked call history for matching call timestamp within 5 minutes
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

          if (diff1 < 5 * 60 * 1000 || diff2 < 5 * 60 * 1000) {
            final typeStr = c.callType.toLowerCase();
            final resolved = (typeStr == 'outgoing' || typeStr == 'outbound') ? 'outbound' : 'inbound';
            _resolvedCallTypes[audio.id] = resolved;
            return resolved;
          }
        }
      }
    }

    // 2. Check last call timestamp if user placed call in this session within 3 minutes
    if (_lastCallTimestamp != null && audioMs > 0) {
      final diff = (audioMs - _lastCallTimestamp!).abs();
      if (diff < 3 * 60 * 1000) {
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
      if (rawTime.contains('AM') || rawTime.contains('PM') || rawTime.contains('am') || rawTime.contains('pm')) {
        return rawTime;
      }
      final parts = rawTime.split(':');
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

    final staffUser = (savedName != null && savedName.isNotEmpty)
        ? savedName
        : ((savedPhone != null && savedPhone.isNotEmpty) ? savedPhone : 'Staff');

    final cleanLeadPhone = leadPhone.isNotEmpty ? leadPhone : 'Lead';

    if (audio.fromNumber != null && audio.fromNumber!.isNotEmpty) {
      fromPhone = audio.fromNumber!;
    }
    if (audio.toNumber != null && audio.toNumber!.isNotEmpty) {
      toPhone = audio.toNumber!;
    }

    if (fromPhone.isEmpty || toPhone.isEmpty) {
      final matches = RegExp(r'(\+?[6-9]\d{9}|\+?\d{10,12})').allMatches('${audio.displayName} ${audio.fileName}');
      final validNumbers = <String>[];

      for (final m in matches) {
        final numStr = m.group(0)!;
        if (!numStr.startsWith('202') && !numStr.startsWith('203')) {
          if (!validNumbers.contains(numStr)) {
            validNumbers.add(numStr);
          }
        }
      }

      if (isIncoming) {
        if (fromPhone.isEmpty) fromPhone = validNumbers.isNotEmpty ? validNumbers[0] : cleanLeadPhone;
        if (toPhone.isEmpty) toPhone = staffUser;
      } else {
        if (fromPhone.isEmpty) fromPhone = staffUser;
        if (toPhone.isEmpty) toPhone = validNumbers.isNotEmpty ? validNumbers[0] : cleanLeadPhone;
      }
    }

    String startStr = '--:--';
    String endStr = '--:--';
    String durationStr = '';

    final startDt = audio.createdAt ?? DateTime.now();
    startStr = DateFormat('hh:mm:ss a').format(startDt);

    if (audio.startTimeStr != null && audio.startTimeStr!.isNotEmpty) {
      final formattedStart = _formatTimeString(audio.startTimeStr);
      if (formattedStart != null) startStr = formattedStart;
    }

    if (audio.endTimeStr != null && audio.endTimeStr!.isNotEmpty) {
      final formattedEnd = _formatTimeString(audio.endTimeStr);
      if (formattedEnd != null) endStr = formattedEnd;
    }

    int durationSec = audio.durationSeconds;

    if (durationSec <= 0 && _resolvedAudioDurations.containsKey(audio.id)) {
      durationSec = _resolvedAudioDurations[audio.id]!;
    }

    final effectiveLocals = localRecordings ?? _localRecordings;
    if (durationSec <= 0 && effectiveLocals.isNotEmpty) {
      final cleanServerName = AutoCallRecordingUploader.cleanFileName(audio.displayName.toLowerCase());
      for (final local in effectiveLocals) {
        final localPath = local['path']?.toString() ?? '';
        final localName = AutoCallRecordingUploader.cleanFileName(localPath.split('/').last.split('\\').last.toLowerCase());
        final localDurMs = (local['durationMs'] as num?)?.toInt() ?? 0;

        if (localDurMs > 0 && (localName == cleanServerName || localPath.contains(cleanServerName) || cleanServerName.contains(localName))) {
          durationSec = (localDurMs / 1000).round();
          _resolvedAudioDurations[audio.id] = durationSec;
          break;
        }
      }
    }

    final effectiveTracked = trackedCalls ?? _trackedCallHistory;
    if (durationSec <= 0 && effectiveTracked.isNotEmpty) {
      final audioMs = startDt.millisecondsSinceEpoch;
      for (final c in effectiveTracked) {
        final diff1 = (c.timestamp - audioMs).abs();
        final diff2 = (c.startTime - audioMs).abs();
        if (diff1 < 900000 || diff2 < 900000) {
          if (c.durationSeconds > 0) {
            durationSec = c.durationSeconds;
            _resolvedAudioDurations[audio.id] = durationSec;
          }
          if (c.appUserPhone != null && c.appUserPhone!.isNotEmpty) {
            if (isIncoming) {
              toPhone = c.appUserPhone!;
            } else {
              fromPhone = c.appUserPhone!;
            }
          }
          if (c.phoneNumber.isNotEmpty) {
            if (isIncoming) {
              fromPhone = c.phoneNumber;
            } else {
              toPhone = c.phoneNumber;
            }
          }
          break;
        }
      }
    }

    if (durationSec <= 0 && systemLogs != null && systemLogs.isNotEmpty) {
      final audioMs = startDt.millisecondsSinceEpoch;
      for (final sys in systemLogs) {
        final sysStart = sys['startTime'] as int? ?? 0;
        final sysDur = sys['durationSeconds'] as int? ?? 0;
        if (sysStart > 0 && (sysStart - audioMs).abs() < 900000) {
          if (sysDur > 0) {
            durationSec = sysDur;
            _resolvedAudioDurations[audio.id] = durationSec;
            break;
          }
        }
      }
    }

    // Final fallback estimate from file size if duration is still unpopulated
    if (durationSec <= 0 && audio.size > 0) {
      durationSec = (audio.size / 2500).round();
      if (durationSec < 1) durationSec = 1;
      _resolvedAudioDurations[audio.id] = durationSec;
    }

    if (durationSec > 0) {
      if (endStr == '--:--') {
        final endDt = startDt.add(Duration(seconds: durationSec));
        endStr = DateFormat('hh:mm:ss a').format(endDt);
      }
      final mins = durationSec ~/ 60;
      final secs = durationSec % 60;
      durationStr = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
    }

    return {
      'fromPhone': fromPhone,
      'toPhone': toPhone,
      'startTime': startStr,
      'endTime': endStr,
      'duration': durationStr,
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
              tooltip: 'Refresh Lead Details',
              onPressed: () {
                final state = context.read<LeadsBloc>().state;
                if (state is LeadDetailsLoaded) {
                  context.read<LeadsBloc>().add(FetchLeadDetails(state.leadDetail.id));
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
                        _buildCallRecordingsTab(state),
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
                  _callLogsFuture = null; // Invalidate cache to reload fresh data
                  _fetchLocalRecordings(state.leadDetail.phone);
                  context.read<LeadsBloc>().add(FetchLeadAudios(state.leadDetail.id));
                  AutoCallRecordingUploader.autoScanAndUploadLeadRecordings(
                    context: context,
                    leadId: state.leadDetail.id,
                    phoneNumber: state.leadDetail.phone,
                    existingServerAudios: state.audios,
                    onUploadSuccess: () {
                      if (mounted) {
                        context.read<LeadsBloc>().add(FetchLeadAudios(state.leadDetail.id));
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
                trailing: lead.phone.isNotEmpty ? IconButton(
                  icon: const Icon(Icons.phone, color: AppColors.primary),
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
                ) : null,
              ),
              if (lead.alternatePhone != null && lead.alternatePhone!.isNotEmpty)
                _buildInfoRow(
                  Icons.phone_iphone_outlined, 
                  'Alternate Phone', 
                  lead.alternatePhone!,
                  onEditTap: () => _navigateToEditForm(context, lead, targetFieldKey: 'alternatePhone'),
                  trailing: IconButton(
                    icon: const Icon(Icons.phone, color: AppColors.primary),
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
    if (audio.createdAt != null) {
      return audio.createdAt!.millisecondsSinceEpoch;
    }
    final name = audio.displayName.isNotEmpty ? audio.displayName : audio.fileName;

    // Pattern 1: YYMMDD_HHMMSS or YYYYMMDD_HHMMSS
    final match1 = RegExp(r'(\d{4}|\d{2})(\d{2})(\d{2})_?(\d{2})(\d{2})(\d{2})').firstMatch(name);
    if (match1 != null) {
      try {
        final yStr = match1.group(1)!;
        final year = yStr.length == 2 ? 2000 + int.parse(yStr) : int.parse(yStr);
        final month = int.parse(match1.group(2)!);
        final day = int.parse(match1.group(3)!);
        final hour = int.parse(match1.group(4)!);
        final min = int.parse(match1.group(5)!);
        final sec = int.parse(match1.group(6)!);
        return DateTime(year, month, day, hour, min, sec).millisecondsSinceEpoch;
      } catch (_) {}
    }

    // Pattern 2: Epoch ms timestamp
    final match2 = RegExp(r'\b(1\d{12})\b').firstMatch(name);
    if (match2 != null) {
      final ms = int.tryParse(match2.group(1)!);
      if (ms != null) return ms;
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

  String _recordingFilter = 'all'; // 'all', 'inbound', or 'outbound'

  Widget _buildCallRecordingsTab(LeadDetailsLoaded state) {
    // Eagerly fetch local recordings if not already done
    if (!_localRecordingsFetched) {
      _localRecordingsFetched = true;
      _fetchLocalRecordings(state.leadDetail.phone);
    }

    // Cache the future so it's not recreated on every build (Flutter anti-pattern)
    if (_callLogsFuture == null || _callLogsFuturePhone != state.leadDetail.phone) {
      _callLogsFuturePhone = state.leadDetail.phone;
      _callLogsFuture = Future.wait([
        CallHistoryStorage.loadCallHistory(),
        CallRecordingService().getSystemCallLogs(state.leadDetail.phone),
        CallRecordingService().getAllSystemRecordings(state.leadDetail.phone),
      ]);
    }

    return FutureBuilder<List<dynamic>>(
      future: _callLogsFuture,
      builder: (context, snapshot) {
        final trackedCalls = (snapshot.data != null && snapshot.data!.isNotEmpty)
            ? List<CallHistory>.from(snapshot.data![0] as List)
            : <CallHistory>[];
        final systemLogs = (snapshot.data != null && snapshot.data!.length > 1)
            ? List<Map<String, dynamic>>.from(snapshot.data![1] as List)
            : <Map<String, dynamic>>[];
        final futureLocalRecordings = (snapshot.data != null && snapshot.data!.length > 2)
            ? List<Map<String, dynamic>>.from(snapshot.data![2] as List)
            : <Map<String, dynamic>>[];

        // Use the best available source: FutureBuilder result > state variable
        final effectiveLocalRecordings = futureLocalRecordings.isNotEmpty 
            ? futureLocalRecordings 
            : _localRecordings;

        // Sync state variable if needed (for playback and other uses)
        if (futureLocalRecordings.isNotEmpty && _localRecordings.isEmpty) {
          _localRecordings = futureLocalRecordings;
        }

        debugPrint('--- CALL LOGS DEBUG ---');
        debugPrint('Tracked Calls loaded: ${trackedCalls.length}');
        debugPrint('System Logs loaded: ${systemLogs.length}');
        debugPrint('Local Recordings: ${effectiveLocalRecordings.length} (future=${futureLocalRecordings.length}, state=${_localRecordings.length})');

        // Merge native system call logs for missing server audio cases
        for (final sysLog in systemLogs) {
          final startTime = sysLog['startTime'] as int? ?? 0;
          final duration = sysLog['durationSeconds'] as int? ?? 0;
          final callType = (sysLog['callType'] as String? ?? 'OUTGOING').toUpperCase();
          final callStatus = (sysLog['callStatus'] as String? ?? (duration > 0 ? 'ANSWERED' : 'UNANSWERED')).toUpperCase();

          final sysHistory = CallHistory(
            id: sysLog['id']?.toString() ?? startTime.toString(),
            phoneNumber: sysLog['phoneNumber']?.toString() ?? state.leadDetail.phone,
            contactName: sysLog['contactName']?.toString(),
            callType: callType,
            timestamp: startTime,
            startTime: startTime,
            endTime: sysLog['endTime'] as int? ?? startTime,
            durationSeconds: duration,
            callStatus: callStatus,
          );

          // Find if there's an existing tracked call (like a dummy 0-duration entry from makeCall)
          // Find if there's an existing tracked call (like a dummy 0-duration entry from makeCall)
          final matchIndex = trackedCalls.indexWhere((t) {
            final timeDiff = (t.startTime - startTime).abs();
            final tDigits = t.phoneNumber.replaceAll(RegExp(r'\D'), '');
            final sysDigits = sysHistory.phoneNumber.replaceAll(RegExp(r'\D'), '');
            final tLast10 = tDigits.length >= 10 ? tDigits.substring(tDigits.length - 10) : tDigits;
            final sysLast10 = sysDigits.length >= 10 ? sysDigits.substring(sysDigits.length - 10) : sysDigits;
            final phoneMatch = (tLast10.isNotEmpty && sysLast10.isNotEmpty && tLast10 == sysLast10) ||
                tDigits == sysDigits ||
                (tLast10.isNotEmpty && sysDigits.contains(tLast10));
            return timeDiff < 60000 && phoneMatch;
          });
          if (matchIndex != -1) {
            // Update the existing tracked call with real duration and status
            final existing = trackedCalls[matchIndex];
            trackedCalls[matchIndex] = CallHistory(
              id: existing.id,
              phoneNumber: existing.phoneNumber,
              contactName: existing.contactName,
              callType: existing.callType,
              timestamp: existing.timestamp,
              startTime: existing.startTime,
              endTime: sysHistory.endTime,
              durationSeconds: sysHistory.durationSeconds > 0 ? sysHistory.durationSeconds : existing.durationSeconds,
              callStatus: sysHistory.callStatus,
              appUserId: existing.appUserId,
              appUserName: existing.appUserName,
              appUserPhone: existing.appUserPhone,
              isSynced: existing.isSynced,
            );
          } else {
            trackedCalls.add(sysHistory);
          }
        }

        // Auto-upload any unuploaded local recordings to backend server ONCE per lead visit
        if (effectiveLocalRecordings.isNotEmpty && _autoUploadedLeadId != state.leadDetail.id) {
          _autoUploadedLeadId = state.leadDetail.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            AutoCallRecordingUploader.autoScanAndUploadLeadRecordings(
              context: context,
              leadId: state.leadDetail.id,
              phoneNumber: state.leadDetail.phone,
              existingServerAudios: state.audios,
              onUploadSuccess: () {
                if (mounted) {
                  context.read<LeadsBloc>().add(FetchLeadAudios(state.leadDetail.id));
                }
              },
            );
          });
        }

        // Display strictly real server audios fetched from backend API
        final rawServerAudios = state.audios != null ? List<LeadAudio>.from(state.audios!) : <LeadAudio>[];

        final List<LeadAudio> sortedRaw = List.from(rawServerAudios);
        sortedRaw.sort(_compareByLatest);

        final List<LeadAudio> serverAudios = [];
        final Set<String> seenIds = {};
        final Set<String> seenAudioFileKeys = {};
        for (final audio in sortedRaw) {
          if (seenIds.contains(audio.id)) continue;
          seenIds.add(audio.id);

          if (audio.size > 0) {
            final cleanName = AutoCallRecordingUploader.cleanFileName(audio.displayName.toLowerCase());
            final cleanFileNameOnly = AutoCallRecordingUploader.cleanFileName(audio.fileName.toLowerCase());
            final key = cleanName.isNotEmpty ? cleanName : cleanFileNameOnly;
            if (key.isNotEmpty) {
              final fileKey = '${key}_${audio.size}';
              if (seenAudioFileKeys.contains(fileKey)) continue;
              seenAudioFileKeys.add(fileKey);
            }
          }

          serverAudios.add(audio);
        }

        serverAudios.sort(_compareByLatest);

        // Build unified list of call entries
        final List<_CallCardData> allEntries = [];

        for (final audio in serverAudios) {
          final isIncoming = _getResolvedCallType(audio, state.leadDetail.phone) == 'inbound';
          final callInfo = _getCallCardDetails(
            audio,
            state.leadDetail.phone,
            isIncoming,
            localRecordings: effectiveLocalRecordings,
            trackedCalls: trackedCalls,
            systemLogs: systemLogs,
          );
          final dateStr = audio.createdAt != null
              ? DateFormat('MMM dd, yyyy - hh:mm a').format(audio.createdAt!)
              : 'Unknown Date';
          final kb = audio.size / 1024;
          final mb = kb / 1024;
          final sizeStr = mb >= 1 ? '${mb.toStringAsFixed(1)} MB' : '${kb.toStringAsFixed(0)} KB';

          final lowerName = '${audio.displayName} ${audio.fileName}'.toLowerCase();
          final isMissedName = lowerName.contains('missed') || lowerName.contains('unanswered');
          final isUnansweredBound = audio.bound?.toUpperCase() == 'MISSED' || audio.bound?.toUpperCase() == 'UNANSWERED';
          final isZeroSize = audio.size <= 0;
          final isZeroDur = audio.durationSeconds <= 0;

          final isUnanswered = isMissedName || isUnansweredBound || isZeroSize || isZeroDur;

          allEntries.add(
            _CallCardData(
              audio: isUnanswered ? null : audio,
              timestamp: audio.createdAt ?? DateTime.now(),
              isIncoming: isIncoming,
              isUnanswered: isUnanswered,
              title: _cleanAudioTitle(audio.displayName, isIncoming: isIncoming, isUnanswered: isUnanswered),
              fromPhone: callInfo['fromPhone'] ?? '',
              toPhone: callInfo['toPhone'] ?? '',
              startTimeStr: callInfo['startTime'] ?? '',
              endTimeStr: callInfo['endTime'] ?? '',
              durationStr: callInfo['duration'] ?? '',
              sizeStr: isUnanswered ? 'No Audio' : sizeStr,
              dateStr: dateStr,
            ),
          );
        }

        // Merge local tracked calls & native system call logs for missed / unanswered / un-uploaded calls
        final leadPhoneDigits = state.leadDetail.phone.replaceAll(RegExp(r'\D'), '');
        final leadLast10 = leadPhoneDigits.length >= 10 ? leadPhoneDigits.substring(leadPhoneDigits.length - 10) : leadPhoneDigits;

        final prefs = sl.isRegistered<SharedPreferences>() ? sl<SharedPreferences>() : null;
        final savedName = prefs?.getString('userName')?.trim();
        final savedPhone = prefs?.getString('userPhone')?.trim();
        final staffUser = (savedName != null && savedName.isNotEmpty)
            ? savedName
            : ((savedPhone != null && savedPhone.isNotEmpty) ? savedPhone : 'Staff');

        for (final tracked in trackedCalls) {
          final tPhoneDigits = tracked.phoneNumber.replaceAll(RegExp(r'\D'), '');
          final tLast10 = tPhoneDigits.length >= 10 ? tPhoneDigits.substring(tPhoneDigits.length - 10) : tPhoneDigits;

          final isMatchLead = leadLast10.isEmpty || tLast10 == leadLast10 || tPhoneDigits.contains(leadLast10) || leadLast10.contains(tLast10);
          if (!isMatchLead) continue;

          final trackedStartTime = tracked.startTime > 0 ? tracked.startTime : tracked.timestamp;
          if (trackedStartTime <= 0) continue;

          // Check if already represented by an audio entry in serverAudios
          final isAlreadyAdded = allEntries.any((entry) {
            final entryMs = entry.timestamp.millisecondsSinceEpoch;
            final timeDiff = (entryMs - trackedStartTime).abs();
            if (timeDiff >= 30000) return false;
            final trackedIsIncoming = tracked.callType.toUpperCase() == 'INCOMING' || tracked.callType.toUpperCase() == 'INBOUND';
            return entry.isIncoming == trackedIsIncoming;
          });

          if (!isAlreadyAdded) {
            final isIncoming = tracked.callType.toUpperCase() == 'INCOMING' || tracked.callType.toUpperCase() == 'INBOUND';
            final isUnanswered = tracked.isUnanswered || tracked.durationSeconds <= 0;

            final dt = DateTime.fromMillisecondsSinceEpoch(trackedStartTime);
            final dateStr = DateFormat('MMM dd, yyyy - hh:mm a').format(dt);
            final startStr = DateFormat('hh:mm:ss a').format(dt);
            final endStr = tracked.endTime > 0 ? DateFormat('hh:mm:ss a').format(DateTime.fromMillisecondsSinceEpoch(tracked.endTime)) : '--:--';
            final durSec = tracked.durationSeconds;
            final durStr = durSec > 0 ? (durSec >= 60 ? '${durSec ~/ 60}m ${durSec % 60}s' : '${durSec}s') : '';

            final fromPhone = isIncoming ? state.leadDetail.phone : (tracked.appUserPhone ?? staffUser);
            final toPhone = isIncoming ? (tracked.appUserPhone ?? staffUser) : state.leadDetail.phone;

            final defaultTitle = isIncoming
                ? (isUnanswered ? 'Missed Call' : 'Incoming Call')
                : (isUnanswered ? 'Unanswered Call' : 'Outgoing Call');

            allEntries.add(
              _CallCardData(
                audio: null,
                history: tracked,
                timestamp: dt,
                isIncoming: isIncoming,
                isUnanswered: isUnanswered,
                title: tracked.contactName ?? defaultTitle,
                fromPhone: fromPhone,
                toPhone: toPhone,
                startTimeStr: startStr,
                endTimeStr: endStr,
                durationStr: durStr,
                sizeStr: 'No Audio',
                dateStr: dateStr,
              ),
            );
          }
        }

        allEntries.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        final inboundEntries = allEntries.where((a) => a.isIncoming).toList();
        final outboundEntries = allEntries.where((a) => !a.isIncoming).toList();

        final currentEntries = _recordingFilter == 'all'
            ? allEntries
            : _recordingFilter == 'inbound'
                ? inboundEntries
                : outboundEntries;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── TITLE & REFRESH BAR ──────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Call Recordings & Logs (${allEntries.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: state.isAudiosLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          )
                        : const Icon(Icons.refresh_rounded, color: AppColors.primary, size: 22),
                    tooltip: 'Refresh Call Recordings',
                    onPressed: state.isAudiosLoading
                        ? null
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Scanning phone for call recordings...'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                            AutoCallRecordingUploader.clearFailedUploads();
                            context.read<LeadsBloc>().add(FetchLeadAudios(state.leadDetail.id));
                            AutoCallRecordingUploader.autoScanAndUploadLeadRecordings(
                              context: context,
                              leadId: state.leadDetail.id,
                              phoneNumber: state.leadDetail.phone,
                              existingServerAudios: state.audios,
                              onUploadSuccess: () {
                                if (mounted) {
                                  context.read<LeadsBloc>().add(FetchLeadAudios(state.leadDetail.id));
                                }
                              },
                            );
                          },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (state.isAudiosLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12.0),
                  child: LinearProgressIndicator(color: AppColors.primary, backgroundColor: Color(0xFFE5E7EB)),
                ),

              // ─── FILTER SUB-TABS (All, Inbound, Outbound) ─────────────────────────
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _buildSubTabItem(
                      filterKey: 'all',
                      label: 'All (${allEntries.length})',
                      icon: Icons.phone_in_talk_rounded,
                      activeColor: AppColors.primary,
                    ),
                    _buildSubTabItem(
                      filterKey: 'inbound',
                      label: 'Inbound (${inboundEntries.length})',
                      icon: Icons.call_received_rounded,
                      activeColor: const Color(0xFF10B981),
                    ),
                    _buildSubTabItem(
                      filterKey: 'outbound',
                      label: 'Outbound (${outboundEntries.length})',
                      icon: Icons.call_made_rounded,
                      activeColor: const Color(0xFFF97316),
                    ),
                  ],
                ),
              ),

              if (!_hasStoragePermission && Platform.isAndroid)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFFD97706), size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Enable "All Files Access" for instant call recording sync.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await CallRecordingService().openStoragePermissionSettings();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          minimumSize: const Size(60, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Enable', style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              // ─── RECORDINGS & CALL LOGS LIST ───────────────────────────
              if (state.isAudiosLoading && state.audios == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36.0),
                  child: Center(child: SpinningLogo(size: 36)),
                )
              else if (currentEntries.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderEnabled),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _recordingFilter == 'inbound'
                            ? Icons.call_received_rounded
                            : _recordingFilter == 'outbound'
                                ? Icons.call_made_rounded
                                : Icons.mic_none_rounded,
                        color: AppColors.textHint.withValues(alpha: 0.4),
                        size: 36,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _recordingFilter == 'inbound'
                            ? 'No incoming call recordings or logs found.'
                            : _recordingFilter == 'outbound'
                                ? 'No outgoing call recordings or logs found.'
                                : 'No call recordings or call logs found for this lead.',
                        style: const TextStyle(color: AppColors.textHint, fontSize: 13),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: currentEntries.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = currentEntries[index];
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
                                ] else ...[
                                  // Unanswered / No audio badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3F4F6),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.mic_off_rounded, size: 14, color: AppColors.textHint),
                                        SizedBox(width: 4),
                                        Text(
                                          'No Audio',
                                          style: TextStyle(fontSize: 10, color: AppColors.textHint, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
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
                                        if (item.durationStr.isNotEmpty)
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
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSubTabItem({
    required String filterKey,
    required String label,
    required IconData icon,
    required Color activeColor,
  }) {
    final isSelected = _recordingFilter == filterKey;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _recordingFilter = filterKey),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? activeColor : AppColors.textHint,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved ${doc.fileName} to Downloads folder!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'OPEN',
                textColor: Colors.white,
                onPressed: () async {
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
              ),
            ),
          );
        }
      } else {
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to download ${doc.fileName}'),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      debugPrint('Download error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download ${doc.fileName}'),
            backgroundColor: AppColors.primary,
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved ${audio.displayName} to Downloads folder!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'OPEN',
                textColor: Colors.white,
                onPressed: () async {
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
              ),
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to download ${audio.displayName}'),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      debugPrint('Audio download error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download ${audio.displayName}'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    }
  }

  void _playLeadAudio(BuildContext context, LeadAudio audio) async {
    // 1. Check if audio.fileName is directly a local file path
    if (audio.fileName.isNotEmpty && File(audio.fileName).existsSync()) {
      debugPrint('Playing audio.fileName directly: ${audio.fileName}');
      CallRecordingService().playRecording(audio.fileName, context: context, title: audio.displayName);
      return;
    }

    // 2. Play local phone recording directly if available in _localRecordings
    final cleanServerName = AutoCallRecordingUploader.cleanFileName(audio.displayName.toLowerCase());
    final rawFileName = audio.fileName.toLowerCase();
    for (final local in _localRecordings) {
      final localPath = local['path']?.toString() ?? '';
      if (localPath.isNotEmpty && File(localPath).existsSync()) {
        final localName = AutoCallRecordingUploader.cleanFileName(localPath.split('/').last.split('\\').last.toLowerCase());
        final lowerPath = localPath.toLowerCase();
        if (localName == cleanServerName || lowerPath.contains(cleanServerName) || (rawFileName.isNotEmpty && lowerPath.contains(rawFileName))) {
          debugPrint('Playing local phone recording directly: $localPath');
          CallRecordingService().playRecording(localPath, context: context, title: audio.displayName);
          return;
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
            final res = await sl<ApiClient>().download(
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
        CallRecordingService().playRecording(tempFile.path, context: context, title: audio.displayName);
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

