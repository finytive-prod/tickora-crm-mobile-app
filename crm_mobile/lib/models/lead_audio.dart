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
        combined.contains('rec_out');
  }

  String get callType {
    final lower = displayName.toLowerCase();
    final lowerFile = fileName.toLowerCase();
    final combined = '$lower $lowerFile';

    // 1. Explicit Outbound check (outgoing calls placed to lead)
    if (combined.contains('outgoing') ||
        combined.contains('outbound') ||
        combined.contains('call_out') ||
        combined.contains('rec_out') ||
        combined.contains('sent')) {
      return 'outbound';
    }

    // 2. Explicit Inbound check (incoming calls received from lead)
    if (combined.contains('incoming') ||
        combined.contains('inbound') ||
        combined.contains('call_in') ||
        combined.contains('rec_in') ||
        combined.contains('recv') ||
        combined.contains('received')) {
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
      ];
}
