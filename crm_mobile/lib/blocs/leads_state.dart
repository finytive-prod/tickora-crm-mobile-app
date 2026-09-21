import 'package:crm_mobile/models/activity_lead.dart';
import 'package:equatable/equatable.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/models/staff_user.dart';
import 'package:crm_mobile/models/custom_field.dart';
import 'package:crm_mobile/models/lead_detail.dart';
import 'package:crm_mobile/models/attachment.dart';
import 'package:crm_mobile/models/lead_audio.dart';
import 'package:crm_mobile/models/lead_form_layout.dart';
import 'package:crm_mobile/models/lead_filter_params.dart';

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
  final List<FixedField> fixedFields;
  final String? selectedStatusId;
  final bool? selectedIsActive;
  final bool isLeadsLoaded;
  final int currentPage;
  final bool hasMoreLeads;
  final bool isLoadingMore;
  final String? searchQuery;
  final LeadFilterParams? filterParams;

  const LeadsLoaded(
    this.leads, {
    this.statuses = const [],
    this.sources = const [],
    this.priorities = const [],
    this.owners = const [],
    this.customFields = const [],
    this.fixedFields = const [],
    this.selectedStatusId,
    this.selectedIsActive,
    this.isLeadsLoaded = false,
    this.currentPage = 0,
    this.hasMoreLeads = true,
    this.isLoadingMore = false,
    this.searchQuery,
    this.filterParams,
  });

  LeadsLoaded copyWith({
    List<Lead>? leads,
    List<LeadStatus>? statuses,
    List<LeadSource>? sources,
    List<String>? priorities,
    List<StaffUser>? owners,
    List<CustomField>? customFields,
    List<FixedField>? fixedFields,
    String? selectedStatusId,
    bool clearSelectedStatusId = false,
    bool? selectedIsActive,
    bool clearSelectedIsActive = false,
    bool? isLeadsLoaded,
    int? currentPage,
    bool? hasMoreLeads,
    bool? isLoadingMore,
    String? searchQuery,
    LeadFilterParams? filterParams,
    bool clearFilterParams = false,
  }) {
    return LeadsLoaded(
      leads ?? this.leads,
      statuses: statuses ?? this.statuses,
      sources: sources ?? this.sources,
      priorities: priorities ?? this.priorities,
      owners: owners ?? this.owners,
      customFields: customFields ?? this.customFields,
      fixedFields: fixedFields ?? this.fixedFields,
      selectedStatusId: clearSelectedStatusId ? null : (selectedStatusId ?? this.selectedStatusId),
      selectedIsActive: clearSelectedIsActive ? null : (selectedIsActive ?? this.selectedIsActive),
      isLeadsLoaded: isLeadsLoaded ?? this.isLeadsLoaded,
      currentPage: currentPage ?? this.currentPage,
      hasMoreLeads: hasMoreLeads ?? this.hasMoreLeads,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      searchQuery: searchQuery ?? this.searchQuery,
      filterParams: clearFilterParams ? null : (filterParams ?? this.filterParams),
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
    fixedFields,
    selectedStatusId,
    selectedIsActive,
    isLeadsLoaded,
    currentPage,
    hasMoreLeads,
    isLoadingMore,
    searchQuery,
    filterParams,
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
  final List<LeadAudio>? audios;
  final bool isAudiosLoading;
  final String? audiosError;

  const LeadDetailsLoaded(
    this.leadDetail, {
    this.auditLogs,
    this.isAuditLogsLoading = false,
    this.auditLogsError,
    this.attachments,
    this.isAttachmentsLoading = false,
    this.attachmentsError,
    this.audios,
    this.isAudiosLoading = false,
    this.audiosError,
  });

  LeadDetailsLoaded copyWith({
    LeadDetail? leadDetail,
    AuditLogResponse? auditLogs,
    bool? isAuditLogsLoading,
    String? auditLogsError,
    List<Attachment>? attachments,
    bool? isAttachmentsLoading,
    String? attachmentsError,
    List<LeadAudio>? audios,
    bool? isAudiosLoading,
    String? audiosError,
  }) {
    return LeadDetailsLoaded(
      leadDetail ?? this.leadDetail,
      auditLogs: auditLogs ?? this.auditLogs,
      isAuditLogsLoading: isAuditLogsLoading ?? this.isAuditLogsLoading,
      auditLogsError: auditLogsError ?? this.auditLogsError,
      attachments: attachments ?? this.attachments,
      isAttachmentsLoading: isAttachmentsLoading ?? this.isAttachmentsLoading,
      attachmentsError: attachmentsError ?? this.attachmentsError,
      audios: audios ?? this.audios,
      isAudiosLoading: isAudiosLoading ?? this.isAudiosLoading,
      audiosError: audiosError ?? this.audiosError,
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
        audios,
        isAudiosLoading,
        audiosError,
      ];
}

class LeadDetailsError extends LeadsState {
  final String message;

  const LeadDetailsError(this.message);

  @override
  List<Object> get props => [message];
}
