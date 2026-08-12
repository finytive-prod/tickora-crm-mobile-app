import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/network/api_client.dart';
import '../core/network/dio_client.dart';
import '../core/network/interceptors/auth_interceptor.dart';
import '../core/network/interceptors/error_interceptor.dart';
import '../core/network/interceptors/logger_interceptor.dart';
import '../features/auth/login/data/repositories/login_repository_impl.dart';
import '../features/auth/login/domain/repositories/login_repository.dart';
import '../features/auth/login/domain/usecases/login_usecase.dart';
import '../features/auth/login/presentation/bloc/login_bloc.dart';
import '../features/leads/domain/repositories/leads_repository.dart';
import '../features/leads/domain/usecases/get_leads_usecase.dart';
import '../features/leads/domain/usecases/get_lead_statuses_usecase.dart';
import '../features/leads/domain/usecases/get_lead_sources_usecase.dart';
import '../features/leads/domain/usecases/get_lead_priorities_usecase.dart';
import '../features/leads/domain/usecases/get_staff_users_usecase.dart';
import '../features/leads/domain/usecases/get_custom_fields_usecase.dart';
import '../features/leads/domain/usecases/create_lead_usecase.dart';
import '../features/leads/domain/usecases/get_followups_usecase.dart';
import '../features/leads/domain/usecases/get_lead_followups_usecase.dart';
import '../features/leads/domain/usecases/update_followup_usecase.dart';
import '../features/leads/domain/usecases/get_lead_details_usecase.dart';
import '../features/leads/domain/usecases/get_lead_audit_logs_usecase.dart';
import '../features/leads/domain/usecases/get_lead_attachments_usecase.dart';
import '../features/leads/domain/usecases/upload_lead_attachment_usecase.dart';
import '../features/leads/domain/usecases/get_custom_fields_list_usecase.dart';
import '../features/leads/domain/usecases/create_custom_fields_usecase.dart';
import '../features/leads/domain/usecases/get_custom_field_types_usecase.dart';
import '../features/leads/domain/usecases/update_custom_fields_usecase.dart';
import '../features/leads/domain/usecases/reorder_lead_status_usecase.dart';
import '../features/leads/domain/usecases/set_default_lead_status_usecase.dart';
import '../features/leads/domain/usecases/create_lead_status_usecase.dart';
import '../features/leads/data/repositories/leads_repository_impl.dart';
import '../features/leads/domain/repositories/followups_repository.dart';
import '../features/leads/data/repositories/followups_repository_impl.dart';
import '../features/leads/presentation/bloc/leads_bloc.dart';
import '../features/leads/presentation/bloc/followups_bloc.dart';
import '../features/leads/presentation/bloc/settings_bloc.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // Core
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerLazySingleton(() => sharedPreferences);
  sl.registerLazySingleton(() => Logger());

  // Interceptors
  sl.registerLazySingleton(
    () => AuthInterceptor(
      sl(),
      onSessionExpired: () {
 
      },
    ),
  );
  sl.registerLazySingleton(() => LoggerInterceptor(sl()));
  sl.registerLazySingleton(() => ErrorInterceptor());

  // Network
  sl.registerLazySingleton<ApiClient>(
    () => DioClient(
      authInterceptor: sl(),
      loggerInterceptor: sl(),
      errorInterceptor: sl(),
    ),
  );

  // Features - Login
  // BLoC
  sl.registerFactory(() => LoginBloc(loginUseCase: sl()));

  // Use Cases
  sl.registerLazySingleton(() => LoginUseCase(sl()));

  // Repository
  sl.registerLazySingleton<LoginRepository>(
    () => LoginRepositoryImpl(apiClient: sl(), sharedPreferences: sl()),
  );

  // Features - Leads
  // BLoC
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
    ),
  );

  sl.registerFactory(
    () => FollowUpsBloc(
      getFollowUpsUseCase: sl(),
      getLeadFollowUpsUseCase: sl(),
      updateFollowUpUseCase: sl(),
    ),
  );

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
    ),
  );

  // Use Cases
  sl.registerLazySingleton(() => GetLeadsUseCase(sl()));
  sl.registerLazySingleton(() => GetLeadStatusesUseCase(sl()));
  sl.registerLazySingleton(() => GetLeadSourcesUseCase(sl()));
  sl.registerLazySingleton(() => GetLeadPrioritiesUseCase(sl()));
  sl.registerLazySingleton(() => GetStaffUsersUseCase(sl()));
  sl.registerLazySingleton(() => GetCustomFieldsUseCase(sl()));
  sl.registerLazySingleton(() => CreateLeadUseCase(sl()));
  sl.registerLazySingleton(() => GetFollowUpsUseCase(sl()));
  sl.registerLazySingleton(() => GetLeadFollowUpsUseCase(sl()));
  sl.registerLazySingleton(() => UpdateFollowUpUseCase(sl()));
  sl.registerLazySingleton(() => GetLeadDetailsUseCase(sl()));
  sl.registerLazySingleton(() => GetLeadAuditLogsUseCase(sl()));
  sl.registerLazySingleton(() => GetLeadAttachmentsUseCase(sl()));
  sl.registerLazySingleton(() => UploadLeadAttachmentUseCase(sl()));
  sl.registerLazySingleton(() => GetCustomFieldsListUseCase(sl()));
  sl.registerLazySingleton(() => CreateCustomFieldsUseCase(sl()));
  sl.registerLazySingleton(() => GetCustomFieldTypesUseCase(sl()));
  sl.registerLazySingleton(() => UpdateCustomFieldsUseCase(sl()));
  sl.registerLazySingleton(() => ReorderLeadStatusUseCase(sl()));
  sl.registerLazySingleton(() => SetDefaultLeadStatusUseCase(sl()));
  sl.registerLazySingleton(() => CreateLeadStatusUseCase(sl()));

  // Repository
  sl.registerLazySingleton<LeadsRepository>(
    () => LeadsRepositoryImpl(apiClient: sl()),
  );

  sl.registerLazySingleton<FollowUpsRepository>(
    () => FollowUpsRepositoryImpl(apiClient: sl()),
  );
}
