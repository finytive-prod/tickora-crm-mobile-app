import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/usecases/login_usecase.dart';
import 'package:crm_mobile/blocs/login_event.dart';
import 'package:crm_mobile/blocs/login_state.dart';
import 'package:crm_mobile/core/services/oauth_service.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/core/services/fcm_service.dart';
import 'package:crm_mobile/injection/injection.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  final LoginUseCase loginUseCase;
  final OAuthService? oauthService;
  StreamSubscription<OAuthCallbackResult>? _oauthSubscription;

  LoginBloc({
    required this.loginUseCase,
    this.oauthService,
  }) : super(LoginInitial()) {
    on<LoginButtonPressed>(_onLoginButtonPressed);
    on<LoginOAuthInitiated>(_onLoginOAuthInitiated);
    on<LoginOAuthCallbackReceived>(_onLoginOAuthCallbackReceived);
    on<LoginOAuthFailed>(_onLoginOAuthFailed);
    on<LoginOAuthCancelled>(_onLoginOAuthCancelled);

    _listenToOAuthCallbacks();
  }

  void _listenToOAuthCallbacks() {
    final service = oauthService ?? (sl.isRegistered<OAuthService>() ? sl<OAuthService>() : null);
    if (service != null) {
      _oauthSubscription = service.callbackStream.listen((result) {
        if (result.isSuccess && result.user != null) {
          add(LoginOAuthCallbackReceived(result.user!));
        } else {
          add(LoginOAuthFailed(result.errorMessage ?? 'Authentication failed'));
        }
      });
    }
  }

  /// Initiates OAuth 2.0 PKCE flow in the in-app browser view.
  Future<void> _onLoginOAuthInitiated(
    LoginOAuthInitiated event,
    Emitter<LoginState> emit,
  ) async {
    emit(const LoginLoading(message: 'Opening secure login...'));

    try {
      final service = oauthService ?? sl<OAuthService>();
      final launched = await service.startAuthorizationFlow(
        emailHint: event.emailHint,
      );

      if (!launched) {
        emit(const LoginFailure(
          'Could not open in-app login. Please try again.',
        ));
      }
    } catch (e) {
      debugPrint('OAuth: Error starting authorization flow: $e');
      emit(LoginFailure(e.toString().replaceAll('Exception: ', '')));
    }
  }

  /// When the user taps the existing Sign In button on LoginScreen,
  /// initiate the OAuth 2.0 PKCE flow in the browser.
  Future<void> _onLoginButtonPressed(
    LoginButtonPressed event,
    Emitter<LoginState> emit,
  ) async {
    final email = event.email.trim();
    // Start OAuth flow directly (passing email as hint if present)
    add(LoginOAuthInitiated(emailHint: email.isNotEmpty ? email : null));
  }

  /// Handles successful token exchange & profile retrieval from deep link callback.
  Future<void> _onLoginOAuthCallbackReceived(
    LoginOAuthCallbackReceived event,
    Emitter<LoginState> emit,
  ) async {
    emit(const LoginLoading(message: 'Completing authentication...'));

    final user = event.user;

    // Fetch privileges with a safety timeout
    try {
      if (sl.isRegistered<PrivilegeService>()) {
        await sl<PrivilegeService>().fetchPrivileges().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('Privilege fetch timed out');
          },
        );
      }
    } catch (e) {
      debugPrint('Error fetching privileges on login: $e');
    }

    // Initialize FCM with a safety timeout
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
  }

  void _onLoginOAuthFailed(
    LoginOAuthFailed event,
    Emitter<LoginState> emit,
  ) {
    emit(LoginFailure(event.message));
  }

  void _onLoginOAuthCancelled(
    LoginOAuthCancelled event,
    Emitter<LoginState> emit,
  ) {
    try {
      final service = oauthService ?? (sl.isRegistered<OAuthService>() ? sl<OAuthService>() : null);
      service?.closeInAppLogin();
    } catch (_) {}
    emit(LoginInitial());
  }

  @override
  Future<void> close() {
    _oauthSubscription?.cancel();
    return super.close();
  }
}
