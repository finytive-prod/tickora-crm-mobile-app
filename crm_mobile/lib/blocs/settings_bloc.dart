import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/usecases/get_custom_fields_list_usecase.dart';
import 'package:crm_mobile/usecases/create_custom_fields_usecase.dart';
import 'package:crm_mobile/usecases/get_custom_field_types_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_statuses_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_sources_usecase.dart';
import 'package:crm_mobile/usecases/update_custom_fields_usecase.dart';
import 'package:crm_mobile/usecases/reorder_lead_status_usecase.dart';
import 'package:crm_mobile/usecases/set_default_lead_status_usecase.dart';
import 'package:crm_mobile/usecases/create_lead_status_usecase.dart';
import 'package:crm_mobile/usecases/create_lead_source_usecase.dart';
import 'package:crm_mobile/usecases/delete_lead_source_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_source_categories_usecase.dart';
import 'package:crm_mobile/usecases/get_permission_modules_usecase.dart';
import 'package:crm_mobile/usecases/get_roles_dropdown_usecase.dart';
import 'package:crm_mobile/usecases/get_role_details_usecase.dart';
import 'package:crm_mobile/usecases/create_role_usecase.dart';
import 'package:crm_mobile/usecases/update_role_usecase.dart';
import 'package:crm_mobile/usecases/reorder_role_priority_usecase.dart';
import 'package:crm_mobile/blocs/settings_event.dart';
import 'package:crm_mobile/blocs/settings_state.dart';

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
  final CreateLeadSourceUseCase createLeadSourceUseCase;
  final DeleteLeadSourceUseCase deleteLeadSourceUseCase;
  final GetLeadSourceCategoriesUseCase getLeadSourceCategoriesUseCase;
  final GetPermissionModulesUseCase getPermissionModulesUseCase;
  final GetRolesDropdownUseCase getRolesDropdownUseCase;
  final GetRoleDetailsUseCase getRoleDetailsUseCase;
  final CreateRoleUseCase createRoleUseCase;
  final UpdateRoleUseCase updateRoleUseCase;
  final ReorderRolePriorityUseCase reorderRolePriorityUseCase;

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
    required this.createLeadSourceUseCase,
    required this.deleteLeadSourceUseCase,
    required this.getLeadSourceCategoriesUseCase,
    required this.getPermissionModulesUseCase,
    required this.getRolesDropdownUseCase,
    required this.getRoleDetailsUseCase,
    required this.createRoleUseCase,
    required this.updateRoleUseCase,
    required this.reorderRolePriorityUseCase,
  }) : super(SettingsInitial()) {
    on<FetchCustomFields>(_onFetchCustomFields);
    on<SaveCustomFields>(_onSaveCustomFields);
    on<UpdateCustomFields>(_onUpdateCustomFields);
    on<FetchLeadStatuses>(_onFetchLeadStatuses);
    on<CreateLeadStatus>(_onCreateLeadStatus);
    on<ReorderLeadStatus>(_onReorderLeadStatus);
    on<SetDefaultLeadStatus>(_onSetDefaultLeadStatus);
    on<FetchLeadSources>(_onFetchLeadSources);
    on<CreateLeadSource>(_onCreateLeadSource);
    on<DeleteLeadSource>(_onDeleteLeadSource);
    on<FetchPermissionModules>(_onFetchPermissionModules);
    on<FetchRolesDropdown>(_onFetchRolesDropdown);
    on<FetchRoleDetails>(_onFetchRoleDetails);
    on<CreateRole>(_onCreateRole);
    on<UpdateRole>(_onUpdateRole);
    on<ReorderRolePriority>(_onReorderRolePriority);
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
    final categoriesResult = await getLeadSourceCategoriesUseCase();
    final sourcesResult = await getLeadSourcesUseCase();

    List<String> categories = [];
    categoriesResult.fold(
      (_) => categories = ['DIGITAL', 'SOCIAL_MEDIA', 'PAID_SEARCH', 'PARTNER', 'IN_PERSON', 'MARKETING', 'OUTBOUND', 'WEBSITE', 'REFERRAL', 'OTHER'],
      (c) => categories = c,
    );

    sourcesResult.fold(
      (failure) => emit(SettingsError(failure.message)),
      (sources) => emit(LeadSourcesLoaded(sources, categories)),
    );
  }

  Future<void> _onCreateLeadSource(
    CreateLeadSource event,
    Emitter<SettingsState> emit,
  ) async {
    emit(SettingsLoading());
    final result = await createLeadSourceUseCase(event.sourceData);

    result.fold(
      (failure) => emit(SettingsError(failure.message)),
      (_) => emit(LeadSourceCreated()),
    );
  }

  Future<void> _onDeleteLeadSource(
    DeleteLeadSource event,
    Emitter<SettingsState> emit,
  ) async {
    emit(SettingsLoading());
    final result = await deleteLeadSourceUseCase(event.id);

    result.fold(
      (failure) => emit(SettingsError(failure.message)),
      (_) => emit(LeadSourceDeleted()),
    );
  }

  Future<void> _onFetchPermissionModules(
    FetchPermissionModules event,
    Emitter<SettingsState> emit,
  ) async {
    emit(SettingsLoading());
    final result = await getPermissionModulesUseCase();

    result.fold(
      (failure) => emit(SettingsError(failure.message)),
      (modules) => emit(PermissionModulesLoaded(modules)),
    );
  }

  Future<void> _onFetchRolesDropdown(
    FetchRolesDropdown event,
    Emitter<SettingsState> emit,
  ) async {
    emit(SettingsLoading());
    final result = await getRolesDropdownUseCase();

    result.fold(
      (failure) => emit(SettingsError(failure.message)),
      (roles) => emit(RolesDropdownLoaded(roles)),
    );
  }

  Future<void> _onFetchRoleDetails(
    FetchRoleDetails event,
    Emitter<SettingsState> emit,
  ) async {
    emit(SettingsLoading());
    final result = await getRoleDetailsUseCase(event.id);

    result.fold(
      (failure) => emit(SettingsError(failure.message)),
      (roleDetail) => emit(RoleDetailsLoaded(roleDetail)),
    );
  }

  Future<void> _onCreateRole(
    CreateRole event,
    Emitter<SettingsState> emit,
  ) async {
    emit(SettingsLoading());
    final result = await createRoleUseCase(event.roleData);

    result.fold(
      (failure) => emit(SettingsError(failure.message)),
      (_) => emit(RoleCreated()),
    );
  }

  Future<void> _onUpdateRole(
    UpdateRole event,
    Emitter<SettingsState> emit,
  ) async {
    emit(SettingsLoading());
    final result = await updateRoleUseCase(event.id, event.roleData);

    result.fold(
      (failure) => emit(SettingsError(failure.message)),
      (_) => emit(RoleUpdated()),
    );
  }

  Future<void> _onReorderRolePriority(
    ReorderRolePriority event,
    Emitter<SettingsState> emit,
  ) async {
    final result = await reorderRolePriorityUseCase(event.roleId, event.newPriority);
    result.fold(
      (failure) => emit(SettingsError(failure.message)),
      (_) {
        add(FetchRolesDropdown());
      },
    );
  }
}
