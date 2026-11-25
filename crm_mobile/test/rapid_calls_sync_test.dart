import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';
import 'package:crm_mobile/core/services/call_history_storage.dart';
import 'package:crm_mobile/models/call_history.dart';
import 'package:crm_mobile/models/lead_audio.dart';
import 'package:crm_mobile/models/lead_call_log.dart';
import 'package:crm_mobile/models/owner_call_report.dart';

void main() {
  const leadId = 'lead-123';
  const phone = '+919876543210';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AutoCallRecordingUploader.resetCallDedupStateForTesting();
  });

  LeadAudio makeServerAudio({
    required String id,
    required DateTime start,
    required String bound,
    String callStatus = 'MISSED',
    int durationSeconds = 0,
    int size = 0,
  }) {
    final end = durationSeconds > 0
        ? start.add(Duration(seconds: durationSeconds))
        : start;
    return LeadAudio(
      id: id,
      leadId: leadId,
      fileName: 'calllog_$id.mp3',
      originalFileName: 'calllog_$id.mp3',
      contentType: 'audio/mpeg',
      size: size,
      createdAt: end,
      durationSeconds: durationSeconds,
      startTimeStr: DateFormat('HH:mm:ss').format(start),
      endTimeStr: DateFormat('HH:mm:ss').format(end),
      callDate: DateFormat('yyyy-MM-dd').format(start),
      bound: bound,
      callStatus: callStatus,
    );
  }

  LeadCallLog makeServerCallLog({
    required String id,
    required DateTime start,
    required String bound,
    required String callStatus,
    int durationSeconds = 0,
  }) {
    final end = durationSeconds > 0
        ? start.add(Duration(seconds: durationSeconds))
        : start;
    return LeadCallLog(
      id: id,
      leadId: leadId,
      bound: bound,
      startTime: DateFormat('HH:mm:ss').format(start),
      endTime: DateFormat('HH:mm:ss').format(end),
      fromNumber: bound.startsWith('IN') ? phone : '9000000000',
      toNumber: bound.startsWith('IN') ? '9000000000' : phone,
      duration: durationSeconds.toString(),
      callDate: DateFormat('yyyy-MM-dd').format(start),
      callStatus: callStatus,
      createdAt: end.toIso8601String(),
    );
  }

  group('Rapid calls within 1 minute deduplication', () {
    test('3 MISSED calls in 1 minute stay distinct in serverAudio, bucket, and callLog checks', () async {
      final base = DateTime(2026, 11, 11, 10, 0, 0);
      final t1 = base.millisecondsSinceEpoch;
      final t2 = base.add(const Duration(seconds: 12)).millisecondsSinceEpoch;
      final t3 = base.add(const Duration(seconds: 26)).millisecondsSinceEpoch;

      // Upload #1 (newest = t3) and add to serverAudios + serverCallLogs + local buckets
      await AutoCallRecordingUploader.markCallBucketUploadedForTesting(
        phone: phone,
        timestampMs: t3,
        bound: 'IN',
        callStatus: 'MISSED',
      );
      final serverAudios = [
        makeServerAudio(
          id: 'a3',
          start: DateTime.fromMillisecondsSinceEpoch(t3),
          bound: 'INBOUND',
          callStatus: 'MISSED',
        ),
      ];
      final serverLogs = [
        makeServerCallLog(
          id: 'l3',
          start: DateTime.fromMillisecondsSinceEpoch(t3),
          bound: 'INBOUND',
          callStatus: 'MISSED',
        ),
      ];

      // Calls #2 (t2 = -14s) and #1 (t1 = -26s) must NOT be suppressed
      expect(
        AutoCallRecordingUploader.isCallRecentlyUploadedForTesting(
          phone,
          bound: 'IN',
          leadId: leadId,
          timestampMs: t2,
          callStatus: 'MISSED',
        ),
        isFalse,
      );
      expect(
        await AutoCallRecordingUploader.isCallAlreadyUploaded(
          phone: phone,
          timestampMs: t2,
          bound: 'IN',
          callStatus: 'MISSED',
          durationSeconds: 0,
          existingServerAudios: serverAudios,
          existingServerCallLogs: serverLogs,
        ),
        isFalse,
      );
      expect(
        await AutoCallRecordingUploader.isAlreadyUploaded(
          'calllog_IN_MISSED_${(t2 ~/ 1000) * 1000}_$phone',
          0,
          existingServerAudios: serverAudios,
        ),
        isFalse,
      );

      // Upload #2 (t2)
      await AutoCallRecordingUploader.markCallBucketUploadedForTesting(
        phone: phone,
        timestampMs: t2,
        bound: 'IN',
        callStatus: 'MISSED',
      );
      serverAudios.add(
        makeServerAudio(
          id: 'a2',
          start: DateTime.fromMillisecondsSinceEpoch(t2),
          bound: 'INBOUND',
          callStatus: 'MISSED',
        ),
      );
      serverLogs.add(
        makeServerCallLog(
          id: 'l2',
          start: DateTime.fromMillisecondsSinceEpoch(t2),
          bound: 'INBOUND',
          callStatus: 'MISSED',
        ),
      );

      // Call #1 (t1) must still NOT be suppressed
      expect(
        await AutoCallRecordingUploader.isCallAlreadyUploaded(
          phone: phone,
          timestampMs: t1,
          bound: 'IN',
          callStatus: 'MISSED',
          durationSeconds: 0,
          existingServerAudios: serverAudios,
          existingServerCallLogs: serverLogs,
        ),
        isFalse,
      );
      expect(
        await AutoCallRecordingUploader.isAlreadyUploaded(
          'calllog_IN_MISSED_${(t1 ~/ 1000) * 1000}_$phone',
          0,
          existingServerAudios: serverAudios,
        ),
        isFalse,
      );

      // Same call within 1-2s jitter IS still detected as duplicate
      expect(
        await AutoCallRecordingUploader.isCallAlreadyUploaded(
          phone: phone,
          timestampMs: t3 + 1000,
          bound: 'IN',
          callStatus: 'MISSED',
          durationSeconds: 0,
          existingServerAudios: serverAudios,
          existingServerCallLogs: serverLogs,
        ),
        isTrue,
      );
    });

    test('3 NOT_CONNECTED outgoing calls within 1 minute stay distinct', () async {
      final base = DateTime(2026, 11, 11, 11, 0, 0);
      final t1 = base.millisecondsSinceEpoch;
      final t2 = base.add(const Duration(seconds: 8)).millisecondsSinceEpoch;
      final t3 = base.add(const Duration(seconds: 17)).millisecondsSinceEpoch;

      await AutoCallRecordingUploader.markCallBucketUploadedForTesting(
        phone: phone,
        timestampMs: t1,
        bound: 'OUT',
        callStatus: 'NOT_CONNECTED',
      );
      final serverAudios = [
        makeServerAudio(
          id: 'a1',
          start: base,
          bound: 'OUTBOUND',
          callStatus: 'NOT_CONNECTED',
        ),
      ];
      final serverLogs = [
        makeServerCallLog(
          id: 'l1',
          start: base,
          bound: 'OUTBOUND',
          callStatus: 'NOT_CONNECTED',
        ),
      ];

      for (final ts in [t2, t3]) {
        expect(
          AutoCallRecordingUploader.isCallRecentlyUploadedForTesting(
            phone,
            bound: 'OUT',
            leadId: leadId,
            timestampMs: ts,
            callStatus: 'NOT_CONNECTED',
          ),
          isFalse,
        );
        expect(
          await AutoCallRecordingUploader.isCallAlreadyUploaded(
            phone: phone,
            timestampMs: ts,
            bound: 'OUT',
            callStatus: 'NOT_CONNECTED',
            durationSeconds: 0,
            existingServerAudios: serverAudios,
            existingServerCallLogs: serverLogs,
          ),
          isFalse,
        );
        expect(
          await AutoCallRecordingUploader.isAlreadyUploaded(
            'calllog_OUT_NOT_CONNECTED_${(ts ~/ 1000) * 1000}_$phone',
            0,
            existingServerAudios: serverAudios,
          ),
          isFalse,
        );
      }
    });

    test('3 short CONNECTED calls and adjacent MISSED/NOT_CONNECTED calls in 1 minute stay distinct', () async {
      final base = DateTime(2026, 11, 11, 12, 0, 0);
      final c1 = base.millisecondsSinceEpoch; // 12:00:00..12:00:05 (5s)
      final c2 = base.add(const Duration(seconds: 10)).millisecondsSinceEpoch; // 12:00:10..12:00:16 (6s)
      final c3Missed = base.add(const Duration(seconds: 20)).millisecondsSinceEpoch; // 12:00:20 (0s MISSED)
      final c4Unconn = base.add(const Duration(seconds: 25)).millisecondsSinceEpoch; // 12:00:25 (0s NOT_CONNECTED)

      await AutoCallRecordingUploader.markCallBucketUploadedForTesting(
        phone: phone,
        timestampMs: c1,
        bound: 'OUT',
        callStatus: 'CONNECTED',
      );
      final serverAudios = [
        makeServerAudio(
          id: 'ac1',
          start: base,
          bound: 'OUTBOUND',
          callStatus: 'CONNECTED',
          durationSeconds: 5,
          size: 4096,
        ),
      ];
      final serverLogs = [
        makeServerCallLog(
          id: 'lc1',
          start: base,
          bound: 'OUTBOUND',
          callStatus: 'CONNECTED',
          durationSeconds: 5,
        ),
      ];

      expect(
        await AutoCallRecordingUploader.isCallAlreadyUploaded(
          phone: phone,
          timestampMs: c2,
          bound: 'OUT',
          callStatus: 'CONNECTED',
          durationSeconds: 6,
          existingServerAudios: serverAudios,
          existingServerCallLogs: serverLogs,
        ),
        isFalse,
      );

      // Connected call 1 (ending at 12:00:05, start 12:00:00) must not suppress c3Missed (12:00:20) or c4Unconn (12:00:25)
      expect(
        await AutoCallRecordingUploader.isCallAlreadyUploaded(
          phone: phone,
          timestampMs: c3Missed,
          bound: 'IN',
          callStatus: 'MISSED',
          durationSeconds: 0,
          existingServerAudios: serverAudios,
          existingServerCallLogs: serverLogs,
        ),
        isFalse,
      );
      expect(
        await AutoCallRecordingUploader.isCallAlreadyUploaded(
          phone: phone,
          timestampMs: c4Unconn,
          bound: 'OUT',
          callStatus: 'NOT_CONNECTED',
          durationSeconds: 0,
          existingServerAudios: serverAudios,
          existingServerCallLogs: serverLogs,
        ),
        isFalse,
      );
    });

    test('CallHistoryStorage.markCallAsSynced only marks matching timestamp within 3.5s', () async {
      final base = DateTime(2026, 11, 11, 13, 0, 0).millisecondsSinceEpoch;
      final call1 = CallHistory(
        id: 'ch-1',
        phoneNumber: phone,
        callType: 'OUTGOING',
        timestamp: base,
        startTime: base,
        endTime: base,
        durationSeconds: 0,
        callStatus: 'NOT_CONNECTED',
      );
      final call2 = CallHistory(
        id: 'ch-2',
        phoneNumber: phone,
        callType: 'OUTGOING',
        timestamp: base + 10000,
        startTime: base + 10000,
        endTime: base + 10000,
        durationSeconds: 0,
        callStatus: 'NOT_CONNECTED',
      );
      await CallHistoryStorage.saveCallHistory([call2, call1]);
      await CallHistoryStorage.markCallAsSynced(phone, base);

      final loaded = await CallHistoryStorage.loadCallHistory();
      final byId = {for (final c in loaded) c.id: c};
      expect(byId['ch-1']?.isSynced, isTrue);
      expect(byId['ch-2']?.isSynced, isFalse);
    });

    test('OwnerCallReport preserves multiple rapid calls within 15 seconds', () {
      final report = OwnerCallReport.fromJson({
        'ownerId': 'u-1',
        'ownerName': 'Agent',
        'calledLeads': [
          {
            'leadId': leadId,
            'leadName': 'Lead A',
            'duration': '0',
            'callType': 'INCOMING',
            'callStatus': 'MISSED',
            'callDate': '2026-11-11',
            'startTime': '14:00:02',
            'createdAt': '2026-11-11T14:00:02',
          },
          {
            'leadId': leadId,
            'leadName': 'Lead A',
            'duration': '0',
            'callType': 'INCOMING',
            'callStatus': 'MISSED',
            'callDate': '2026-11-11',
            'startTime': '14:00:08',
            'createdAt': '2026-11-11T14:00:08',
          },
          {
            'leadId': leadId,
            'leadName': 'Lead A',
            'duration': '0',
            'callType': 'INCOMING',
            'callStatus': 'MISSED',
            'callDate': '2026-11-11',
            'startTime': '14:00:14',
            'createdAt': '2026-11-11T14:00:14',
          },
        ],
      });

      expect(report.calledLeads.length, 3);
    });
  });

  group('Redmi duplicate connected call log prevention', () {
    test(
      'Phase 2 waits full 8s after native hangup when ring time inflates dial-end gap, then releases after 8s',
      () {
        final base = DateTime(2026, 11, 12, 12, 0, 0);
        // Dial started 12:00:00, rang 10s, talked 15s -> hangup at 12:00:25.
        // Android CallLog sets callEnd = dialStart + 15s = 12:00:15.
        final startMs = base.millisecondsSinceEpoch;
        final callEndMs = base.add(const Duration(seconds: 15)).millisecondsSinceEpoch;
        final hangupMs = base.add(const Duration(seconds: 25)).millisecondsSinceEpoch;

        AutoCallRecordingUploader.recordNativeCallEnded(
          phone: phone,
          endedAtMs: hangupMs,
          wasOffhook: true,
        );

        // 2s after hangup (12s after CallLog callEndMs), Phase 2 MUST still wait 6s for MIUI flush
        final scanAt2s = base.add(const Duration(seconds: 27)).millisecondsSinceEpoch;
        expect(
          AutoCallRecordingUploader.resolvePhase2GraceWaitForTesting(
            phoneNumber: phone,
            startTimeMs: startMs,
            callEndMs: callEndMs,
            nowMs: scanAt2s,
          ),
          equals(6000),
        );

        // 8.5s after hangup, grace is satisfied so devices without call recording still upload
        final scanAt85s = base.add(const Duration(milliseconds: 33500)).millisecondsSinceEpoch;
        expect(
          AutoCallRecordingUploader.resolvePhase2GraceWaitForTesting(
            phoneNumber: phone,
            startTimeMs: startMs,
            callEndMs: callEndMs,
            nowMs: scanAt85s,
          ),
          equals(0),
        );
      },
    );

    test(
      'Earlier historical call is not delayed by a newer hangup >65s later',
      () {
        final base = DateTime(2026, 11, 12, 12, 0, 0);
        final oldStart = base.millisecondsSinceEpoch;
        final oldEnd = base.add(const Duration(seconds: 10)).millisecondsSinceEpoch;
        final newHangup = base.add(const Duration(seconds: 90)).millisecondsSinceEpoch;
        final scanNow = base.add(const Duration(seconds: 92)).millisecondsSinceEpoch;

        AutoCallRecordingUploader.recordNativeCallEnded(
          phone: phone,
          endedAtMs: newHangup,
          wasOffhook: true,
        );

        expect(
          AutoCallRecordingUploader.resolvePhase2GraceWaitForTesting(
            phoneNumber: phone,
            startTimeMs: oldStart,
            callEndMs: oldEnd,
            nowMs: scanNow,
          ),
          equals(0),
        );
      },
    );

    test(
      '0-byte CONNECTED stub prevents duplicate CONNECTED audio upload while 0s MISSED does not',
      () async {
        final dialStart = DateTime(2026, 11, 12, 12, 10, 0);
        final answerStart = dialStart.add(const Duration(seconds: 8));

        final connectedStubAudios = [
          makeServerAudio(
            id: 'stub-0',
            start: dialStart,
            bound: 'OUTBOUND',
            callStatus: 'CONNECTED',
            durationSeconds: 0,
            size: 0,
          ),
        ];
        final connectedServerLogs = [
          makeServerCallLog(
            id: 'log-conn-1',
            start: dialStart,
            bound: 'OUTBOUND',
            callStatus: 'CONNECTED',
            durationSeconds: 15,
          ),
        ];

        // Exact start match even when size=0 & duration=0 on stub audio
        expect(
          await AutoCallRecordingUploader.isCallAlreadyUploaded(
            phone: phone,
            timestampMs: dialStart.millisecondsSinceEpoch,
            bound: 'OUT',
            callStatus: 'CONNECTED',
            durationSeconds: 15,
            existingServerAudios: connectedStubAudios,
            existingServerCallLogs: const [],
          ),
          isTrue,
        );

        // Answer-time fallback (8s ring shift) still matches existing serverCallLog interval
        expect(
          await AutoCallRecordingUploader.isCallAlreadyUploaded(
            phone: phone,
            timestampMs: answerStart.millisecondsSinceEpoch,
            bound: 'OUT',
            callStatus: 'CONNECTED',
            durationSeconds: 15,
            existingServerAudios: const [],
            existingServerCallLogs: connectedServerLogs,
          ),
          isTrue,
        );

        // 0s MISSED stub at the same timestamp must NEVER block a real connected call
        SharedPreferences.setMockInitialValues({});
        AutoCallRecordingUploader.resetCallDedupStateForTesting();
        final missedOnlyAudios = [
          makeServerAudio(
            id: 'stub-missed',
            start: dialStart,
            bound: 'INBOUND',
            callStatus: 'MISSED',
            durationSeconds: 0,
            size: 0,
          ),
        ];
        expect(
          await AutoCallRecordingUploader.isCallAlreadyUploaded(
            phone: phone,
            timestampMs: dialStart.millisecondsSinceEpoch,
            bound: 'OUT',
            callStatus: 'CONNECTED',
            durationSeconds: 15,
            existingServerAudios: missedOnlyAudios,
            existingServerCallLogs: const [],
          ),
          isFalse,
        );
      },
    );
  });
}

