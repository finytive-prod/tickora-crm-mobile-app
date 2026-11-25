import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/blocs/login_bloc.dart';
import 'package:crm_mobile/blocs/login_event.dart';
import 'package:crm_mobile/blocs/login_state.dart';
import 'package:crm_mobile/core/network/api_constants.dart';
import 'package:crm_mobile/core/services/oauth_service.dart';
import 'package:crm_mobile/core/services/secure_token_storage.dart';
import 'package:crm_mobile/models/oauth_token_response.dart';
import 'package:crm_mobile/models/user.dart';
import 'package:crm_mobile/repositories/login_repository.dart';
import 'package:crm_mobile/usecases/login_usecase.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class _FakeLoginRepository extends Fake implements LoginRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences sharedPreferences;
  late SecureTokenStorage secureTokenStorage;
  late OAuthService oauthService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    FlutterSecureStorage.setMockInitialValues({});
    secureTokenStorage = SecureTokenStorage(sharedPreferences: sharedPreferences);
    oauthService = OAuthService(
      tokenStorage: secureTokenStorage,
      sharedPreferences: sharedPreferences,
    );
  });

  group('OAuth 2.0 PKCE Cryptographic Tests', () {
    test('code_verifier generates between 43 and 128 characters using unreserved set', () {
      final verifier = oauthService.generateCodeVerifier();

      expect(verifier.length, greaterThanOrEqualTo(43));
      expect(verifier.length, lessThanOrEqualTo(128));
      expect(verifier.length, equals(64));

      // RFC 7636 unreserved characters: [A-Z], [a-z], [0-9], "-", ".", "_", "~"
      final unreservedPattern = RegExp(r'^[A-Za-z0-9\-\._~]+$');
      expect(unreservedPattern.hasMatch(verifier), isTrue);
    });

    test('code_challenge matches RFC 7636 Appendix B test vector', () {
      // Official RFC 7636 Appendix B test vector:
      const rfcVerifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      const expectedChallenge = 'E9Melhoa2OwvFrGMTJguCH5rtG6j30-WiUI2t82_PmQ';

      final challenge = oauthService.generateCodeChallenge(rfcVerifier);

      expect(challenge, equals(expectedChallenge));
      // Must not contain '=' padding
      expect(challenge.contains('='), isFalse);
    });

    test('generateState creates secure unpadded random state', () {
      final state1 = oauthService.generateState();
      final state2 = oauthService.generateState();

      expect(state1, isNotEmpty);
      expect(state2, isNotEmpty);
      expect(state1, isNot(equals(state2)));
      expect(state1.contains('='), isFalse);
    });

    test('buildAuthorizationUrl constructs valid OAuth URL with all required query parameters', () {
      const challenge = 'E9Melhoa2OwvFrGMTJguCH5rtG6j30-WiUI2t82_PmQ';
      const state = 'xyzState123';

      final uri = oauthService.buildAuthorizationUrl(
        codeChallenge: challenge,
        state: state,
        emailHint: 'test@example.com',
      );

      expect(uri.host, equals('qa.69-46-84-35.sslip.io'));
      expect(uri.path, equals('/login'));
      expect(uri.queryParameters['client_id'], equals('tickora-launcher-web'));
      expect(uri.queryParameters['redirect_uri'], equals('https://qa.69-46-84-35.sslip.io/callback'));
      expect(uri.queryParameters['response_type'], equals('code'));
      expect(uri.queryParameters['code_challenge'], equals(challenge));
      expect(uri.queryParameters['code_challenge_method'], equals('S256'));
      expect(uri.queryParameters['state'], equals(state));
      expect(uri.queryParameters['login_hint'], equals('test@example.com'));
    });
  });

  group('OAuthTokenResponse Model Parsing', () {
    test('parses camelCase response according to backend contract', () {
      final json = {
        'accessToken': 'test_access_token_123',
        'refreshToken': 'test_refresh_token_456',
        'tokenType': 'Bearer',
        'expiresIn': 3600,
      };

      final response = OAuthTokenResponse.fromJson(json);

      expect(response.accessToken, equals('test_access_token_123'));
      expect(response.refreshToken, equals('test_refresh_token_456'));
      expect(response.tokenType, equals('Bearer'));
      expect(response.expiresIn, equals(3600));
    });

    test('falls back gracefully to snake_case if returned', () {
      final json = {
        'access_token': 'snake_access',
        'refresh_token': 'snake_refresh',
        'token_type': 'Bearer',
        'expires_in': 7200,
      };

      final response = OAuthTokenResponse.fromJson(json);

      expect(response.accessToken, equals('snake_access'));
      expect(response.refreshToken, equals('snake_refresh'));
      expect(response.tokenType, equals('Bearer'));
      expect(response.expiresIn, equals(7200));
    });
  });

  group('SecureTokenStorage Tests', () {
    test('stores and retrieves access and refresh tokens', () async {
      await secureTokenStorage.saveTokens(
        accessToken: 'secure_access_token',
        refreshToken: 'secure_refresh_token',
        expiresIn: 3600,
      );

      final access = await secureTokenStorage.getAccessToken();
      final refresh = await secureTokenStorage.getRefreshToken();
      final isExpired = await secureTokenStorage.isTokenExpired();

      expect(access, equals('secure_access_token'));
      expect(refresh, equals('secure_refresh_token'));
      expect(isExpired, isFalse);
    });

    test('saves, reads, and clears pending PKCE values', () async {
      await secureTokenStorage.savePendingPkce(
        codeVerifier: 'verifier123',
        state: 'state123',
      );

      expect(await secureTokenStorage.getPendingVerifier(), equals('verifier123'));
      expect(await secureTokenStorage.getPendingState(), equals('state123'));

      await secureTokenStorage.clearPendingPkce();

      expect(await secureTokenStorage.getPendingVerifier(), isNull);
      expect(await secureTokenStorage.getPendingState(), isNull);
    });

    test('clears all tokens on logout', () async {
      await secureTokenStorage.saveTokens(
        accessToken: 'access_to_clear',
        refreshToken: 'refresh_to_clear',
        expiresIn: 3600,
      );

      await secureTokenStorage.clearTokens();

      expect(await secureTokenStorage.getAccessToken(), isNull);
      expect(await secureTokenStorage.getRefreshToken(), isNull);
      expect(await secureTokenStorage.hasValidSession(), isFalse);
      expect(sharedPreferences.getString('token'), isNull);
    });
  });

  group('LoginBloc OAuth 2.0 PKCE Flow', () {
    test('LoginButtonPressed triggers OAuth PKCE flow and emits loading', () async {
      final repo = _FakeLoginRepository();
      final bloc = LoginBloc(
        loginUseCase: LoginUseCase(repo),
        oauthService: oauthService,
      );

      final states = <LoginState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const LoginButtonPressed(email: 'user@example.com'));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(states.isNotEmpty, isTrue);
      expect(states.first, isA<LoginLoading>());

      await sub.cancel();
      await bloc.close();
    });

    test('LoginOAuthCallbackReceived emits LoginSuccess with authenticated user', () async {
      final repo = _FakeLoginRepository();
      final bloc = LoginBloc(
        loginUseCase: LoginUseCase(repo),
        oauthService: oauthService,
      );

      const user = User(
        accessToken: 'acc_token_abc',
        expiresIn: 3600,
        tokenType: 'Bearer',
        userId: 'user-001',
        userName: 'Test User',
        role: 'ADMIN',
        privileges: ['LEAD_VIEW', 'LEAD_CREATE'],
      );

      final states = <LoginState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const LoginOAuthCallbackReceived(user));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(states.any((s) => s is LoginSuccess), isTrue);
      final successState = states.firstWhere((s) => s is LoginSuccess) as LoginSuccess;
      expect(successState.user.userName, equals('Test User'));
      expect(successState.user.userId, equals('user-001'));

      await sub.cancel();
      await bloc.close();
    });

    test('LoginOAuthFailed emits LoginFailure with error message', () async {
      final repo = _FakeLoginRepository();
      final bloc = LoginBloc(
        loginUseCase: LoginUseCase(repo),
        oauthService: oauthService,
      );

      final states = <LoginState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const LoginOAuthFailed('User cancelled authentication in browser'));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(states.any((s) => s is LoginFailure), isTrue);
      final failureState = states.firstWhere((s) => s is LoginFailure) as LoginFailure;
      expect(failureState.message, contains('User cancelled'));

      await sub.cancel();
      await bloc.close();
    });
  });
}
