import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/widgets/in_app_audio_player_modal.dart';
import 'package:crm_mobile/core/utils/navigation_service.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';
import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/blocs/leads_state.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';

class CallRecordingService {
  static const MethodChannel _channel = MethodChannel('com.example.crm_mobile/call_recording');
  static bool _isOverlayListenerInitialized = false;
  static String? _lastOverlayLookupPhone;
  static DateTime? _lastOverlayLookupTime;
  static Timer? _postCallRetryTimer;

  static void initializeOverlayListener() {
    if (_isOverlayListenerInitialized) return;
    _isOverlayListenerInitialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onCallDetected') {
        final Map<dynamic, dynamic>? args = call.arguments as Map<dynamic, dynamic>?;
        final String? phone = args?['phoneNumber'] as String?;
        if (phone != null && phone.trim().isNotEmpty) {
          _checkLeadAndNotifyOverlay(phone.trim());
        }
      } else if (call.method == 'onQuickAddLeadFromOverlay') {
        final Map<dynamic, dynamic>? args = call.arguments as Map<dynamic, dynamic>?;
        final String? phone = args?['phoneNumber'] as String?;
        if (phone != null && phone.trim().isNotEmpty) {
          _performQuickAddLeadFromOverlay(phone.trim());
        }
      } else if (call.method == 'onFloatingCardAction') {
        final Map<dynamic, dynamic>? args = call.arguments as Map<dynamic, dynamic>?;
        final String? phone = args?['phoneNumber'] as String?;
        final String? leadId = args?['leadId'] as String?;
        final String? action = args?['action'] as String?;

        if (action == 'ACTION_VIEW_DETAILS' && leadId != null && leadId.trim().isNotEmpty) {
          NavigationService.navigateToLeadDetails(leadId.trim());
        } else if (phone != null && phone.trim().isNotEmpty) {
          NavigationService.navigateToQuickInvite(phone.trim());
        }
      } else if (call.method == 'onCallEnded') {
        final Map<dynamic, dynamic>? args = call.arguments as Map<dynamic, dynamic>?;
        final String? phone = args?['phoneNumber'] as String?;
        final bool isMissed = args?['isMissed'] as bool? ?? false;
        final bool wasOffhook = args?['wasOffhook'] as bool? ?? false;
        final int offhookDurationMs = (args?['offhookDurationMs'] as num?)?.toInt() ?? 0;
        final int endedAtMs = (args?['endedAtMs'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch;
        AutoCallRecordingUploader.recordNativeCallEnded(
          phone: phone,
          endedAtMs: endedAtMs,
          wasOffhook: wasOffhook,
        );
        debugPrint(
          'Call ended detected via channel: phone=$phone, isMissed=$isMissed, wasOffhook=$wasOffhook, offhookDurationMs=$offhookDurationMs',
        );
        AutoCallRecordingUploader.syncRecentCallsIfAvailable(force: true);
        _postCallRetryTimer?.cancel();
        _postCallRetryTimer = Timer(const Duration(seconds: 5), () {
          AutoCallRecordingUploader.syncRecentCallsIfAvailable(force: true);
        });
      }
    });

    _channel.invokeMethod<Map<dynamic, dynamic>>('getInitialOverlayAction').then((data) {
      if (data != null) {
        final phone = data['phoneNumber'] as String?;
        final leadId = data['leadId'] as String?;
        final action = data['action'] as String?;
        if (action == 'ACTION_VIEW_DETAILS' && leadId != null && leadId.trim().isNotEmpty) {
          NavigationService.navigateToLeadDetails(leadId.trim());
        } else if (phone != null && phone.trim().isNotEmpty) {
          NavigationService.navigateToQuickInvite(phone.trim());
        }
      }
    }).catchError((_) {});
  }

  static Future<void> _checkLeadAndNotifyOverlay(String phone) async {
    try {
      final cleanDigits = phone.replaceAll(RegExp(r'[^\d]'), '');
      if (cleanDigits.length < 7) return;

      final last10 = cleanDigits.length >= 10 ? cleanDigits.substring(cleanDigits.length - 10) : cleanDigits;
      final now = DateTime.now();
      if (_lastOverlayLookupPhone == last10 &&
          _lastOverlayLookupTime != null &&
          now.difference(_lastOverlayLookupTime!).inSeconds < 5) {
        return;
      }
      _lastOverlayLookupPhone = last10;
      _lastOverlayLookupTime = now;

      final repo = sl<LeadsRepository>();

      bool found = false;
      String leadName = '';
      String leadId = '';
      String assignedToName = '';
      String assignedToId = '';
      bool hadApiFailure = false;

      final queries = <String>[
        if (last10.isNotEmpty) last10,
        if (phone.trim().isNotEmpty && phone.trim() != last10) phone.trim(),
      ];

      // 1. Check via searchLeadByNumber (/leads/search/number?phone=...) with deduplicated queries
      for (final q in queries) {
        if (found) break;
        try {
          final result = await repo.searchLeadByNumber(q);
          result.fold((_) {
            hadApiFailure = true;
          }, (data) {
            if (data.alreadyMapped || (data.leadId != null && data.leadId!.isNotEmpty)) {
              found = true;
              final name = data.name?.trim() ?? '';
              leadName = name.isNotEmpty ? name : (data.leadNumber ?? 'Existing Lead');
              leadId = data.leadId ?? '';
              assignedToName = data.assignedToName?.trim() ?? data.assignedToInfo?.trim() ?? '';
              assignedToId = data.assignedToId?.trim() ?? '';
            }
          });
        } catch (_) {
          hadApiFailure = true;
        }
      }

      // 2. Fallback: only if searchLeadByNumber failed, query getLeads once with last10
      if (!found && hadApiFailure && last10.isNotEmpty) {
        try {
          final allLeadsRes = await repo.getLeads(0, 20, searchQuery: last10);
          allLeadsRes.fold((_) {}, (leads) {
            for (final l in leads) {
              final leadDigits = l.phone.replaceAll(RegExp(r'[^\d]'), '');
              if (leadDigits.endsWith(last10) || (leadDigits.isNotEmpty && last10.endsWith(leadDigits))) {
                found = true;
                final fullName = '${l.firstName} ${l.lastName}'.trim();
                leadName = fullName.isNotEmpty ? fullName : (l.companyName.isNotEmpty ? l.companyName : 'Existing Lead');
                leadId = l.id;
                assignedToName = l.ownerUserName?.trim() ?? '';
                assignedToId = l.ownerUserId?.trim() ?? '';
                break;
              }
            }
          });
        } catch (_) {}
      }

      final prefs = sl<SharedPreferences>();
      final currentUserId = prefs.getString('userId')?.trim() ?? '';
      final currentUserName = (prefs.getString('userName')?.trim() ?? '').toLowerCase();

      bool isAssigned = false;
      bool isAssignedToMe = false;
      bool isAssignedToOther = false;

      if (found) {
        final cleanAssigned = assignedToName.toLowerCase();
        final isUnassigned = assignedToName.isEmpty ||
            cleanAssigned == 'unassigned' ||
            cleanAssigned == 'null' ||
            cleanAssigned == 'n/a' ||
            cleanAssigned == 'none';

        if (!isUnassigned || assignedToId.isNotEmpty) {
          isAssigned = true;
          if ((currentUserId.isNotEmpty && assignedToId.isNotEmpty && currentUserId == assignedToId) ||
              (currentUserName.isNotEmpty && cleanAssigned.isNotEmpty && (cleanAssigned == currentUserName || cleanAssigned.contains(currentUserName) || currentUserName.contains(cleanAssigned)))) {
            isAssignedToMe = true;
          } else {
            isAssignedToOther = true;
          }
        } else {
          // Lead exists in CRM but unassigned
          isAssignedToMe = true;
        }
      }

      debugPrint('[OverlayLeadCheck] phone=$phone, found=$found, isAssigned=$isAssigned, isOther=$isAssignedToOther, assignedTo=$assignedToName, leadName=$leadName, leadId=$leadId');

      await _channel.invokeMethod('updateFloatingCardLeadInfo', {
        'phoneNumber': phone,
        'isExisting': found,
        'leadName': leadName,
        'leadId': leadId,
        'badgeMessage': isAssignedToOther
            ? 'ASSIGNED TO ${assignedToName.toUpperCase()}'
            : (found ? 'LEAD ALREADY EXISTS' : 'NEW NUMBER'),
        'assignedToName': assignedToName,
        'isAssignedToOther': isAssignedToOther,
        'isAssignedToMe': isAssignedToMe,
      });
    } catch (e) {
      debugPrint('Error checking lead in overlay: $e');
    }
  }

  static Future<void> _performQuickAddLeadFromOverlay(String phone) async {
    try {
      final cleanDigits = phone.replaceAll(RegExp(r'[^\d]'), '');
      if (cleanDigits.length < 5) {
        debugPrint('[QuickAdd] Phone number invalid: $phone');
        await _channel.invokeMethod('updateFloatingCardLeadInfo', {
          'phoneNumber': phone,
          'isExisting': false,
          'leadName': 'Unknown Caller',
          'leadId': '',
          'badgeMessage': 'INVALID NUMBER',
        });
        return;
      }

      final prefs = sl<SharedPreferences>();
      final currentUserId = prefs.getString('userId');

      // Use clean 10-digit number if length >= 10, else cleanDigits
      final phoneToSave = cleanDigits.length >= 10
          ? cleanDigits.substring(cleanDigits.length - 10)
          : cleanDigits;

      final Map<String, dynamic> payload = {
        'phone': phoneToSave,
        'mobile': phoneToSave,
        'mobileNumber': phoneToSave,
        'firstName': 'quick call user',
        'name': 'quick call user',
      };

      if (currentUserId != null && currentUserId.isNotEmpty) {
        payload['assignedTo'] = currentUserId;
        payload['ownerUserId'] = currentUserId;
      }

      // Check if LeadsBloc has default status already cached
      if (sl.isRegistered<LeadsBloc>()) {
        final state = sl<LeadsBloc>().state;
        if (state is LeadsLoaded && state.statuses.isNotEmpty) {
          final def = state.statuses.firstWhere(
            (s) => s.isDefault == true,
            orElse: () => state.statuses.first,
          );
          payload['leadStatusId'] = def.id;
          payload['statusId'] = def.id;
        }
      }

      final repo = sl<LeadsRepository>();
      final result = await repo.quickInviteLead(payload).timeout(
        const Duration(seconds: 10),
        onTimeout: () => Left(ServerFailure('Quick add timed out')),
      );

      await result.fold(
        (failure) async {
          debugPrint('[QuickAdd] Failed: ${failure.message}');
          await _channel.invokeMethod('updateFloatingCardLeadInfo', {
            'phoneNumber': phone,
            'isExisting': false,
            'leadName': 'Unknown Lead',
            'leadId': '',
            'badgeMessage': 'ADD FAILED - RETRY',
          });
        },
        (_) async {
          debugPrint('[QuickAdd] Success for $phoneToSave');
          AutoCallRecordingUploader.invalidatePhoneLookupCache(phoneToSave);

          String newLeadId = '';
          try {
            final searchRes = await repo.searchLeadByNumber(phoneToSave).timeout(
              const Duration(seconds: 4),
              onTimeout: () => Left(ServerFailure('Search timed out')),
            );
            searchRes.fold((_) {}, (r) {
              if (r.alreadyMapped && r.leadId != null && r.leadId!.isNotEmpty) {
                newLeadId = r.leadId!;
              }
            });
          } catch (_) {}

          // Update overlay floating card to existing lead state
          await _channel.invokeMethod('updateFloatingCardLeadInfo', {
            'phoneNumber': phone,
            'isExisting': true,
            'leadName': 'quick call user',
            'leadId': newLeadId,
            'badgeMessage': 'LEAD ALREADY EXISTS',
          });

          // Start tracking call recording for this new lead
          if (newLeadId.isNotEmpty) {
            await AutoCallRecordingUploader.trackCurrentCallForLead(
              leadId: newLeadId,
              phoneNumber: phoneToSave,
              leadName: 'quick call user',
            );
          }
        },
      );
    } catch (e) {
      debugPrint('[QuickAdd] Error in _performQuickAddLeadFromOverlay: $e');
      try {
        await _channel.invokeMethod('updateFloatingCardLeadInfo', {
          'phoneNumber': phone,
          'isExisting': false,
          'leadName': 'Unknown Caller',
          'leadId': '',
          'badgeMessage': 'ADD FAILED',
        });
      } catch (_) {}
    }
  }

  Future<bool> hasOverlayPermission() async {
    try {
      final bool? result = await _channel.invokeMethod('hasOverlayPermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (_) {}
  }

  Future<bool> hasCallScreeningRole() async {
    try {
      final bool? result = await _channel.invokeMethod('hasCallScreeningRole');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> requestCallScreeningRole() async {
    try {
      await _channel.invokeMethod('requestCallScreeningRole');
    } catch (_) {}
  }

  Future<bool> requestPermissionsSequentially() async {
    try {
      final bool result = await _channel.invokeMethod('requestPermissionsSequentially');
      return result;
    } on PlatformException catch (e) {
      print("Failed to request permissions sequentially: '${e.message}'.");
      return false;
    }
  }

  Future<bool> hasStoragePermission() async {
    try {
      final bool result = await _channel.invokeMethod('hasStoragePermission');
      return result;
    } on PlatformException catch (e) {
      print("Failed to check storage permission: '${e.message}'.");
      return false;
    }
  }

  Future<void> openStoragePermissionSettings() async {
    try {
      await _channel.invokeMethod('openStoragePermissionSettings');
    } on PlatformException catch (e) {
      print("Failed to open storage permission settings: '${e.message}'.");
    }
  }

  Future<bool> requestAllFilesAccess() async {
    try {
      final bool result = await _channel.invokeMethod('requestAllFilesAccess');
      return result;
    } on PlatformException catch (e) {
      print("Failed to request all files access: '${e.message}'.");
      return false;
    }
  }

  Future<bool> isCallOngoing() async {
    try {
      final bool? result = await _channel.invokeMethod('isCallOngoing');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }


  Future<String?> findLatestSystemRecording({
    required int callTimestamp,
    String phoneNumber = "",
  }) async {
    try {
      final String? path = await _channel.invokeMethod('findLatestSystemRecording', {
        'callTimestamp': callTimestamp,
        'phoneNumber': phoneNumber,
      });
      return path;
    } on PlatformException catch (e) {
      print("Failed to find latest system recording: '${e.message}'.");
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getAllSystemRecordings(String phoneNumber, {int callTimestamp = 0}) async {
    try {
      final List<dynamic>? recordings = await _channel.invokeMethod('getAllSystemRecordings', {
        'phoneNumber': phoneNumber,
        'callTimestamp': callTimestamp,
      });
      if (recordings == null) return [];
      
      return recordings.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        return map;
      }).toList();
    } on PlatformException catch (e) {
      print("Failed to get all system recordings: '${e.message}'.");
      return [];
    }
  }

  Future<Map<String, dynamic>?> getLatestCallDetails({
    required String phoneNumber,
    int callTimestamp = 0,
  }) async {
    try {
      final Map<dynamic, dynamic>? res = await _channel.invokeMethod('getLatestCallDetails', {
        'phoneNumber': phoneNumber,
        'callTimestamp': callTimestamp,
      });
      if (res != null) {
        return Map<String, dynamic>.from(res);
      }
      return null;
    } on PlatformException catch (e) {
      print("Failed to get latest call details: '${e.message}'.");
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getSystemCallLogs(String phoneNumber) async {
    try {
      final List<dynamic>? res = await _channel.invokeMethod('getSystemCallLogs', {
        'phoneNumber': phoneNumber,
      });
      if (res != null) {
        return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } on PlatformException catch (e) {
      print("Failed to get system call logs: '${e.message}'.");
      return [];
    }
  }

  /// Gets the device's own phone number from SIM / call log.
  /// Returns the phone number string, or empty string if unavailable.
  Future<String> getDevicePhoneNumber() async {
    try {
      final String? result = await _channel.invokeMethod('getDevicePhoneNumber');
      return result ?? '';
    } on PlatformException catch (e) {
      print("Failed to get device phone number: '${e.message}'.");
      return '';
    }
  }

  Future<void> playRecording(String path, {BuildContext? context, String? title, Function(int)? onDurationFound}) async {
    if (context != null && context.mounted) {
      InAppAudioPlayerModal.show(context, filePath: path, title: title ?? 'Recording', onDurationFound: onDurationFound);
      return;
    }

    try {
      await _channel.invokeMethod('playRecording', {
        'path': path,
      });
    } on PlatformException catch (e) {
      print("Failed to play recording: '${e.message}'.");
    }
  }

  Future<String?> saveToDownloads({
    required String filePath,
    required String fileName,
    String? mimeType,
  }) async {
    try {
      final String? savedPath = await _channel.invokeMethod('saveToDownloads', {
        'filePath': filePath,
        'fileName': fileName,
        'mimeType': mimeType,
      });
      return savedPath;
    } on PlatformException catch (e) {
      print("Failed to save to downloads: '${e.message}'.");
      return null;
    }
  }

  Future<String> detectCallType({
    required String filePath,
    required String fileName,
    required String phoneNumber,
    required int timestamp,
    int callTimestamp = 0,
  }) async {
    try {
      final String? type = await _channel.invokeMethod('detectCallType', {
        'filePath': filePath,
        'fileName': fileName,
        'phoneNumber': phoneNumber,
        'timestamp': timestamp,
        'callTimestamp': callTimestamp,
      });
      return type ?? 'inbound';
    } on PlatformException catch (e) {
      print("Failed to detect call type: '${e.message}'.");
      return 'inbound';
    }
  }

  Future<int> getAudioDuration(String filePath) async {
    try {
      final int ms = await _channel.invokeMethod('getAudioDuration', {'filePath': filePath});
      return ms;
    } on PlatformException catch (e) {
      print("Failed to get audio duration: '${e.message}'.");
      return 0;
    }
  }

  Future<void> playNativeAudio(String path) async {
    try {
      await _channel.invokeMethod('playNativeAudio', {
        'path': path,
      });
    } on PlatformException catch (e) {
      print("Failed to play native audio: '${e.message}'.");
    }
  }
}
