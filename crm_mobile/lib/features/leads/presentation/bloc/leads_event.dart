import 'package:equatable/equatable.dart';

abstract class LeadsEvent extends Equatable {
  const LeadsEvent();

  @override
  List<Object?> get props => [];
}

class FetchLeads extends LeadsEvent {
  final int page;
  final int size;
  final String? statusId;

  const FetchLeads({this.page = 0, this.size = 10, this.statusId});

  @override
  List<Object> get props => [page, size, if (statusId != null) statusId!];
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
