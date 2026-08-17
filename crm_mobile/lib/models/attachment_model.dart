import 'package:crm_mobile/models/attachment.dart';

class AttachmentModel extends Attachment {
  const AttachmentModel({
    required super.id,
    required super.leadId,
    required super.fileName,
    required super.fileType,
    required super.filePath,
    super.uploadedBy,
    super.createdAt,
  });

  factory AttachmentModel.fromJson(Map<String, dynamic> json) {
    return AttachmentModel(
      id: json['id'] ?? '',
      leadId: json['leadId'] ?? '',
      fileName: json['fileName'] ?? '',
      fileType: json['fileType'] ?? '',
      filePath: json['filePath'] ?? '',
      uploadedBy: json['uploadedBy'],
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'leadId': leadId,
      'fileName': fileName,
      'fileType': fileType,
      'filePath': filePath,
      'uploadedBy': uploadedBy,
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}
