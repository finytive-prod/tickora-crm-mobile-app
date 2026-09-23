import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/dio_client.dart';
import 'package:crm_mobile/core/network/interceptors/auth_interceptor.dart';
import 'package:crm_mobile/core/network/interceptors/error_interceptor.dart';
import 'package:crm_mobile/core/network/interceptors/logger_interceptor.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/core/services/fcm_service.dart';
import 'package:crm_mobile/core/services/app_update_service.dart';
import 'package:crm_mobile/core/utils/navigation_service.dart';

// BLoC Imports
import 'package:crm_mobile/blocs/login_bloc.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/blocs/followups_bloc.dart';
import 'package:crm_mobile/blocs/settings_bloc.dart';
import 'package:crm_mobile/blocs/staff_bloc.dart';
import 'package:crm_mobile/blocs/calendar_bloc.dart';

// Repository Imports
import 'package:crm_mobile/repositories/login_repository.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';
import 'package:crm_mobile/repositories/followups_repository.dart';
import 'package:crm_mobile/repositories/customer_repository.dart';
import 'package:crm_mobile/repositories/dashboard_repository.dart';
import 'package:crm_mobile/usecases/customer_usecases.dart';
import 'package:crm_mobile/blocs/customer_bloc.dart';
import 'package:crm_mobile/blocs/dashboard_bloc.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';
import 'package:crm_mobile/repositories/calendar_repository.dart';

// Usecase Imports
import 'package:crm_mobile/usecases/login_usecase.dart';
import 'package:crm_mobile/usecases/get_calendar_categories_usecase.dart';
import 'package:crm_mobile/usecases/create_calendar_event_usecase.dart';
import 'package:crm_mobile/usecases/update_calendar_event_usecase.dart';
import 'package:crm_mobile/usecases/get_calendar_events_usecase.dart';
import 'package:crm_mobile/usecases/delete_calendar_event_usecase.dart';
import 'package:crm_mobile/usecases/reorder_role_priority_usecase.dart';

import 'package:crm_mobile/usecases/get_leads_usecase.dart';
import 'package:crm_mobile/usecases/search_leads_usecase.dart';
import 'package:crm_mobile/usecases/get_staff_users_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_priorities_usecase.dart';
import 'package:crm_mobile/usecases/create_lead_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_details_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_audit_logs_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_attachments_usecase.dart';
import 'package:crm_mobile/usecases/upload_lead_attachment_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_audios_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_call_logs_usecase.dart';
import 'package:crm_mobile/usecases/upload_lead_audio_usecase.dart';
import 'package:crm_mobile/usecases/update_lead_active_status_usecase.dart';
import 'package:crm_mobile/usecases/update_lead_usecase.dart';
import 'package:crm_mobile/usecases/quick_invite_lead_usecase.dart';

import 'package:crm_mobile/usecases/get_followups_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_followups_usecase.dart';
import 'package:crm_mobile/usecases/update_followup_usecase.dart';
import 'package:crm_mobile/usecases/add_followup_usecase.dart';

import 'package:crm_mobile/usecases/get_custom_fields_usecase.dart';
import 'package:crm_mobile/usecases/get_custom_fields_list_usecase.dart';
import 'package:crm_mobile/usecases/create_custom_fields_usecase.dart';
import 'package:crm_mobile/usecases/get_custom_field_types_usecase.dart';
import 'package:crm_mobile/usecases/update_custom_fields_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_statuses_usecase.dart';
import 'package:crm_mobile/usecases/reorder_lead_status_usecase.dart';
import 'package:crm_mobile/usecases/set_default_lead_status_usecase.dart';
import 'package:crm_mobile/usecases/create_lead_status_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_sources_usecase.dart';
import 'package:crm_mobile/usecases/create_lead_source_usecase.dart';
import 'package:crm_mobile/usecases/delete_lead_source_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_source_categories_usecase.dart';
import 'package:crm_mobile/usecases/get_permission_modules_usecase.dart';
import 'package:crm_mobile/usecases/get_roles_dropdown_usecase.dart';
import 'package:crm_mobile/usecases/get_role_details_usecase.dart';
import 'package:crm_mobile/usecases/create_role_usecase.dart';
import 'package:crm_mobile/usecases/update_role_usecase.dart';
import 'package:crm_mobile/usecases/get_staff_members_usecase.dart';
import 'package:crm_mobile/usecases/get_staff_stats_usecase.dart';
import 'package:crm_mobile/usecases/update_staff_member_usecase.dart';
import 'package:crm_mobile/usecases/toggle_staff_status_usecase.dart';
import 'package:crm_mobile/usecases/create_staff_member_usecase.dart';
import 'package:crm_mobile/usecases/get_staff_member_by_id_usecase.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // Core & External Services
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerLazySingleton(() => sharedPreferences);
  sl.registerLazySingleton(() => Logger());

  // Interceptors
  sl.registerLazySingleton(() => AuthInterceptor(sl(), onSessionExpired: NavigationService.handleSessionExpired));
  sl.registerLazySingleton(() => LoggerInterceptor(sl()));
  sl.registerLazySingleton(() => ErrorInterceptor());

  // Network Client
  sl.registerLazySingleton<ApiClient>(
    () => DioClient(
      authInterceptor: sl(),
      loggerInterceptor: sl(),
      errorInterceptor: sl(),
    ),
  );

  // Core App Services
  sl.registerLazySingleton(() => PrivilegeService(apiClient: sl(), logger: sl()));
  sl.registerLazySingleton(() => FcmService.instance);
  sl.registerLazySingleton(() => AppUpdateService());

  // Auth BLoC, Usecases & Repositories
  sl.registerFactory(() => LoginBloc(loginUseCase: sl()));
  sl.registerLazySingleton(() => LoginUseCase(sl()));
  sl.registerLazySingleton<LoginRepository>(
    () => LoginRepositoryImpl(apiClient: sl(), sharedPreferences: sl()),
  );

  // Leads BLoC, Usecases & Repositories
  sl.registerFactory(
    () => LeadsBloc(
      getLeadsUseCase: sl(),
      getLeadStatusesUseCase: sl(),
      getLeadSourcesUseCase: sl(),
      getLeadPrioritiesUseCase: sl(),
      getStaffUsersUseCase: sl(),
      getCustomFieldsUseCase: sl(),
      createLeadUseCase: sl(),
      getLeadDetailsUseCase: sl(),
      getLeadAuditLogsUseCase: sl(),
      getLeadAttachmentsUseCase: sl(),
      uploadLeadAttachmentUseCase: sl(),
      getLeadAudiosUseCase: sl(),
      getLeadCallLogsUseCase: sl(),
      uploadLeadAudioUseCase: sl(),
      updateLeadUseCase: sl(),
      updateLeadActiveStatusUseCase: sl(),
      searchLeadsUseCase: sl(),
      quickInviteLeadUseCase: sl(),
    ),
  );

  sl.registerLazySingleton(() => GetLeadsUseCase(sl()));
  sl.registerLazySingleton(() => SearchLeadsUseCase(sl()));
  sl.registerLazySingleton(() => GetLeadPrioritiesUseCase(sl()));
  sl.registerLazySingleton(() => GetStaffUsersUseCase(sl()));
  sl.registerLazySingleton(() => CreateLeadUseCase(sl()));
  sl.registerLazySingleton(() => QuickInviteLeadUseCase(sl()));
  sl.registerLazySingleton(() => GetLeadDetailsUseCase(sl()));
  sl.registerLazySingleton(() => GetLeadAuditLogsUseCase(sl()));
  sl.registerLazySingleton(() => GetLeadAttachmentsUseCase(sl()));
  sl.registerLazySingleton(() => UploadLeadAttachmentUseCase(sl()));
  sl.registerLazySingleton(() => GetLeadAudiosUseCase(sl()));
  sl.registerLazySingleton(() => GetLeadCallLogsUseCase(sl()));
  sl.registerLazySingleton(() => UploadLeadAudioUseCase(sl()));
  sl.registerLazySingleton(() => UpdateLeadUseCase(sl()));
  sl.registerLazySingleton(() => UpdateLeadActiveStatusUseCase(sl()));

  sl.registerLazySingleton<LeadsRepository>(
    () => LeadsRepositoryImpl(apiClient: sl()),
  );

  // Follow-ups BLoC, Usecases & Repositories
  sl.registerFactory(() => FollowUpsBloc(
        getFollowUpsUseCase: sl(),
        getLeadFollowUpsUseCase: sl(),
        updateFollowUpUseCase: sl(),
        addFollowUpUseCase: sl(),
      ));

  sl.registerFactory(() => CustomerBloc(
        getCustomersUseCase: sl(),
        getCustomerTypesUseCase: sl(),
        createCustomerUseCase: sl(),
        updateCustomerUseCase: sl(),
        deleteCustomerUseCase: sl(),
      ));

  sl.registerLazySingleton(() => GetFollowUpsUseCase(sl()));
  sl.registerLazySingleton(() => GetLeadFollowUpsUseCase(sl()));
  sl.registerLazySingleton(() => UpdateFollowUpUseCase(sl()));
  sl.registerLazySingleton(() => AddFollowUpUseCase(sl()));

  // Follow-ups Repository
  sl.registerLazySingleton<FollowUpsRepository>(
    () => FollowUpsRepositoryImpl(apiClient: sl()),
  );

  // Customer Repository
  sl.registerLazySingleton<CustomerRepository>(
    () => CustomerRepositoryImpl(apiClient: sl()),
  );

  // Customer UseCases
  sl.registerLazySingleton(() => GetCustomersUseCase(sl()));
  sl.registerLazySingleton(() => GetCustomerTypesUseCase(sl()));
  sl.registerLazySingleton(() => CreateCustomerUseCase(sl()));
  sl.registerLazySingleton(() => UpdateCustomerUseCase(sl()));
  sl.registerLazySingleton(() => DeleteCustomerUseCase(sl()));

  // Dashboard BLoC & Repository
  sl.registerFactory(() => DashboardBloc(
        repository: sl(),
      ));
  sl.registerLazySingleton<DashboardRepository>(
    () => DashboardRepositoryImpl(apiClient: sl()),
  );

  // Settings BLoC, Usecases & Repositories
  sl.registerFactory(
    () => SettingsBloc(
      getCustomFieldsListUseCase: sl(),
      createCustomFieldsUseCase: sl(),
      getCustomFieldTypesUseCase: sl(),
      getLeadStatusesUseCase: sl(),
      getLeadSourcesUseCase: sl(),
      updateCustomFieldsUseCase: sl(),
      reorderLeadStatusUseCase: sl(),
      setDefaultLeadStatusUseCase: sl(),
      createLeadStatusUseCase: sl(),
      createLeadSourceUseCase: sl(),
      deleteLeadSourceUseCase: sl(),
      getLeadSourceCategoriesUseCase: sl(),
      getPermissionModulesUseCase: sl(),
      getRolesDropdownUseCase: sl(),
      getRoleDetailsUseCase: sl(),
      createRoleUseCase: sl(),
      updateRoleUseCase: sl(),
      reorderRolePriorityUseCase: sl(),
    ),
  );

  sl.registerLazySingleton(() => GetCustomFieldsUseCase(sl()));
  sl.registerLazySingleton(() => GetCustomFieldsListUseCase(sl()));
  sl.registerLazySingleton(() => CreateCustomFieldsUseCase(sl()));
  sl.registerLazySingleton(() => GetCustomFieldTypesUseCase(sl()));
  sl.registerLazySingleton(() => UpdateCustomFieldsUseCase(sl()));
  sl.registerLazySingleton(() => GetLeadStatusesUseCase(sl()));
  sl.registerLazySingleton(() => ReorderLeadStatusUseCase(sl()));
  sl.registerLazySingleton(() => SetDefaultLeadStatusUseCase(sl()));
  sl.registerLazySingleton(() => CreateLeadStatusUseCase(sl()));
  sl.registerLazySingleton(() => GetLeadSourcesUseCase(sl()));
  sl.registerLazySingleton(() => CreateLeadSourceUseCase(sl()));
  sl.registerLazySingleton(() => DeleteLeadSourceUseCase(sl()));
  sl.registerLazySingleton(() => GetLeadSourceCategoriesUseCase(sl()));
  sl.registerLazySingleton(() => GetPermissionModulesUseCase(sl()));
  sl.registerLazySingleton(() => GetRolesDropdownUseCase(sl()));
  sl.registerLazySingleton(() => GetRoleDetailsUseCase(sl()));
  sl.registerLazySingleton(() => CreateRoleUseCase(sl()));
  sl.registerLazySingleton(() => UpdateRoleUseCase(sl()));
  sl.registerLazySingleton(() => ReorderRolePriorityUseCase(sl()));

  sl.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(apiClient: sl()),
  );

  // Staff BLoC & Usecases
  sl.registerFactory(
    () => StaffBloc(
      getStaffMembersUseCase: sl(),
      getStaffStatsUseCase: sl(),
      updateStaffMemberUseCase: sl(),
      toggleStaffStatusUseCase: sl(),
      createStaffMemberUseCase: sl(),
      getStaffMemberByIdUseCase: sl(),
    ),
  );

  sl.registerLazySingleton(() => GetStaffMembersUseCase(sl()));
  sl.registerLazySingleton(() => GetStaffStatsUseCase(sl()));
  sl.registerLazySingleton(() => UpdateStaffMemberUseCase(sl()));
  sl.registerLazySingleton(() => ToggleStaffStatusUseCase(sl()));
  sl.registerLazySingleton(() => CreateStaffMemberUseCase(sl()));
  sl.registerLazySingleton(() => GetStaffMemberByIdUseCase(sl()));

  // Calendar BLoC, Usecases & Repositories
  sl.registerFactory(
    () => CalendarBloc(
      getCalendarCategoriesUseCase: sl(),
      createCalendarEventUseCase: sl(),
      updateCalendarEventUseCase: sl(),
      getCalendarEventsUseCase: sl(),
      deleteCalendarEventUseCase: sl(),
    ),
  );

  sl.registerLazySingleton(() => GetCalendarCategoriesUseCase(sl()));
  sl.registerLazySingleton(() => CreateCalendarEventUseCase(sl()));
  sl.registerLazySingleton(() => UpdateCalendarEventUseCase(sl()));
  sl.registerLazySingleton(() => GetCalendarEventsUseCase(sl()));
  sl.registerLazySingleton(() => DeleteCalendarEventUseCase(sl()));

  sl.registerLazySingleton<CalendarRepository>(
    () => CalendarRepositoryImpl(apiClient: sl()),
  );
}
