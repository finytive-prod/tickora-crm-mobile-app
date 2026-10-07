import 'package:flutter_test/flutter_test.dart';
import 'package:crm_mobile/models/lead_audio.dart';
import 'package:crm_mobile/models/lead_call_log.dart';

void main() {
  group('Lead Audio & Call Log Endpoint verification tests', () {
    test('Verify Get Audios by Lead ID JSON parsing', () {
      final audioJson = [
        {
          "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "leadId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "fileName": "audio_123.mp3",
          "originalFileName": "my_recording.mp3",
          "contentType": "audio/mpeg",
          "size": 1024500,
          "bound": "INBOUND", 
          "startTime": "10:00:00",
          "endTime": "10:05:00",
          "fromNumber": "+1234567890",
          "toNumber": "+0987654321",
          "duration": "300", 
          "callDate": "2026-10-03",
          "callStatus": "COMPLETED", 
          "createdAt": "2026-10-03T10:05:01"
        }
      ];

      final audioList = audioJson.map((e) => LeadAudioModel.fromJson(e)).toList();

      expect(audioList.length, 1);
      final audio = audioList.first;
      expect(audio.id, "3fa85f64-5717-4562-b3fc-2c963f66afa6");
      expect(audio.leadId, "3fa85f64-5717-4562-b3fc-2c963f66afa6");
      expect(audio.fileName, "audio_123.mp3");
      expect(audio.originalFileName, "my_recording.mp3");
      expect(audio.contentType, "audio/mpeg");
      expect(audio.size, 1024500);
      expect(audio.bound, "INBOUND");
      expect(audio.callType, "inbound");
      expect(audio.startTimeStr, "10:00:00");
      expect(audio.endTimeStr, "10:05:00");
      expect(audio.fromNumber, "+1234567890");
      expect(audio.toNumber, "+0987654321");
      expect(audio.durationSeconds, 300);
      expect(audio.callDate, "2026-10-03");
      expect(audio.callStatus, "COMPLETED");
      expect(audio.createdAt, isNotNull);
    });

    test('Verify Get Call Log History by Lead ID JSON parsing', () {
      final callLogJson = {
        "totalCalls": 15,
        "totalInboundCalls": 10,
        "totalOutboundCalls": 5,
        "totalMissedCalls": 2,
        "totalDuration": 4500,
        "callHistory": [
          {
            "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
            "leadId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
            "bound": "OUTBOUND",
            "startTime": "14:20:00",
            "endTime": "14:25:00",
            "fromNumber": "+0987654321",
            "toNumber": "+1234567890",
            "duration": "300",
            "callDate": "2026-10-02",
            "callStatus": "MISSED",
            "createdAt": "2026-10-02T14:25:01"
          }
        ]
      };

      final response = LeadCallLogResponse.fromJson(callLogJson);

      expect(response.totalCalls, 15);
      expect(response.totalInboundCalls, 10);
      expect(response.totalOutboundCalls, 5);
      expect(response.totalMissedCalls, 2);
      expect(response.totalDuration, 4500);
      expect(response.callHistory.length, 1);

      final log = response.callHistory.first;
      expect(log.id, "3fa85f64-5717-4562-b3fc-2c963f66afa6");
      expect(log.leadId, "3fa85f64-5717-4562-b3fc-2c963f66afa6");
      expect(log.bound, "OUTBOUND");
      expect(log.startTime, "14:20:00");
      expect(log.endTime, "14:25:00");
      expect(log.fromNumber, "+0987654321");
      expect(log.toNumber, "+1234567890");
      expect(log.duration, "300");
      expect(log.callDate, "2026-10-02");
      expect(log.callStatus, "MISSED");
      expect(log.createdAt, "2026-10-02T14:25:01");
    });
  });
}
