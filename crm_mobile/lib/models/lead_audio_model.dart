import 'package:crm_mobile/models/lead_audio.dart';

class LeadAudioModel extends LeadAudio {
  const LeadAudioModel({
    required super.id,
    required super.leadId,
    required super.fileName,
    required super.originalFileName,
    required super.contentType,
    required super.size,
    super.createdAt,
  });

  factory LeadAudioModel.fromJson(Map<String, dynamic> json) {
    return LeadAudioModel(
      id: json['id']?.toString() ?? '',
      leadId: json['leadId']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      originalFileName: json['originalFileName']?.toString() ?? json['fileName']?.toString() ?? '',
      contentType: json['contentType']?.toString() ?? 'audio/mpeg',
      size: (json['size'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
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
    };
  }
}
