import 'package:equatable/equatable.dart';
import 'package:crm_mobile/models/lead_filter_params.dart';

abstract class LeadsEvent extends Equatable {
  const LeadsEvent();

  @override
  List<Object?> get props => [];
}

class FetchLeads extends LeadsEvent {
  final int page;
  final int size;
  final String? statusId;
  final bool isLoadMore;
  final bool? isActive;
  final LeadFilterParams? filterParams;
  final String? searchQuery;

  const FetchLeads({
    this.page = 0,
    this.size = 15,
    this.statusId,
    this.isLoadMore = false,
    this.isActive,
    this.filterParams,
    this.searchQuery,
  });

  @override
  List<Object?> get props => [page, size, statusId, isLoadMore, isActive, filterParams, searchQuery];
}

class SearchLeads extends LeadsEvent {
  final String query;
  final int page;
  final int size;
  final bool isLoadMore;
  final LeadFilterParams? filterParams;

  const SearchLeads({
    required this.query,
    this.page = 0,
    this.size = 15,
    this.isLoadMore = false,
    this.filterParams,
  });

  @override
  List<Object?> get props => [query, page, size, isLoadMore, filterParams];
}


class FetchLeadStatuses extends LeadsEvent {}

class FetchLeadSources extends LeadsEvent {}

class FetchLeadPriorities extends LeadsEvent {}

class FetchStaffUsers extends LeadsEvent {
  final String? search;
  const FetchStaffUsers({this.search});

  @override
  List<Object> get props => [if (search != null) search!];
}

class FetchCustomFieldsForm extends LeadsEvent {}

class CreateLead extends LeadsEvent {
  final Map<String, dynamic> leadData;
  final List<String> filePaths;
  final String? leadFileName;

  const CreateLead(this.leadData, {this.filePaths = const [], this.leadFileName});

  @override
  List<Object?> get props => [leadData, filePaths, leadFileName];
}

class QuickInviteLead extends LeadsEvent {
  final Map<String, dynamic> data;

  const QuickInviteLead(this.data);

  @override
  List<Object?> get props => [data];
}

class UpdateLead extends LeadsEvent {
  final String leadId;
  final Map<String, dynamic> leadData;
  final List<String> filePaths;
  final String? leadFileName;

  const UpdateLead({
    required this.leadId,
    required this.leadData,
    this.filePaths = const [],
    this.leadFileName,
  });

  @override
  List<Object?> get props => [leadId, leadData, filePaths, leadFileName];
}

class FetchLeadDetails extends LeadsEvent {
  final String id;

  const FetchLeadDetails(this.id);

  @override
  List<Object?> get props => [id];
}

class FetchLeadAuditLogs extends LeadsEvent {
  final String id;

  const FetchLeadAuditLogs(this.id);

  @override
  List<Object?> get props => [id];
}

class FetchLeadAttachments extends LeadsEvent {
  final String id;

  const FetchLeadAttachments(this.id);

  @override
  List<Object?> get props => [id];
}

class UploadLeadAttachment extends LeadsEvent {
  final String leadId;
  final String filePath;

  const UploadLeadAttachment({required this.leadId, required this.filePath});

  @override
  List<Object?> get props => [leadId, filePath];
}

class FetchLeadAudios extends LeadsEvent {
  final String id;

  const FetchLeadAudios(this.id);

  @override
  List<Object?> get props => [id];
}

class FetchLeadCallLogs extends LeadsEvent {
  final String id;

  const FetchLeadCallLogs(this.id);

  @override
  List<Object?> get props => [id];
}

class UploadLeadAudio extends LeadsEvent {
  final String leadId;
  final String? filePath;
  final String? bound;
  final String? startTime;
  final String? endTime;
  final String? from;
  final String? to;
  final String? duration;
  final String? callDate;
  final String? callStatus;

  const UploadLeadAudio({
    required this.leadId,
    this.filePath,
    this.bound,
    this.startTime,
    this.endTime,
    this.from,
    this.to,
    this.duration,
    this.callDate,
    this.callStatus,
  });

  @override
  List<Object?> get props => [
        leadId,
        filePath,
        bound,
        startTime,
        endTime,
        from,
        to,
        duration,
        callDate,
        callStatus,
      ];
}

class UpdateLeadActiveStatus extends LeadsEvent {
  final String leadId;
  final bool isActive;

  const UpdateLeadActiveStatus({
    required this.leadId,
    required this.isActive,
  });

  @override
  List<Object> get props => [leadId, isActive];
}
