import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/usecases/login_usecase.dart';
import 'package:crm_mobile/blocs/login_event.dart';
import 'package:crm_mobile/blocs/login_state.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
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
    emit(LoginLoading());

    final failureOrUser = await loginUseCase(event.email, event.password);

    await failureOrUser.fold(
      (failure) async => emit(LoginFailure(failure.message)),
      (user) async {
        await sl<PrivilegeService>().fetchPrivileges();
        emit(LoginSuccess(user));
      },
    );
  }
}
