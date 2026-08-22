import 'package:equatable/equatable.dart';

class LeadAudio extends Equatable {
  final String id;
  final String leadId;
  final String fileName;
  final String originalFileName;
  final String contentType;
  final int size;
  final DateTime? createdAt;

  const LeadAudio({
    required this.id,
    required this.leadId,
    required this.fileName,
    required this.originalFileName,
    required this.contentType,
    required this.size,
    this.createdAt,
  });

  String get displayName => originalFileName.isNotEmpty ? originalFileName : fileName;

  String get callType {
    final lower = displayName.toLowerCase();
    if (lower.contains('inbound') ||
        lower.contains('incoming') ||
        lower.contains('_in_') ||
        lower.contains('_inc_') ||
        lower.contains('callin') ||
        lower.contains('recv') ||
        lower.contains('received') ||
        lower.contains('(in)') ||
        lower.contains('in_') ||
        lower.contains('inc_')) {
      return 'inbound';
    }
    return 'outbound';
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
      ];
}
