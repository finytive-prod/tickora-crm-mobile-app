import 'package:equatable/equatable.dart';

class AuditLog extends Equatable {
  final String auditId;
  final String entityId;
  final String actionType;
  final String message;
  final String actionBy;
  final String actionByName;
  final DateTime? actionAt;

  const AuditLog({
    required this.auditId,
    required this.entityId,
    required this.actionType,
    required this.message,
    required this.actionBy,
    required this.actionByName,
    this.actionAt,
  });

  @override
  List<Object?> get props => [auditId, entityId, actionType, message, actionBy, actionByName, actionAt];
}

class AuditLogResponse extends Equatable {
  final List<AuditLog> content;
  final int totalPages;
  final int totalElements;

  const AuditLogResponse({
    required this.content,
    required this.totalPages,
    required this.totalElements,
  });

  @override
  List<Object?> get props => [content, totalPages, totalElements];
}
