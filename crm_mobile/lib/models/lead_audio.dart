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
  final String? startTimeStr;
  final String? endTimeStr;
  final String? fromNumber;
  final String? toNumber;
  final String? bound;

  const LeadAudio({
    required this.id,
    required this.leadId,
    required this.fileName,
    required this.originalFileName,
    required this.contentType,
    required this.size,
    this.createdAt,
    this.durationSeconds = 0,
    this.startTimeStr,
    this.endTimeStr,
    this.fromNumber,
    this.toNumber,
    this.bound,
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
      final b = bound!.toUpperCase();
      if (b == 'IN' || b == 'INBOUND' || b == 'INCOMING' || b.contains('IN')) return 'inbound';
      if (b == 'OUT' || b == 'OUTBOUND' || b == 'OUTGOING' || b.contains('OUT')) return 'outbound';
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
        startTimeStr,
        endTimeStr,
        fromNumber,
        toNumber,
        bound,
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
    super.startTimeStr,
    super.endTimeStr,
    super.fromNumber,
    super.toNumber,
    super.bound,
  });

  factory LeadAudioModel.fromJson(Map<String, dynamic> json) {
    int parsedDur = (json['durationSeconds'] as num?)?.toInt() ?? 0;
    if (parsedDur <= 0 && json['duration'] != null) {
      parsedDur = int.tryParse(json['duration'].toString()) ?? 0;
    }

    DateTime? parsedCreatedAt;
    if (json['createdAt'] != null) {
      parsedCreatedAt = DateTime.tryParse(json['createdAt'].toString());
    } else if (json['created_at'] != null) {
      parsedCreatedAt = DateTime.tryParse(json['created_at'].toString());
    } else if (json['callDate'] != null) {
      final cd = json['callDate'].toString();
      final st = json['startTime']?.toString() ?? json['start_time']?.toString() ?? '00:00:00';
      parsedCreatedAt = DateTime.tryParse('${cd}T$st');
    }

    return LeadAudioModel(
      id: json['id']?.toString() ?? '',
      leadId: json['leadId']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      originalFileName: json['originalFileName']?.toString() ?? json['fileName']?.toString() ?? '',
      contentType: json['contentType']?.toString() ?? 'audio/mpeg',
      size: (json['size'] as num?)?.toInt() ?? 0,
      createdAt: parsedCreatedAt,
      durationSeconds: parsedDur,
      startTimeStr: json['startTime']?.toString() ?? json['start_time']?.toString(),
      endTimeStr: json['endTime']?.toString() ?? json['end_time']?.toString(),
      fromNumber: json['from']?.toString() ?? json['fromNumber']?.toString(),
      toNumber: json['to']?.toString() ?? json['toNumber']?.toString(),
      bound: json['bound']?.toString(),
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
      'durationSeconds': durationSeconds,
      'startTime': startTimeStr,
      'endTime': endTimeStr,
      'from': fromNumber,
      'to': toNumber,
      'bound': bound,
    };
  }
}
