import 'package:equatable/equatable.dart';

class LeadAudio extends Equatable {
  final String id;
  final String leadId;
  final String fileName;
  final String originalFileName;
  final String contentType;
  final int size;
  final DateTime? createdAt;
  final int durationSeconds;
  final String? durationStr;
  final String? startTimeStr;
  final String? endTimeStr;
  final String? fromNumber;
  final String? toNumber;
  final String? bound;
  final String? callDate;
  final String? callStatus;
  final String? createdBy;
  final String? owner;
  final String? callHandledBy;

  const LeadAudio({
    required this.id,
    required this.leadId,
    required this.fileName,
    required this.originalFileName,
    required this.contentType,
    required this.size,
    this.createdAt,
    this.durationSeconds = 0,
    this.durationStr,
    this.startTimeStr,
    this.endTimeStr,
    this.fromNumber,
    this.toNumber,
    this.bound,
    this.callDate,
    this.callStatus,
    this.createdBy,
    this.owner,
    this.callHandledBy,
  });

  String get displayName => originalFileName.isNotEmpty ? originalFileName : fileName;

  bool get hasExplicitDirection {
    final lower = displayName.toLowerCase();
    final lowerFile = fileName.toLowerCase();
    final combined = '$lower $lowerFile';
    return combined.contains('incoming') ||
        combined.contains('inbound') ||
        combined.contains('outgoing') ||
        combined.contains('outbound') ||
        combined.contains('call_in') ||
        combined.contains('call_out') ||
        combined.contains('rec_in') ||
        combined.contains('rec_out') ||
        combined.contains('_inc_') ||
        combined.contains('_outg_') ||
        combined.contains('(in)') ||
        combined.contains('(out)') ||
        combined.contains('sent') ||
        combined.contains('recv') ||
        combined.contains('received');
  }

  String get callType {
    if (bound != null && bound!.isNotEmpty) {
      final b = bound!.toUpperCase().trim();
      if (b == 'OUT' || b == 'OUTBOUND' || b == 'OUTGOING' || b.startsWith('OUT')) return 'outbound';
      if (b == 'IN' || b == 'INBOUND' || b == 'INCOMING' || b.startsWith('IN')) return 'inbound';
    }

    final lower = displayName.toLowerCase();
    final lowerFile = fileName.toLowerCase();
    final combined = '$lower $lowerFile';

    // 1. Explicit Outbound check (outgoing calls placed to lead)
    if (combined.contains('outgoing') ||
        combined.contains('outbound') ||
        combined.contains('call_out') ||
        combined.contains('rec_out') ||
        combined.contains('_outg_') ||
        combined.contains('(out)') ||
        combined.contains('sent') ||
        combined.contains('missed_out') ||
        combined.contains('unanswered')) {
      return 'outbound';
    }

    // 2. Explicit Inbound check (incoming calls received from lead)
    if (combined.contains('incoming') ||
        combined.contains('inbound') ||
        combined.contains('call_in') ||
        combined.contains('rec_in') ||
        combined.contains('_inc_') ||
        combined.contains('(in)') ||
        combined.contains('recv') ||
        combined.contains('received') ||
        combined.contains('missed_in') ||
        combined.contains('missed')) {
      return 'inbound';
    }

    return 'inbound';
  }

  @override
  List<Object?> get props => [
        id,
        leadId,
        fileName,
        originalFileName,
        contentType,
        size,
        createdAt,
        durationSeconds,
        durationStr,
        startTimeStr,
        endTimeStr,
        fromNumber,
        toNumber,
        bound,
        callDate,
        callStatus,
        createdBy,
        owner,
        callHandledBy,
      ];
}

class LeadAudioModel extends LeadAudio {
  const LeadAudioModel({
    required super.id,
    required super.leadId,
    required super.fileName,
    required super.originalFileName,
    required super.contentType,
    required super.size,
    super.createdAt,
    super.durationSeconds,
    super.durationStr,
    super.startTimeStr,
    super.endTimeStr,
    super.fromNumber,
    super.toNumber,
    super.bound,
    super.callDate,
    super.callStatus,
    super.createdBy,
    super.owner,
    super.callHandledBy,
  });

  factory LeadAudioModel.fromJson(Map<String, dynamic> json) {
    int parsedDur = 0;
    final rawDur = json['duration'] ?? json['durationSeconds'] ?? json['duration_seconds'];
    String? rawDurStr;
    if (rawDur != null) {
      rawDurStr = rawDur.toString();
      if (rawDur is num) {
        parsedDur = rawDur.toInt();
      } else {
        final str = rawDur.toString().trim();
        if (str.contains(':')) {
          final parts = str.split(':');
          if (parts.length == 3) {
            parsedDur = (int.tryParse(parts[0]) ?? 0) * 3600 +
                (int.tryParse(parts[1]) ?? 0) * 60 +
                (int.tryParse(parts[2]) ?? 0);
          } else if (parts.length == 2) {
            parsedDur = (int.tryParse(parts[0]) ?? 0) * 60 +
                (int.tryParse(parts[1]) ?? 0);
          }
        } else {
          parsedDur = (num.tryParse(str) ?? int.tryParse(str))?.toInt() ?? 0;
        }
      }
    }

    DateTime? parsedCreatedAt;
    if (json['createdAt'] != null) {
      parsedCreatedAt = DateTime.tryParse(json['createdAt'].toString())?.toLocal();
    } else if (json['created_at'] != null) {
      parsedCreatedAt = DateTime.tryParse(json['created_at'].toString())?.toLocal();
    } else if (json['callDate'] != null) {
      final cd = json['callDate'].toString();
      final st = json['startTime']?.toString() ?? json['start_time']?.toString() ?? '00:00:00';
      parsedCreatedAt = DateTime.tryParse('${cd}T$st')?.toLocal();
    }

    return LeadAudioModel(
      id: json['id']?.toString() ?? '',
      leadId: json['leadId']?.toString() ?? json['lead_id']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      originalFileName: json['originalFileName']?.toString() ?? json['fileName']?.toString() ?? '',
      contentType: json['contentType']?.toString() ?? 'audio/mpeg',
      size: (json['size'] as num?)?.toInt() ?? 0,
      createdAt: parsedCreatedAt,
      durationSeconds: parsedDur,
      durationStr: rawDurStr,
      startTimeStr: json['startTime']?.toString() ?? json['start_time']?.toString() ?? json['startTimeStr']?.toString(),
      endTimeStr: json['endTime']?.toString() ?? json['end_time']?.toString() ?? json['endTimeStr']?.toString(),
      fromNumber: json['fromNumber']?.toString() ?? json['from_number']?.toString() ?? json['from']?.toString(),
      toNumber: json['toNumber']?.toString() ?? json['to_number']?.toString() ?? json['to']?.toString(),
      bound: json['bound']?.toString(),
      callDate: json['callDate']?.toString() ?? json['call_date']?.toString(),
      callStatus: json['callStatus']?.toString() ?? json['call_status']?.toString() ?? json['status']?.toString(),
      createdBy: json['createdBy']?.toString() ?? json['created_by']?.toString(),
      owner: json['owner']?.toString() ?? json['ownerName']?.toString() ?? json['owner_name']?.toString(),
      callHandledBy: json['callHandledBy']?.toString() ?? json['call_handled_by']?.toString() ?? json['handledBy']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'leadId': leadId,
      'fileName': fileName,
      'originalFileName': originalFileName,
      'contentType': contentType,
      'size': size,
      'createdAt': createdAt?.toIso8601String(),
      'duration': durationStr ?? durationSeconds.toString(),
      'durationSeconds': durationSeconds,
      'startTime': startTimeStr,
      'endTime': endTimeStr,
      'fromNumber': fromNumber,
      'toNumber': toNumber,
      'bound': bound,
      'callDate': callDate,
      'callStatus': callStatus,
      'createdBy': createdBy,
      'owner': owner,
      'callHandledBy': callHandledBy,
    };
  }
}
