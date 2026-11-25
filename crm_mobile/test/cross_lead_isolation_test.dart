import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/blocs/leads_event.dart';
import 'package:crm_mobile/blocs/leads_state.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';
import 'package:crm_mobile/models/activity_lead.dart';
import 'package:crm_mobile/models/attachment.dart';
import 'package:crm_mobile/models/lead_audio.dart';
import 'package:crm_mobile/models/lead_call_log.dart';
import 'package:crm_mobile/models/lead_detail.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';
import 'package:crm_mobile/screens/leads/widgets/lead_call_logs_tab.dart';
import 'package:crm_mobile/usecases/create_lead_usecase.dart';
import 'package:crm_mobile/usecases/get_custom_fields_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_attachments_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_priorities_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_audios_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_audit_logs_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_call_logs_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_details_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_sources_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_statuses_usecase.dart';
import 'package:crm_mobile/usecases/get_leads_usecase.dart';
import 'package:crm_mobile/usecases/get_staff_users_usecase.dart';
import 'package:crm_mobile/usecases/quick_invite_lead_usecase.dart';
import 'package:crm_mobile/usecases/search_leads_usecase.dart';
import 'package:crm_mobile/usecases/update_lead_active_status_usecase.dart';
import 'package:crm_mobile/usecases/update_lead_usecase.dart';
import 'package:crm_mobile/usecases/upload_lead_attachment_usecase.dart';
import 'package:crm_mobile/usecases/upload_lead_audio_usecase.dart';

class _FakeLeadsRepository extends Fake implements LeadsRepository {
  final Map<String, LeadDetail> details = {};
  final Map<String, Completer<Either<Failure, List<LeadAudio>>>>
  audioCompleters = {};
  final Map<String, Completer<Either<Failure, LeadCallLogResponse>>>
  callLogCompleters = {};
  final Map<String, List<LeadAudio>> audios = {};
  final Map<String, LeadCallLogResponse> callLogs = {};
  final Map<String, AuditLogResponse> auditLogs = {};

  @override
  Future<Either<Failure, LeadDetail>> getLeadDetails(String id) async {
    return Right(details[id]!);
  }

  @override
  Future<Either<Failure, AuditLogResponse>> getLeadAuditLogs(
    String id, {
    int page = 0,
    int size = 20,
  }) async {
    return Right(
      auditLogs[id] ??
          const AuditLogResponse(content: [], totalPages: 0, totalElements: 0),
    );
  }

  @override
  Future<Either<Failure, List<Attachment>>> getLeadAttachments(
    String id,
  ) async {
    return const Right([]);
  }

  @override
  Future<Either<Failure, List<LeadAudio>>> getLeadAudios(String leadId) async {
    final pending = audioCompleters[leadId];
    if (pending != null) return pending.future;
    return Right(audios[leadId] ?? const []);
  }

  @override
  Future<Either<Failure, LeadCallLogResponse>> getLeadCallLogs(
    String leadId,
  ) async {
    final pending = callLogCompleters[leadId];
    if (pending != null) return pending.future;
    return Right(
      callLogs[leadId] ??
          const LeadCallLogResponse(
            totalCalls: 0,
            totalInboundCalls: 0,
            totalOutboundCalls: 0,
            totalMissedCalls: 0,
            totalDuration: 0,
            callHistory: [],
          ),
    );
  }
}

class _FakeSettingsRepository extends Fake implements SettingsRepository {}

LeadDetail _makeLead({
  required String id,
  required String phone,
  String? alternatePhone,
  List<LeadDetailCustomField> customFields = const [],
}) {
  return LeadDetail(
    id: id,
    leadNumber: 'LD-$id',
    firstName: 'Lead',
    lastName: id,
    companyName: 'Test Co',
    email: '$id@example.com',
    phone: phone,
    alternatePhone: alternatePhone,
    customFields: customFields,
  );
}

LeadAudio _makeAudio({
  required String id,
  required String leadId,
  String fileName = 'call_recording.m4a',
  String? fromNumber,
  String? toNumber,
  String? bound = 'OUT',
}) {
  return LeadAudio(
    id: id,
    leadId: leadId,
    fileName: fileName,
    originalFileName: fileName,
    contentType: 'audio/mp4',
    size: 2048,
    durationSeconds: 30,
    fromNumber: fromNumber,
    toNumber: toNumber,
    bound: bound,
    callDate: '2026-11-12',
    callStatus: 'CONNECTED',
  );
}

LeadCallLog _makeCallLog({
  required String id,
  required String leadId,
  required String fromNumber,
  required String toNumber,
  String bound = 'OUT',
}) {
  return LeadCallLog(
    id: id,
    leadId: leadId,
    bound: bound,
    startTime: '10:00:00',
    endTime: '10:00:30',
    fromNumber: fromNumber,
    toNumber: toNumber,
    duration: '30',
    callDate: '2026-11-12',
    callStatus: 'CONNECTED',
    createdAt: '2026-11-12T10:00:30',
  );
}

LeadsBloc _buildLeadsBloc(_FakeLeadsRepository repo) {
  final settingsRepo = _FakeSettingsRepository();
  return LeadsBloc(
    getLeadsUseCase: GetLeadsUseCase(repo),
    getLeadStatusesUseCase: GetLeadStatusesUseCase(settingsRepo),
    getLeadSourcesUseCase: GetLeadSourcesUseCase(settingsRepo),
    getLeadPrioritiesUseCase: GetLeadPrioritiesUseCase(repo),
    getStaffUsersUseCase: GetStaffUsersUseCase(repo),
    getCustomFieldsUseCase: GetCustomFieldsUseCase(settingsRepo),
    createLeadUseCase: CreateLeadUseCase(repo),
    getLeadDetailsUseCase: GetLeadDetailsUseCase(repo),
    getLeadAuditLogsUseCase: GetLeadAuditLogsUseCase(repo),
    getLeadAttachmentsUseCase: GetLeadAttachmentsUseCase(repo),
    uploadLeadAttachmentUseCase: UploadLeadAttachmentUseCase(repo),
    getLeadAudiosUseCase: GetLeadAudiosUseCase(repo),
    getLeadCallLogsUseCase: GetLeadCallLogsUseCase(repo),
    uploadLeadAudioUseCase: UploadLeadAudioUseCase(repo),
    updateLeadUseCase: UpdateLeadUseCase(repo),
    searchLeadsUseCase: SearchLeadsUseCase(repo),
    updateLeadActiveStatusUseCase: UpdateLeadActiveStatusUseCase(repo),
    quickInviteLeadUseCase: QuickInviteLeadUseCase(repo),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AutoCallRecordingUploader.resetCallDedupStateForTesting();
  });

  group('Phone matching and filename isolation helpers', () {
    test('rejects placeholders, empty strings, and short numbers', () {
      expect(AutoCallRecordingUploader.isUsablePhone(null), isFalse);
      expect(AutoCallRecordingUploader.isUsablePhone(''), isFalse);
      expect(AutoCallRecordingUploader.isUsablePhone('-'), isFalse);
      expect(AutoCallRecordingUploader.isUsablePhone('N/A'), isFalse);
      expect(AutoCallRecordingUploader.isUsablePhone('null'), isFalse);
      expect(AutoCallRecordingUploader.isUsablePhone('123456'), isFalse);
      expect(AutoCallRecordingUploader.isUsablePhone('123'), isFalse);
      expect(AutoCallRecordingUploader.isUsablePhone('+91 98765 43210'), isTrue);
      expect(AutoCallRecordingUploader.isUsablePhone('9876543210'), isTrue);
    });

    test('phonesMatch aligns +91 country codes cleanly and rejects mismatches', () {
      expect(
        AutoCallRecordingUploader.phonesMatch('+919876543210', '9876543210'),
        isTrue,
      );
      expect(
        AutoCallRecordingUploader.phonesMatch('09876543210', '+91 98765-43210'),
        isTrue,
      );
      expect(
        AutoCallRecordingUploader.phonesMatch('9876543210', '9876500000'),
        isFalse,
      );
      expect(
        AutoCallRecordingUploader.phonesMatch('-', '9876543210'),
        isFalse,
      );
    });

    test('hasConflictingPhoneInFileName detects foreign phone but ignores timestamps', () {
      const targetPhone = '+919876543210';

      expect(
        AutoCallRecordingUploader.hasConflictingPhoneInFileName(
          'Call recording 9876500000_261112_100000.m4a',
          targetPhone,
        ),
        isTrue,
      );
      expect(
        AutoCallRecordingUploader.hasConflictingPhoneInFileName(
          'Call recording +919876543210_20261112120500.m4a',
          targetPhone,
        ),
        isFalse,
      );
      expect(
        AutoCallRecordingUploader.hasConflictingPhoneInFileName(
          'Call_recording_20261112120500_1762930000123.m4a',
          targetPhone,
        ),
        isFalse,
      );
      expect(
        AutoCallRecordingUploader.hasConflictingPhoneInFileName(
          'Recording_20261112_100530.mp3',
          targetPhone,
        ),
        isFalse,
      );
    });

    test('uploader entrypoints safely no-op on unusable phone "-"', () async {
      await AutoCallRecordingUploader.autoScanAndUploadLeadRecordings(
        context: null,
        leadId: 'lead-1',
        phoneNumber: '-',
      );
      await AutoCallRecordingUploader.checkAndUploadLatestRecording(
        context: null,
        leadId: 'lead-1',
        phoneNumber: '-',
        callTimestamp: DateTime.now().millisecondsSinceEpoch,
      );
    });
  });

  group('LeadCallLogsTab isolation guards', () {
    final lead = _makeLead(
      id: 'lead-A',
      phone: '+919876543210',
      alternatePhone: '9123456789',
      customFields: const [
        LeadDetailCustomField(
          fieldId: 'cf-1',
          fieldName: 'secondary_mobile',
          label: 'Office Phone',
          fieldType: 'phone',
          value: '9988776655',
        ),
        LeadDetailCustomField(
          fieldId: 'cf-2',
          fieldName: 'notes',
          label: 'Notes',
          fieldType: 'text',
          value: '9999999999',
        ),
      ],
    );

    test('collectUsableLeadPhones collects primary, alternate, and phone custom fields only', () {
      final phones = LeadCallLogsTab.collectUsableLeadPhones(lead);
      expect(
        phones,
        containsAll(['+919876543210', '9123456789', '9988776655']),
      );
      expect(phones, isNot(contains('9999999999')));
    });

    test('itemBelongsToLead allows primary, alternate, and custom phones', () {
      final phones = LeadCallLogsTab.collectUsableLeadPhones(lead);
      for (final num in ['9876543210', '+919123456789', '9988776655']) {
        expect(
          LeadCallLogsTab.itemBelongsToLead(
            itemLeadId: 'lead-A',
            fromNumber: 'Staff',
            toNumber: num,
            bound: 'OUT',
            lead: lead,
            leadPhones: phones,
            fileName: 'calllog.m4a',
          ),
          isTrue,
        );
      }
    });

    test('itemBelongsToLead rejects mismatched leadId, foreign phone, and conflicting filename', () {
      final phones = LeadCallLogsTab.collectUsableLeadPhones(lead);

      // Mismatched itemLeadId even if phone matches
      expect(
        LeadCallLogsTab.itemBelongsToLead(
          itemLeadId: 'lead-B',
          fromNumber: 'Staff',
          toNumber: '9876543210',
          bound: 'OUT',
          lead: lead,
          leadPhones: phones,
        ),
        isFalse,
      );

      // Foreign number even if itemLeadId matches
      expect(
        LeadCallLogsTab.itemBelongsToLead(
          itemLeadId: 'lead-A',
          fromNumber: 'Staff',
          toNumber: '9000011111',
          bound: 'OUT',
          lead: lead,
          leadPhones: phones,
        ),
        isFalse,
      );

      // Placeholder numbers with conflicting 10-digit filename
      expect(
        LeadCallLogsTab.itemBelongsToLead(
          itemLeadId: 'lead-A',
          fromNumber: 'Lead',
          toNumber: 'Staff',
          bound: 'IN',
          lead: lead,
          leadPhones: phones,
          fileName: 'Call recording 9000011111_261112_100000.m4a',
        ),
        isFalse,
      );

      // Placeholder numbers without conflicting filename stay allowed
      expect(
        LeadCallLogsTab.itemBelongsToLead(
          itemLeadId: 'lead-A',
          fromNumber: 'Lead',
          toNumber: 'Staff',
          bound: 'IN',
          lead: lead,
          leadPhones: phones,
          fileName: 'Recording_20261112_100000.m4a',
        ),
        isTrue,
      );
    });
  });

  group('LeadsBloc cross-lead isolation', () {
    test('switching to lead-B clears lead-A data and ignores stale delayed responses', () async {
      final repo = _FakeLeadsRepository();
      final leadA = _makeLead(id: 'lead-A', phone: '+919876543210');
      final leadB = _makeLead(id: 'lead-B', phone: '+919000011111');
      repo.details['lead-A'] = leadA;
      repo.details['lead-B'] = leadB;

      final audioA = _makeAudio(
        id: 'aud-A',
        leadId: 'lead-A',
        toNumber: '+919876543210',
      );
      final callLogA = _makeCallLog(
        id: 'log-A',
        leadId: 'lead-A',
        fromNumber: 'Staff',
        toNumber: '+919876543210',
      );
      repo.audios['lead-A'] = [audioA];
      repo.callLogs['lead-A'] = LeadCallLogResponse(
        totalCalls: 1,
        totalInboundCalls: 0,
        totalOutboundCalls: 1,
        totalMissedCalls: 0,
        totalDuration: 30,
        callHistory: [callLogA],
      );
      repo.auditLogs['lead-A'] = const AuditLogResponse(
        content: [
          AuditLog(
            auditId: 'audit-A',
            entityId: 'lead-A',
            actionType: 'CALL',
            message: 'Lead A log',
            actionBy: 'u1',
            actionByName: 'Agent',
          ),
        ],
        totalPages: 1,
        totalElements: 1,
      );

      final bloc = _buildLeadsBloc(repo);

      // 1. Load lead-A completely
      bloc.add(const FetchLeadDetails('lead-A'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state, isA<LeadDetailsLoaded>());
      var loaded = bloc.state as LeadDetailsLoaded;
      expect(loaded.leadDetail.id, 'lead-A');
      expect(loaded.audios?.map((a) => a.id), ['aud-A']);
      expect(loaded.callLogs?.callHistory.map((c) => c.id), ['log-A']);
      expect(loaded.auditLogs?.content.map((a) => a.auditId), ['audit-A']);

      // 2. Prepare delayed responses for lead-A while switching to lead-B
      final staleAudioCompleter =
          Completer<Either<Failure, List<LeadAudio>>>();
      final staleCallLogCompleter =
          Completer<Either<Failure, LeadCallLogResponse>>();
      repo.audioCompleters['lead-A'] = staleAudioCompleter;
      repo.callLogCompleters['lead-A'] = staleCallLogCompleter;

      final audioB = _makeAudio(
        id: 'aud-B',
        leadId: 'lead-B',
        toNumber: '+919000011111',
      );
      final callLogB = _makeCallLog(
        id: 'log-B',
        leadId: 'lead-B',
        fromNumber: 'Staff',
        toNumber: '+919000011111',
      );
      repo.audios['lead-B'] = [audioB];
      repo.callLogs['lead-B'] = LeadCallLogResponse(
        totalCalls: 1,
        totalInboundCalls: 0,
        totalOutboundCalls: 1,
        totalMissedCalls: 0,
        totalDuration: 30,
        callHistory: [callLogB],
      );

      // Kick off stale lead-A fetches, then immediately switch to lead-B
      bloc.add(const FetchLeadAudios('lead-A'));
      bloc.add(const FetchLeadCallLogs('lead-A'));
      bloc.add(const FetchLeadDetails('lead-B'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      loaded = bloc.state as LeadDetailsLoaded;
      expect(loaded.leadDetail.id, 'lead-B');
      expect(loaded.audios?.map((a) => a.id), ['aud-B']);
      expect(loaded.callLogs?.callHistory.map((c) => c.id), ['log-B']);
      expect(loaded.auditLogs?.content, isEmpty);

      // 3. Complete delayed lead-A responses and verify lead-B is untouched
      staleAudioCompleter.complete(Right([audioA]));
      staleCallLogCompleter.complete(
        Right(
          LeadCallLogResponse(
            totalCalls: 1,
            totalInboundCalls: 0,
            totalOutboundCalls: 1,
            totalMissedCalls: 0,
            totalDuration: 30,
            callHistory: [callLogA],
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      loaded = bloc.state as LeadDetailsLoaded;
      expect(loaded.leadDetail.id, 'lead-B');
      expect(loaded.audios?.map((a) => a.id), ['aud-B']);
      expect(loaded.callLogs?.callHistory.map((c) => c.id), ['log-B']);

      await bloc.close();
    });
  });
}
