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
import '../features/leads/data/repositories/leads_repository_impl.dart';
import '../features/leads/presentation/bloc/leads_bloc.dart';
final sl = GetIt.instance; // sl is short for service locator

Future<void> init() async {
  // Core
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerLazySingleton(() => sharedPreferences);
  sl.registerLazySingleton(() => Logger());

  // Interceptors
  sl.registerLazySingleton(
    () => AuthInterceptor(sl(), onSessionExpired: () {
      // Handle session expiration (e.g. redirect to login)
      // Since this requires a context, it is typically handled by setting up a GlobalKey<NavigatorState>
    }),
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
    () => LoginRepositoryImpl(
      apiClient: sl(),
      sharedPreferences: sl(),
    ),
  );

  // Features - Leads
  // BLoC
  sl.registerFactory(() => LeadsBloc(
        getLeadsUseCase: sl(),
        getLeadStatusesUseCase: sl(),
      ));

  // Use Cases
  sl.registerLazySingleton(() => GetLeadsUseCase(sl()));
  sl.registerLazySingleton(() => GetLeadStatusesUseCase(sl()));

  // Repository
  sl.registerLazySingleton<LeadsRepository>(
    () => LeadsRepositoryImpl(apiClient: sl()),
  );
}
