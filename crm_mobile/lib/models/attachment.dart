import 'package:equatable/equatable.dart';

class Attachment extends Equatable {
  final String id;
  final String leadId;
  final String fileName;
  final String fileType;
  final String filePath;
  final String? uploadedBy;
  final DateTime? createdAt;

  const Attachment({
    required this.id,
    required this.leadId,
    required this.fileName,
    required this.fileType,
    required this.filePath,
    this.uploadedBy,
    this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        leadId,
        fileName,
        fileType,
        filePath,
        uploadedBy,
        createdAt,
      ];
}
