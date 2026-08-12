import 'package:crm_mobile/features/leads/domain/entities/activity_lead.dart';
import 'package:equatable/equatable.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/staff_user.dart';
import '../../domain/entities/custom_field.dart';
import '../../domain/entities/lead_detail.dart';
import '../../domain/entities/attachment.dart';


abstract class LeadsState extends Equatable {
  const LeadsState();

  @override
  List<Object?> get props => [];
}

class LeadsInitial extends LeadsState {}

class LeadsLoading extends LeadsState {}

class LeadsLoaded extends LeadsState {
  final List<Lead> leads;
  final List<LeadStatus> statuses;
  final List<LeadSource> sources;
  final List<String> priorities;
  final List<StaffUser> owners;
  final List<CustomField> customFields;
  final String? selectedStatusId;
  final bool isLeadsLoaded;

  const LeadsLoaded(
    this.leads, {
    this.statuses = const [],
    this.sources = const [],
    this.priorities = const [],
    this.owners = const [],
    this.customFields = const [],
    this.selectedStatusId,
    this.isLeadsLoaded = false,
  });

  LeadsLoaded copyWith({
    List<Lead>? leads,
    List<LeadStatus>? statuses,
    List<LeadSource>? sources,
    List<String>? priorities,
    List<StaffUser>? owners,
    List<CustomField>? customFields,
    String? selectedStatusId,
    bool clearSelectedStatusId = false,
    bool? isLeadsLoaded,
  }) {
    return LeadsLoaded(
      leads ?? this.leads,
      statuses: statuses ?? this.statuses,
      sources: sources ?? this.sources,
      priorities: priorities ?? this.priorities,
      owners: owners ?? this.owners,
      customFields: customFields ?? this.customFields,
      selectedStatusId: clearSelectedStatusId ? null : (selectedStatusId ?? this.selectedStatusId),
      isLeadsLoaded: isLeadsLoaded ?? this.isLeadsLoaded,
    );
  }

  @override
  List<Object?> get props => [
    leads, 
    statuses, 
    sources,
    priorities,
    owners,
    customFields,
    isLeadsLoaded,
    if (selectedStatusId != null) selectedStatusId!
  ];
}

class LeadsError extends LeadsState {
  final String message;

  const LeadsError(this.message);

  @override
  List<Object> get props => [message];
}

class LeadActionLoading extends LeadsState {}

class LeadActionSuccess extends LeadsState {
  final String message;

  const LeadActionSuccess(this.message);

  @override
  List<Object> get props => [message];
}

class LeadActionError extends LeadsState {
  final String message;

  const LeadActionError(this.message);

  @override
  List<Object> get props => [message];
}

class LeadDetailsLoading extends LeadsState {}

class LeadDetailsLoaded extends LeadsState {
  final LeadDetail leadDetail;
  final AuditLogResponse? auditLogs;
  final bool isAuditLogsLoading;
  final String? auditLogsError;
  final List<Attachment>? attachments;
  final bool isAttachmentsLoading;
  final String? attachmentsError;

  const LeadDetailsLoaded(
    this.leadDetail, {
    this.auditLogs,
    this.isAuditLogsLoading = false,
    this.auditLogsError,
    this.attachments,
    this.isAttachmentsLoading = false,
    this.attachmentsError,
  });

  LeadDetailsLoaded copyWith({
    LeadDetail? leadDetail,
    AuditLogResponse? auditLogs,
    bool? isAuditLogsLoading,
    String? auditLogsError,
    List<Attachment>? attachments,
    bool? isAttachmentsLoading,
    String? attachmentsError,
  }) {
    return LeadDetailsLoaded(
      leadDetail ?? this.leadDetail,
      auditLogs: auditLogs ?? this.auditLogs,
      isAuditLogsLoading: isAuditLogsLoading ?? this.isAuditLogsLoading,
      auditLogsError: auditLogsError ?? this.auditLogsError,
      attachments: attachments ?? this.attachments,
      isAttachmentsLoading: isAttachmentsLoading ?? this.isAttachmentsLoading,
      attachmentsError: attachmentsError ?? this.attachmentsError,
    );
  }

  @override
  List<Object?> get props => [
        leadDetail,
        auditLogs,
        isAuditLogsLoading,
        auditLogsError,
        attachments,
        isAttachmentsLoading,
        attachmentsError,
      ];
}

class LeadDetailsError extends LeadsState {
  final String message;

  const LeadDetailsError(this.message);

  @override
  List<Object> get props => [message];
}
