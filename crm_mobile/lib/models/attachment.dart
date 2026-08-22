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

    final baseUrl = dotenv.env['BASE_URL'] ?? 'http://50.117.0.165:8080/api/crm/lead-service';
    final domain = baseUrl.contains('/api') ? baseUrl.split('/api').first : 'http://50.117.0.165:8080';

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
