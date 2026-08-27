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
    
    // Explicit Outbound check first
    if (lower.contains('outgoing') ||
        lower.contains('outbound') ||
        lower.contains('_out_') ||
        lower.contains('_outg_') ||
        lower.contains('callout') ||
        lower.contains('sent') ||
        lower.contains('(out)') ||
        lower.contains('out_')) {
      return 'outbound';
    }

    // Explicit Inbound check (without matching 'recording_')
    if (lower.contains('incoming') ||
        lower.contains('inbound') ||
        lower.contains('_in_') ||
        lower.contains('_inc_') ||
        lower.contains('callin') ||
        lower.contains('recv') ||
        lower.contains('received') ||
        lower.contains('(in)')) {
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
