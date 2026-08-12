import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/get_custom_fields_list_usecase.dart';
import '../../domain/usecases/create_custom_fields_usecase.dart';
import '../../domain/usecases/get_custom_field_types_usecase.dart';
import '../../domain/usecases/get_lead_statuses_usecase.dart';
import '../../domain/usecases/get_lead_sources_usecase.dart';
import '../../domain/usecases/update_custom_fields_usecase.dart';
import '../../domain/usecases/reorder_lead_status_usecase.dart';
import '../../domain/usecases/set_default_lead_status_usecase.dart';
import '../../domain/usecases/create_lead_status_usecase.dart';
import 'settings_event.dart';
import 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final GetCustomFieldsListUseCase getCustomFieldsListUseCase;
  final CreateCustomFieldsUseCase createCustomFieldsUseCase;
  final GetCustomFieldTypesUseCase getCustomFieldTypesUseCase;
  final GetLeadStatusesUseCase getLeadStatusesUseCase;
  final GetLeadSourcesUseCase getLeadSourcesUseCase;
  final UpdateCustomFieldsUseCase updateCustomFieldsUseCase;
  final ReorderLeadStatusUseCase reorderLeadStatusUseCase;
  final SetDefaultLeadStatusUseCase setDefaultLeadStatusUseCase;
  final CreateLeadStatusUseCase createLeadStatusUseCase;

  SettingsBloc({
    required this.getCustomFieldsListUseCase,
    required this.createCustomFieldsUseCase,
    required this.getCustomFieldTypesUseCase,
    required this.getLeadStatusesUseCase,
    required this.getLeadSourcesUseCase,
    required this.updateCustomFieldsUseCase,
    required this.reorderLeadStatusUseCase,
    required this.setDefaultLeadStatusUseCase,
    required this.createLeadStatusUseCase,
  }) : super(SettingsInitial()) {
    on<FetchCustomFields>(_onFetchCustomFields);
    on<SaveCustomFields>(_onSaveCustomFields);
    on<UpdateCustomFields>(_onUpdateCustomFields);
    on<FetchLeadStatuses>(_onFetchLeadStatuses);
    on<CreateLeadStatus>(_onCreateLeadStatus);
    on<ReorderLeadStatus>(_onReorderLeadStatus);
    on<SetDefaultLeadStatus>(_onSetDefaultLeadStatus);
    on<FetchLeadSources>(_onFetchLeadSources);
  }

  Future<void> _onFetchCustomFields(
    FetchCustomFields event,
    Emitter<SettingsState> emit,
  ) async {
    emit(SettingsLoading());
    final typesResult = await getCustomFieldTypesUseCase();
    final fieldsResult = await getCustomFieldsListUseCase();

    List<String> types = [];
    typesResult.fold(
      (_) => types = ['TEXT', 'NUMBER', 'DROPDOWN', 'CHECKBOX', 'DATE', 'TEXTAREA', 'ATTACHMENT'],
      (t) => types = t,
    );

    fieldsResult.fold(
      (failure) {
        emit(SettingsError(failure.message));
      },
      (fields) {
        emit(CustomFieldsLoaded(fields, types));
      },
    );
  }

  Future<void> _onSaveCustomFields(
    SaveCustomFields event,
    Emitter<SettingsState> emit,
  ) async {
    emit(SettingsLoading());
    final result = await createCustomFieldsUseCase(event.fields);

    result.fold(
      (failure) => emit(SettingsError(failure.message)),
      (_) => emit(CustomFieldsSaved()),
    );
  }

  Future<void> _onUpdateCustomFields(
    UpdateCustomFields event,
    Emitter<SettingsState> emit,
  ) async {
    emit(SettingsLoading());
    final result = await updateCustomFieldsUseCase(event.fields);

    result.fold(
      (failure) => emit(SettingsError(failure.message)),
      (_) => emit(CustomFieldsUpdated()),
    );
  }

  Future<void> _onFetchLeadStatuses(
    FetchLeadStatuses event,
    Emitter<SettingsState> emit,
  ) async {
    emit(SettingsLoading());
    final result = await getLeadStatusesUseCase();

    result.fold(
      (failure) => emit(SettingsError(failure.message)),
      (statuses) => emit(LeadStatusesLoaded(statuses)),
    );
  }

  Future<void> _onReorderLeadStatus(
    ReorderLeadStatus event,
    Emitter<SettingsState> emit,
  ) async {
    emit(SettingsLoading());
    final result = await reorderLeadStatusUseCase(event.id, event.displayOrder);

    result.fold(
      (failure) => emit(SettingsError(failure.message)),
      (_) => emit(LeadStatusReordered()),
    );
  }

  Future<void> _onSetDefaultLeadStatus(
    SetDefaultLeadStatus event,
    Emitter<SettingsState> emit,
  ) async {
    emit(SettingsLoading());
    final result = await setDefaultLeadStatusUseCase(event.id);

    result.fold(
      (failure) => emit(SettingsError(failure.message)),
      (_) => emit(DefaultLeadStatusSet()),
    );
  }

  Future<void> _onCreateLeadStatus(
    CreateLeadStatus event,
    Emitter<SettingsState> emit,
  ) async {
    emit(SettingsLoading());
    final result = await createLeadStatusUseCase(event.statusData);

    result.fold(
      (failure) => emit(SettingsError(failure.message)),
      (_) => emit(LeadStatusCreated()),
    );
  }

  Future<void> _onFetchLeadSources(
    FetchLeadSources event,
    Emitter<SettingsState> emit,
  ) async {
    emit(SettingsLoading());
    final result = await getLeadSourcesUseCase();

    result.fold(
      (failure) => emit(SettingsError(failure.message)),
      (sources) => emit(LeadSourcesLoaded(sources)),
    );
  }
}
