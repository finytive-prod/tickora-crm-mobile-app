import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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

  String get fullUrl {
    if (filePath.isEmpty) return '';

    try {
      if (File(filePath).existsSync()) {
        return filePath;
      }
    } catch (_) {}

    final baseUrl = dotenv.env['BASE_URL'] ?? '';
    final domain = baseUrl.contains('/api') ? baseUrl.split('/api').first : baseUrl;

    String url = filePath;

    if (url.startsWith('http://localhost') || url.startsWith('http://127.0.0.1')) {
      url = url.replaceFirst(RegExp(r'http://(localhost|127\.0\.0\.1)(:\d+)?'), domain);
    } else if (url.startsWith('https://localhost') || url.startsWith('https://127.0.0.1')) {
      url = url.replaceFirst(RegExp(r'https://(localhost|127\.0\.0\.1)(:\d+)?'), domain);
    }

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    if (url.startsWith('/api')) {
      return '$domain$url';
    }

    final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final cleanPath = url.startsWith('/') ? url : '/$url';
    return '$cleanBase$cleanPath';
  }

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
