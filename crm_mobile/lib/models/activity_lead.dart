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

class AuditLogModel extends AuditLog {
  const AuditLogModel({
    required super.auditId,
    required super.entityId,
    required super.actionType,
    required super.message,
    required super.actionBy,
    required super.actionByName,
    super.actionAt,
  });

  factory AuditLogModel.fromJson(Map<String, dynamic> json) {
    return AuditLogModel(
      auditId: json['auditId'] ?? '',
      entityId: json['entityId'] ?? '',
      actionType: json['actionType'] ?? '',
      message: json['message'] ?? '',
      actionBy: json['actionBy'] ?? '',
      actionByName: json['actionByName'] ?? '',
      actionAt: json['actionAt'] != null ? DateTime.tryParse(json['actionAt']) : null,
    );
  }
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

class AuditLogResponseModel extends AuditLogResponse {
  const AuditLogResponseModel({
    required super.content,
    required super.totalPages,
    required super.totalElements,
  });

  factory AuditLogResponseModel.fromJson(Map<String, dynamic> json) {
    final List<dynamic> list = json['content'] ?? [];
    final content = list.map((e) => AuditLogModel.fromJson(e)).toList();
    return AuditLogResponseModel(
      content: content,
      totalPages: json['totalPages'] ?? 0,
      totalElements: json['totalElements'] ?? 0,
    );
  }
}
