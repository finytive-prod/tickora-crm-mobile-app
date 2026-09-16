import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/usecases/login_usecase.dart';
import 'package:crm_mobile/blocs/login_event.dart';
import 'package:crm_mobile/blocs/login_state.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/core/services/fcm_service.dart';
import 'package:crm_mobile/injection/injection.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  final LoginUseCase loginUseCase;

  LoginBloc({required this.loginUseCase}) : super(LoginInitial()) {
    on<LoginButtonPressed>(_onLoginButtonPressed);
  }

  Future<void> _onLoginButtonPressed(
    LoginButtonPressed event,
    Emitter<LoginState> emit,
  ) async {
    final email = event.email.trim();
    final password = event.password.trim();

    if (email.isEmpty) {
      emit(const LoginFailure('Please enter your email address'));
      return;
    }
    if (password.isEmpty) {
      emit(const LoginFailure('Please enter your password'));
      return;
    }

    emit(LoginLoading());

    try {
      final failureOrUser = await loginUseCase(email, password);

      await failureOrUser.fold(
        (failure) async {
          emit(LoginFailure(failure.message));
        },
        (user) async {
          // Fetch privileges with a 5-second safety timeout
          try {
            await sl<PrivilegeService>().fetchPrivileges().timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                debugPrint('Privilege fetch timed out');
              },
            );
          } catch (e) {
            debugPrint('Error fetching privileges on login: $e');
          }

          // Initialize FCM with a 5-second safety timeout
          try {
            await FcmService.instance.initialize().timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                debugPrint('FCM init timed out');
              },
            );
          } catch (e) {
            debugPrint('Error initializing FCM on login: $e');
          }

          emit(LoginSuccess(user));
        },
      );
    } catch (e) {
      debugPrint('Unhandled error during login: $e');
      emit(LoginFailure(e.toString().replaceAll('Exception: ', '')));
    }
  }
}

