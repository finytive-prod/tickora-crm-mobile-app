import 'package:equatable/equatable.dart';
import '../../domain/entities/custom_field.dart';
import '../../domain/entities/lead.dart';

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

  const LeadSourcesLoaded(this.sources);

  @override
  List<Object?> get props => [sources];
}

class LeadSourceCreated extends SettingsState {}

class LeadSourceDeleted extends SettingsState {}

class SettingsError extends SettingsState {
  final String message;

  const SettingsError(this.message);

  @override
  List<Object?> get props => [message];
}
