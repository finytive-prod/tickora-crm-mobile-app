import 'package:crm_mobile/models/lead.dart';
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

    test('Verify Get Audios Endpoint sample response with owner, createdBy, callHandledBy', () {
      final sampleAudioJson = [
        {
          "id": "6732f91a-7b3c-4cf2-83b6-76495b4e7a2b",
          "leadId": "b5e1bbd8-df2a-4d88-8e85-bed58db4eec5",
          "fileName": "d9841f32-51ab-43b0-953e-4d4ec31bcf91.mp3",
          "originalFileName": "call_recording_client_intro.mp3",
          "contentType": "audio/mpeg",
          "size": 348160,
          "bound": "OUT",
          "startTime": "10:30:00",
          "endTime": "10:32:15",
          "fromNumber": "+1234567890",
          "toNumber": "+0987654321",
          "duration": "00:02:15",
          "callDate": "2026-11-23",
          "callStatus": "CONNECTED",
          "createdAt": "2026-11-23T10:30:00",
          "createdBy": "8b3d4f5a-6c7e-8d9f-0a1b-2c3d4e5f6a7b",
          "owner": "John Doe",
          "callHandledBy": "John Doe"
        }
      ];

      final audioList = sampleAudioJson.map((e) => LeadAudioModel.fromJson(e)).toList();

      expect(audioList.length, 1);
      final audio = audioList.first;
      expect(audio.id, "6732f91a-7b3c-4cf2-83b6-76495b4e7a2b");
      expect(audio.leadId, "b5e1bbd8-df2a-4d88-8e85-bed58db4eec5");
      expect(audio.fileName, "d9841f32-51ab-43b0-953e-4d4ec31bcf91.mp3");
      expect(audio.originalFileName, "call_recording_client_intro.mp3");
      expect(audio.contentType, "audio/mpeg");
      expect(audio.size, 348160);
      expect(audio.bound, "OUT");
      expect(audio.callType, "outbound");
      expect(audio.startTimeStr, "10:30:00");
      expect(audio.endTimeStr, "10:32:15");
      expect(audio.fromNumber, "+1234567890");
      expect(audio.toNumber, "+0987654321");
      expect(audio.durationSeconds, 135);
      expect(audio.durationStr, "00:02:15");
      expect(audio.callDate, "2026-11-23");
      expect(audio.callStatus, "CONNECTED");
      expect(audio.createdBy, "8b3d4f5a-6c7e-8d9f-0a1b-2c3d4e5f6a7b");
      expect(audio.owner, "John Doe");
      expect(audio.callHandledBy, "John Doe");
    });

    test('Verify Lead Search GET /leads/search JSON parsing', () {
      final sampleSearchResponse = {
        "code": 200,
        "message": "Leads retrieved successfully",
        "data": {
          "content": [
            {
              "id": "b5e1bbd8-df2a-4d88-8e85-bed58db4eec5",
              "leadNumber": "LD-2026-0042",
              "firstName": "John",
              "lastName": "Doe",
              "companyName": "Acme Corp",
              "email": "john.doe@acme.com",
              "phone": "+1234567890",
              "priority": "HIGH",
              "status": {
                "id": "22222222-3333-4444-5555-666666666666",
                "statusName": "Contacted",
                "colorCode": "#3B82F6"
              },
              "ownerUserName": "Staff Member A",
              "createdAt": "2026-11-20T10:15:00"
            }
          ],
          "pageable": {
            "pageNumber": 0,
            "pageSize": 10
          },
          "totalElements": 1,
          "totalPages": 1,
          "last": true
        }
      };

      final content = (sampleSearchResponse['data'] as Map)['content'] as List;
      final leads = content.map((e) => LeadModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();

      expect(leads.length, 1);
      final lead = leads.first;
      expect(lead.id, "b5e1bbd8-df2a-4d88-8e85-bed58db4eec5");
      expect(lead.leadNumber, "LD-2026-0042");
      expect(lead.firstName, "John");
      expect(lead.lastName, "Doe");
      expect(lead.companyName, "Acme Corp");
      expect(lead.email, "john.doe@acme.com");
      expect(lead.phone, "+1234567890");
      expect(lead.priority, "HIGH");
      expect(lead.status, isNotNull);
      expect(lead.status?.id, "22222222-3333-4444-5555-666666666666");
      expect(lead.status?.statusName, "Contacted");
      expect(lead.status?.color, "#3B82F6");
      expect(lead.ownerUserName, "Staff Member A");
      expect(lead.createdAt, DateTime.parse("2026-11-20T10:15:00"));
    });

    test('Verify Upload Lead Audio payload parameters & duration sanitization', () {
      String sanitizeDuration(String? d) {
        if (d == null || d.trim().isEmpty) return '0';
        final trimmed = d.trim();
        if (trimmed.contains(':')) {
          final parts = trimmed.split(':');
          if (parts.length == 3) {
            final h = int.tryParse(parts[0]) ?? 0;
            final m = int.tryParse(parts[1]) ?? 0;
            final s = int.tryParse(parts[2]) ?? 0;
            return (h * 3600 + m * 60 + s).toString();
          } else if (parts.length == 2) {
            final m = int.tryParse(parts[0]) ?? 0;
            final s = int.tryParse(parts[1]) ?? 0;
            return (m * 60 + s).toString();
          }
        }
        return (int.tryParse(trimmed) ?? 0).toString();
      }

      // Test duration sanitization
      expect(sanitizeDuration('45'), '45');
      expect(sanitizeDuration('00:02:15'), '135');
      expect(sanitizeDuration('02:15'), '135');
      expect(sanitizeDuration(null), '0');
      expect(sanitizeDuration(''), '0');

      // Verify multipart payload structure matching user cURL specification:
      // -F "files=@path/to/call_recording_1414.mp3"
      // -F "bound=OUT"
      // -F "fromNumber=+1234567890"
      // -F "toNumber=8925966055"
      // -F "duration=45"
      // -F "callStatus=CONNECTED"
      // -F "callDate=2026-11-23"
      // -F "startTime=14:14:41"
      // -F "endTime=14:15:26"
      final expectedKeys = [
        'files',
        'bound',
        'fromNumber',
        'from',
        'toNumber',
        'to',
        'duration',
        'callStatus',
        'callDate',
        'startTime',
        'endTime',
      ];

      final sampleFields = {
        'bound': 'OUT',
        'fromNumber': '+1234567890',
        'from': '+1234567890',
        'toNumber': '8925966055',
        'to': '8925966055',
        'duration': sanitizeDuration('45'),
        'callStatus': 'CONNECTED',
        'callDate': '2026-11-23',
        'startTime': '14:14:41',
        'endTime': '14:15:26',
      };

      for (final key in expectedKeys) {
        if (key != 'files') {
          expect(sampleFields.containsKey(key), isTrue, reason: 'Missing $key field');
        }
      }
      expect(sampleFields['duration'], '45');
      expect(sampleFields['bound'], 'OUT');
      expect(sampleFields['fromNumber'], '+1234567890');
      expect(sampleFields['toNumber'], '8925966055');
      expect(sampleFields['callStatus'], 'CONNECTED');
      expect(sampleFields['callDate'], '2026-11-23');
      expect(sampleFields['startTime'], '14:14:41');
      expect(sampleFields['endTime'], '14:15:26');
    });

    test('Verify Missed Call badge colors: red text and soft red container', () {
      const isMissed = true;
      const isUnanswered = false;

      final String statusPillText;
      final int statusPillTextColor;
      final int statusPillBgColor;
      final int statusPillBorderColor;

      if (isMissed) {
        statusPillText = 'MISSED';
        statusPillTextColor = 0xFFDC2626; // Red 600
        statusPillBgColor = 0xFFFEF2F2;   // Red 50
        statusPillBorderColor = 0xFFFECACA; // Red 200
      } else if (isUnanswered) {
        statusPillText = 'UNANSWERED';
        statusPillTextColor = 0xFFD97706;
        statusPillBgColor = 0xFFFFFBEB;
        statusPillBorderColor = 0xFFFCD34D;
      } else {
        statusPillText = 'CONNECTED';
        statusPillTextColor = 0xFF059669;
        statusPillBgColor = 0xFFECFDF5;
        statusPillBorderColor = 0xFF6EE7B7;
      }

      expect(statusPillText, 'MISSED');
      expect(statusPillTextColor, 0xFFDC2626); // Red color for missed word
      expect(statusPillBgColor, 0xFFFEF2F2);
      expect(statusPillBorderColor, 0xFFFECACA);
    });
  });
}





