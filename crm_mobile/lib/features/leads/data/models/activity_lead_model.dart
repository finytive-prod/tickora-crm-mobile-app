import '../../domain/entities/activity_lead.dart';

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
