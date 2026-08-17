import 'package:equatable/equatable.dart';

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

class FetchCustomFields extends SettingsEvent {}

class SaveCustomFields extends SettingsEvent {
  final List<Map<String, dynamic>> fields;

  const SaveCustomFields(this.fields);

  @override
  List<Object?> get props => [fields];
}

class UpdateCustomFields extends SettingsEvent {
  final List<Map<String, dynamic>> fields;

  const UpdateCustomFields(this.fields);

  @override
  List<Object?> get props => [fields];
}

class FetchLeadStatuses extends SettingsEvent {}

class ReorderLeadStatus extends SettingsEvent {
  final String id;
  final int displayOrder;

  const ReorderLeadStatus(this.id, this.displayOrder);

  @override
  List<Object?> get props => [id, displayOrder];
}

class SetDefaultLeadStatus extends SettingsEvent {
  final String id;

  const SetDefaultLeadStatus(this.id);

  @override
  List<Object?> get props => [id];
}

class CreateLeadStatus extends SettingsEvent {
  final Map<String, dynamic> statusData;

  const CreateLeadStatus(this.statusData);

  @override
  List<Object?> get props => [statusData];
}

class DeleteLeadStatus extends SettingsEvent {
  final String id;

  const DeleteLeadStatus(this.id);

  @override
  List<Object?> get props => [id];
}

class FetchLeadSources extends SettingsEvent {}

class CreateLeadSource extends SettingsEvent {
  final Map<String, dynamic> sourceData;

  const CreateLeadSource(this.sourceData);

  @override
  List<Object?> get props => [sourceData];
}

class DeleteLeadSource extends SettingsEvent {
  final String id;

  const DeleteLeadSource(this.id);

  @override
  List<Object?> get props => [id];
}

class FetchPermissionModules extends SettingsEvent {}

class FetchRolesDropdown extends SettingsEvent {}

class FetchRoleDetails extends SettingsEvent {
  final String id;

  const FetchRoleDetails(this.id);

  @override
  List<Object?> get props => [id];
}

class CreateRole extends SettingsEvent {
  final Map<String, dynamic> roleData;

  const CreateRole(this.roleData);

  @override
  List<Object?> get props => [roleData];
}

class UpdateRole extends SettingsEvent {
  final String id;
  final Map<String, dynamic> roleData;

  const UpdateRole(this.id, this.roleData);

  @override
  List<Object?> get props => [id, roleData];
}
