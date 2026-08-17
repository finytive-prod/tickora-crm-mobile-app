import 'package:equatable/equatable.dart';
import 'package:crm_mobile/models/custom_field.dart';
import 'package:crm_mobile/models/lead.dart';

import 'package:crm_mobile/models/permission_module.dart';
import 'package:crm_mobile/models/role_entity.dart';

abstract class SettingsState extends Equatable {
  const SettingsState();

  @override
  List<Object?> get props => [];
}

class SettingsInitial extends SettingsState {}

class SettingsLoading extends SettingsState {}

class CustomFieldsLoaded extends SettingsState {
  final List<CustomField> fields;
  final List<String> types;

  const CustomFieldsLoaded(this.fields, this.types);

  @override
  List<Object?> get props => [fields, types];
}

class CustomFieldsSaved extends SettingsState {}

class CustomFieldsUpdated extends SettingsState {}

class LeadStatusesLoaded extends SettingsState {
  final List<LeadStatus> statuses;

  const LeadStatusesLoaded(this.statuses);

  @override
  List<Object?> get props => [statuses];
}

class LeadStatusCreated extends SettingsState {}

class LeadStatusReordered extends SettingsState {}

class DefaultLeadStatusSet extends SettingsState {}

class LeadStatusDeleted extends SettingsState {}

class LeadSourcesLoaded extends SettingsState {
  final List<LeadSource> sources;
  final List<String> categories;

  const LeadSourcesLoaded(this.sources, this.categories);

  @override
  List<Object?> get props => [sources, categories];
}

class LeadSourceCreated extends SettingsState {}

class LeadSourceDeleted extends SettingsState {}

class PermissionModulesLoaded extends SettingsState {
  final List<PermissionModule> modules;

  const PermissionModulesLoaded(this.modules);

  @override
  List<Object?> get props => [modules];
}

class RolesDropdownLoaded extends SettingsState {
  final List<RoleDropdownItem> roles;

  const RolesDropdownLoaded(this.roles);

  @override
  List<Object?> get props => [roles];
}

class RoleDetailsLoaded extends SettingsState {
  final RoleDetail roleDetail;

  const RoleDetailsLoaded(this.roleDetail);

  @override
  List<Object?> get props => [roleDetail];
}

class RoleCreated extends SettingsState {}

class RoleUpdated extends SettingsState {}

class SettingsError extends SettingsState {
  final String message;

  const SettingsError(this.message);

  @override
  List<Object?> get props => [message];
}
