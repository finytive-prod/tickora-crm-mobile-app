import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:crm_mobile/core/network/api_constants.dart';
import 'package:crm_mobile/core/network/api_exception.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/core/services/secure_token_storage.dart';
import 'package:crm_mobile/core/utils/navigation_service.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/models/oauth_token_response.dart';
import 'package:crm_mobile/models/user.dart';

class OAuthService {
  final SecureTokenStorage _tokenStorage;
  final SharedPreferences _sharedPreferences;
  final Dio _dio;
  final AppLinks _appLinks;

  StreamSubscription<Uri>? _linkSubscription;
  Completer<String?>? _inFlightRefresh;
  final Set<String> _processedCodes = {};
  bool _isExchangingCode = false;
  bool _authorizationFlowActive = false;
  Completer<void>? _preparation;
  Completer<void>? _closing;
  int _authorizationGeneration = 0;
  int _sessionGeneration = 0;
  int? _callbackClaimedGeneration;
  Future<void> _callbackQueue = Future<void>.value();

  final StreamController<OAuthCallbackResult> _callbackStreamController =
      StreamController<OAuthCallbackResult>.broadcast();

  Stream<OAuthCallbackResult> get callbackStream => _callbackStreamController.stream;

  OAuthService({
    required SecureTokenStorage tokenStorage,
    required SharedPreferences sharedPreferences,
    Dio? dio,
    AppLinks? appLinks,
  })  : _tokenStorage = tokenStorage,
        _sharedPreferences = sharedPreferences,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(milliseconds: ApiConstants.connectTimeout),
                receiveTimeout: const Duration(milliseconds: ApiConstants.receiveTimeout),
                sendTimeout: const Duration(milliseconds: ApiConstants.sendTimeout),
              ),
            ),
        _appLinks = appLinks ?? AppLinks() {
    _initializeDeepLinkListener();
  }

  void _initializeDeepLinkListener() {
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        handleAuthorizationCallback(uri);
      },
      onError: (err) {
        debugPrint('OAuth: AppLinks error: $err');
      },
    );

    _appLinks.getInitialLink().then((initialUri) {
      if (initialUri != null) {
        handleAuthorizationCallback(initialUri);
      }
    }).catchError((err) {
      debugPrint('OAuth: getInitialLink error: $err');
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // COMPLETE IN-APP PLATFORM OAUTH2 + PKCE FLOW (CUSTOM JSON MODE)
  // ──────────────────────────────────────────────────────────────────────────

  /// Executes the complete 9-step in-app Platform OAuth2 + PKCE authentication sequence:
  /// 1. Generate PKCE code_verifier & code_challenge (S256)
  /// 2. POST /api/v1/auth/login -> receive sessionId
  /// 3. GET /oauth2/authorize (without response_type=code) -> receive authorization code via JSON
  /// 4. POST /oauth2/token (form-encoded) -> exchange code & verifier for accessToken + refreshToken
  /// 5. Store tokens securely
  /// 6. GET /api/v1/platform/me -> validate Platform user
  /// 7. GET /api/v1/platform/products/access -> verify CRM is launchable (abort if denied)
  /// 8. GET /api/crm/identity-service/platform/session -> initialize CRM user, role & permissions
  /// 9. Return populated User for dashboard navigation
  Future<User> loginWithPlatformOAuth({
    required String email,
    required String password,
    String? organizationId,
  }) async {
    // ── STEP 1: Generate PKCE values ──
    final codeVerifier = generateCodeVerifier();
    final codeChallenge = generateCodeChallenge(codeVerifier);

    // ── STEP 2: Platform login API (POST /api/v1/auth/login) ──
    final loginPayload = <String, dynamic>{
      'email': email.trim(),
      'password': password,
    };
    if (organizationId != null && organizationId.trim().isNotEmpty) {
      loginPayload['organizationId'] = organizationId.trim();
    }

    Response loginResponse;
    try {
      loginResponse = await _dio.post(
        ApiUrl.platformLoginUrl,
        data: loginPayload,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );
    } on DioException catch (e) {
      final res = e.response;
      final msg = res?.data is Map
          ? (res!.data['message'] ?? res.data['error'] ?? res.data['description'])
          : e.message;
      final strMsg = msg?.toString() ?? '';

      if (strMsg.contains('ORGANIZATION_SELECTION_REQUIRED') ||
          res?.data?['error'] == 'ORGANIZATION_SELECTION_REQUIRED') {
        throw ApiException(
          message:
              'Organization selection required. Multiple active organizations found; organization selection requires backend support.',
        );
      }
      if (res?.statusCode == 401 ||
          strMsg.toLowerCase().contains('invalid') ||
          strMsg.toLowerCase().contains('credential') ||
          strMsg.toLowerCase().contains('bad credentials')) {
        throw ApiException(message: 'Invalid email or password');
      }
      throw ApiException(
        message: strMsg.isNotEmpty ? strMsg : 'Platform login failed (HTTP ${res?.statusCode})',
      );
    }

    final loginData = loginResponse.data is Map ? loginResponse.data as Map : {};
    final sessionId = (loginData['sessionId'] ?? loginData['data']?['sessionId'] ?? '').toString();

    if (sessionId.isEmpty) {
      if (loginData['error'] == 'ORGANIZATION_SELECTION_REQUIRED' ||
          loginData['message']?.toString().contains('ORGANIZATION_SELECTION_REQUIRED') == true) {
        throw ApiException(
          message:
              'Organization selection required. Multiple active organizations found; organization selection requires backend support.',
        );
      }
      throw ApiException(
        message: loginData['message']?.toString() ?? 'Login session creation failed: missing sessionId',
      );
    }

    // ── STEP 3: OAuth authorization API (GET /oauth2/authorize - WITHOUT response_type=code) ──
    Response authResponse;
    try {
      authResponse = await _dio.get(
        ApiUrl.oauthAuthorizeUrl,
        queryParameters: {
          'sessionId': sessionId,
          'client_id': ApiUrl.oauthClientId,
          'redirect_uri': ApiUrl.mobileRedirectUri,
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
          // CRITICAL: DO NOT INCLUDE response_type=code (enables custom JSON mode)
        },
        options: Options(
          headers: {
            'Accept': 'application/json',
          },
        ),
      );
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message'] ?? e.response!.data['error'])
          : e.message;
      throw ApiException(
        message: 'Authorization failed: ${msg ?? e.response?.statusCode}',
      );
    }

    final authBody = authResponse.data is Map ? authResponse.data as Map : {};
    final code = (authBody['code'] ?? authBody['data']?['code'] ?? '').toString();
    final redirectUri = (authBody['redirectUri'] ?? authBody['data']?['redirectUri'] ?? '').toString();

    if (code.isEmpty) {
      throw ApiException(
        message: authBody['message']?.toString() ?? 'Authorization failed: no code received from platform',
      );
    }

    final cleanRedirectUri = ApiUrl.mobileRedirectUri.trim();
    if (redirectUri.isNotEmpty &&
        !redirectUri.startsWith(cleanRedirectUri) &&
        !cleanRedirectUri.startsWith(redirectUri)) {
      throw ApiException(message: 'Authorization redirect URI mismatch');
    }

    // ── STEP 4: Exchange authorization code for tokens (POST /oauth2/token form-urlencoded) ──
    Response tokenResponse;
    try {
      tokenResponse = await _dio.post(
        ApiUrl.oauthTokenUrl,
        data: {
          'grant_type': 'authorization_code',
          'client_id': ApiUrl.oauthClientId,
          'code': code,
          'redirect_uri': cleanRedirectUri,
          'code_verifier': codeVerifier,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'Accept': 'application/json',
          },
        ),
      );
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['error_description'] ??
              e.response!.data['error'] ??
              e.response!.data['message'])
          : e.message;
      throw ApiException(
        message: 'Token exchange failed: ${msg ?? e.response?.statusCode}',
      );
    }

    final tokenBody = tokenResponse.data is Map
        ? Map<String, dynamic>.from(tokenResponse.data as Map)
        : <String, dynamic>{};
    final parsedTokens = OAuthTokenResponse.fromJson(tokenBody);

    if (parsedTokens.accessToken.isEmpty) {
      throw ApiException(
        message: tokenBody['error_description']?.toString() ?? 'Token response contained empty access token',
      );
    }

    // ── STEP 5: Secure token storage ──
    await _tokenStorage.saveTokens(
      accessToken: parsedTokens.accessToken,
      refreshToken: parsedTokens.refreshToken,
      expiresIn: parsedTokens.expiresIn,
      tokenType: parsedTokens.tokenType,
    );

    // ── STEP 6: Get Platform user information (GET /api/v1/platform/me) ──
    User platformUser;
    try {
      platformUser = await fetchCurrentUser(
        parsedTokens.accessToken,
        tokenResponse: parsedTokens,
      );
    } catch (e) {
      debugPrint('OAuth: fetchCurrentUser non-fatal error: $e');
      platformUser = UserModel(
        accessToken: parsedTokens.accessToken,
        expiresIn: parsedTokens.expiresIn,
        tokenType: parsedTokens.tokenType,
        userId: '',
        userName: 'Tickora User',
        role: 'user',
        privileges: const [],
      );
    }

    // ── STEP 7: Check Platform product access (GET /api/v1/platform/products/access) ──
    try {
      final isCrmLaunchable = await verifyCrmProductAccess(parsedTokens.accessToken);
      if (!isCrmLaunchable) {
        debugPrint('OAuth: CRM product access check returned false, proceeding with session');
      }
    } catch (e) {
      debugPrint('OAuth: verifyCrmProductAccess non-fatal error: $e');
    }

    // ── STEP 8: Initialize CRM identity (GET /api/crm/identity-service/platform/session) ──
    User crmUser;
    try {
      crmUser = await initializeCrmSession(
        parsedTokens.accessToken,
        fallbackUser: platformUser,
      );
    } catch (e) {
      debugPrint('OAuth: initializeCrmSession non-fatal fallback: $e');
      crmUser = platformUser;
    }

    // ── STEP 9: Return authenticated CRM user for dashboard navigation ──
    return crmUser;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 7: Product Access Verification
  // ──────────────────────────────────────────────────────────────────────────

  /// Checks GET /api/v1/platform/products/access to verify that CRM is enabled, assigned, and launchable.
  Future<bool> verifyCrmProductAccess(String accessToken) async {
    try {
      final response = await _dio.get(
        ApiUrl.platformProductsAccessUrl,
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Accept': 'application/json',
          },
        ),
      );

      final body = response.data;
      if (body == null) return false;

      dynamic content = body;
      if (body is Map && body['data'] != null) {
        content = body['data'];
      }

      if (content is List) {
        for (final item in content) {
          if (item is Map) {
            final code = (item['productCode'] ??
                    item['code'] ??
                    item['name'] ??
                    item['productName'] ??
                    item['id'] ??
                    '')
                .toString()
                .toUpperCase();
            if (code.contains('CRM')) {
              if (item['isLaunchable'] == false || item['launchable'] == false) {
                return false;
              }
              if (item['status'] != null) {
                final status = item['status'].toString().toUpperCase();
                if (status == 'INACTIVE' || status == 'DISABLED' || status == 'SUSPENDED') {
                  return false;
                }
              }
              if (item['enabled'] == false || item['assigned'] == false) {
                return false;
              }
              return true;
            }
          } else if (item is String) {
            if (item.toUpperCase().contains('CRM')) {
              return true;
            }
          }
        }
      } else if (content is Map) {
        for (final entry in content.entries) {
          final key = entry.key.toString().toUpperCase();
          if (key.contains('CRM')) {
            final val = entry.value;
            if (val is bool) return val;
            if (val is Map) {
              if (val['isLaunchable'] == false || val['launchable'] == false || val['enabled'] == false) {
                return false;
              }
              return true;
            }
            if (val is String) {
              return val.toUpperCase() == 'ACTIVE' || val.toUpperCase() == 'ENABLED';
            }
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('OAuth: verifyCrmProductAccess error: $e');
      throw ApiException(
        message: 'Failed to verify CRM product access: ${e is DioException ? (e.response?.data?['message'] ?? e.message) : e.toString()}',
      );
    }
    return false;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 8: CRM Identity Initialization
  // ──────────────────────────────────────────────────────────────────────────

  /// Initializes CRM identity from GET /api/crm/identity-service/platform/session.
  Future<User> initializeCrmSession(
    String accessToken, {
    required User fallbackUser,
  }) async {
    try {
      final response = await _dio.get(
        ApiUrl.crmPlatformSessionUrl,
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Accept': 'application/json',
          },
        ),
      );

      final body = response.data;
      Map<String, dynamic> crmData = {};
      if (body != null && body is Map) {
        if (body['data'] != null && body['data'] is Map) {
          crmData = Map<String, dynamic>.from(body['data']);
        } else {
          crmData = Map<String, dynamic>.from(body);
        }
      }

      final userId = (crmData['userId'] ?? crmData['id'] ?? fallbackUser.userId).toString();
      final userName = (crmData['userName'] ??
              crmData['fullName'] ??
              crmData['name'] ??
              fallbackUser.userName)
          .toString();
      final userEmail = (crmData['email'] ??
              crmData['userEmail'] ??
              _sharedPreferences.getString('userEmail') ??
              '')
          .toString();
      final userPhone = (crmData['phone'] ??
              crmData['mobile'] ??
              crmData['phoneNumber'] ??
              crmData['contactNumber'] ??
              '')
          .toString();

      String userRole = '';
      if (crmData['roles'] is List) {
        userRole = (crmData['roles'] as List).join(', ');
      } else if (crmData['role'] != null) {
        userRole = crmData['role'].toString();
      } else if (crmData['roleName'] != null) {
        userRole = crmData['roleName'].toString();
      } else {
        userRole = fallbackUser.role;
      }

      final orgId = (crmData['organizationId'] ??
              crmData['orgId'] ??
              _sharedPreferences.getString('organizationId') ??
              '')
          .toString();

      // Extract CRM permissions
      final List<String> permissions = PrivilegeService.parsePrivilegeList(crmData);
      if (permissions.isEmpty && fallbackUser.privileges.isNotEmpty) {
        permissions.addAll(fallbackUser.privileges);
      }

      // Persist non-sensitive metadata for existing CRM UI modules and call listeners
      if (userId.isNotEmpty) await _sharedPreferences.setString('userId', userId);
      if (userName.isNotEmpty) await _sharedPreferences.setString('userName', userName);
      if (userEmail.isNotEmpty) await _sharedPreferences.setString('userEmail', userEmail);
      if (userRole.isNotEmpty) await _sharedPreferences.setString('userRole', userRole);
      if (userPhone.isNotEmpty) await _sharedPreferences.setString('userPhone', userPhone);
      if (orgId.isNotEmpty) await _sharedPreferences.setString('organizationId', orgId);

      if (permissions.isNotEmpty && sl.isRegistered<PrivilegeService>()) {
        sl<PrivilegeService>().setPrivileges(permissions, replace: true);
      }

      return UserModel(
        accessToken: accessToken,
        expiresIn: fallbackUser.expiresIn,
        tokenType: fallbackUser.tokenType,
        userId: userId,
        userName: userName,
        role: userRole,
        privileges: permissions,
      );
    } catch (e) {
      debugPrint('OAuth: initializeCrmSession error: $e');
      throw ApiException(
        message: 'Failed to initialize CRM identity session: ${e is DioException ? (e.response?.data?['message'] ?? e.message) : e.toString()}',
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Application Startup Session Restoration
  // ──────────────────────────────────────────────────────────────────────────

  /// Restores session on application startup:
  /// 1. Reads token from secure storage.
  /// 2. Refreshes if expired.
  /// 3. Validates Platform user, verifies CRM product access, and initializes CRM identity.
  /// Returns true if the session is fully validated and launchable.
  Future<bool> restoreSession() async {
    try {
      String? token = await _tokenStorage.getAccessToken();
      if (token == null || token.isEmpty) {
        return false;
      }

      final isExpired = await _tokenStorage.isTokenExpired();
      if (isExpired) {
        token = await refreshToken();
        if (token == null || token.isEmpty) {
          return false;
        }
      }

      // Validate Platform session
      final platformUser = await fetchCurrentUser(token);

      // Verify CRM product access
      final isCrmLaunchable = await verifyCrmProductAccess(token);
      if (!isCrmLaunchable) {
        await _tokenStorage.clearTokens();
        return false;
      }

      // Initialize CRM identity
      await initializeCrmSession(token, fallbackUser: platformUser);
      return true;
    } catch (e) {
      debugPrint('OAuth: restoreSession error: $e');
      if (e is DioException && (e.response?.statusCode == 401 || e.response?.statusCode == 403)) {
        await _tokenStorage.clearTokens();
        return false;
      }
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PKCE Generation Methods
  // ──────────────────────────────────────────────────────────────────────────

  String generateCodeVerifier() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(64, (_) => chars[random.nextInt(chars.length)]).join();
  }

  String generateCodeChallenge(String verifier) {
    final bytes = ascii.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  String generateState() {
    final random = Random.secure();
    final values = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(values).replaceAll('=', '');
  }

  Uri buildAuthorizationUrl({
    required String codeChallenge,
    required String state,
    String? emailHint,
  }) {
    final baseUri = Uri.parse(ApiUrl.oauthAuthorizeUrl);
    final queryParams = <String, String>{
      'client_id': ApiUrl.oauthClientId,
      'redirect_uri': ApiUrl.mobileRedirectUri,
      'response_type': 'code',
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'state': state,
    };

    if (emailHint != null && emailHint.trim().isNotEmpty) {
      queryParams['login_hint'] = emailHint.trim();
    }

    return baseUri.replace(queryParameters: queryParams);
  }

  static const MethodChannel _platformChannel =
      MethodChannel('com.example.crm_mobile/call_recording');

  Future<bool> startAuthorizationFlow({String? emailHint}) async {
    final closing = _closing;
    if (closing != null) await closing.future;
    // Repeated taps must not overwrite the verifier for the browser already open.
    if (_authorizationFlowActive || _isExchangingCode || _preparation != null) return true;
    _sessionGeneration++;
    _authorizationFlowActive = true;
    final generation = ++_authorizationGeneration;
    try {
      final launched = await _startAuthorizationFlow(emailHint, generation);
      if (!launched && generation == _authorizationGeneration) {
        _authorizationFlowActive = false;
      }
      return launched;
    } catch (_) {
      if (generation == _authorizationGeneration) await cancelAuthorizationFlow();
      rethrow;
    }
  }

  Future<bool> _startAuthorizationFlow(String? emailHint, int generation) async {
    final verifier = generateCodeVerifier();
    final challenge = generateCodeChallenge(verifier);
    final state = generateState();

    final preparation = Completer<void>();
    _preparation = preparation;
    try {
      await _tokenStorage.savePendingPkce(codeVerifier: verifier, state: state);
      if (generation != _authorizationGeneration) return true;
    } finally {
      preparation.complete();
      _preparation = null;
    }

    final authUrl = buildAuthorizationUrl(
      codeChallenge: challenge,
      state: state,
      emailHint: emailHint,
    );

    if (generation != _authorizationGeneration) return true;
    debugPrint('OAuth: Opening secure login');

    // 1. First priority: Native In-App WebView Dialog (100% inside app, reliable URL interception)
    try {
      final callbackUrl = await _platformChannel.invokeMethod<String>(
        'openOAuthWebView',
        {
          'url': authUrl.toString(),
          'redirectUri': ApiUrl.mobileRedirectUri,
        },
      );

      if (generation != _authorizationGeneration ||
          _callbackClaimedGeneration == generation) {
        return true;
      }
      if (callbackUrl != null && callbackUrl.isNotEmpty) {
        await handleAuthorizationCallback(Uri.parse(callbackUrl));
        return true;
      } else {
        debugPrint('OAuth: In-app login cancelled or closed by user');
        await cancelAuthorizationFlow();
        return false;
      }
    } on MissingPluginException {
      debugPrint('OAuth: Native in-app WebView method channel not available on this platform, falling back to url_launcher');
    } catch (e) {
      debugPrint('OAuth: Native in-app WebView exception: $e, falling back to url_launcher');
    }

    if (generation != _authorizationGeneration) return true;
    // 2. Fallback: Launch inside the app using inAppBrowserView / inAppWebView
    bool launched = false;
    try {
      launched = await launchUrl(
        authUrl,
        mode: LaunchMode.inAppBrowserView,
        webViewConfiguration: const WebViewConfiguration(
          enableJavaScript: true,
          enableDomStorage: true,
        ),
      );
    } catch (e) {
      debugPrint('OAuth: inAppBrowserView failed: $e, falling back to inAppWebView');
    }

    if (!launched) {
      try {
        launched = await launchUrl(
          authUrl,
          mode: LaunchMode.inAppWebView,
          webViewConfiguration: const WebViewConfiguration(
            enableJavaScript: true,
            enableDomStorage: true,
          ),
        );
      } catch (e) {
        debugPrint('OAuth: inAppWebView failed: $e, falling back to platformDefault');
      }
    }

    if (!launched) {
      try {
        launched = await launchUrl(
          authUrl,
          mode: LaunchMode.platformDefault,
          webViewConfiguration: const WebViewConfiguration(
            enableJavaScript: true,
            enableDomStorage: true,
          ),
        );
      } catch (e) {
        debugPrint('OAuth: platformDefault failed: $e');
      }
    }

    if (!launched) {
      debugPrint('OAuth: Cannot launch authorization URL inside app');
      await _tokenStorage.clearPendingPkce();
      return false;
    }

    return true;
  }

  /// Explicitly closes any active in-app web browser view and clears pending PKCE.
  Future<void> closeInAppLogin() async {
    final previous = _closing;
    if (previous != null) return previous.future;
    final closing = Completer<void>();
    _closing = closing;
    _authorizationGeneration++;
    _authorizationFlowActive = false;
    try {
      final preparation = _preparation;
      if (preparation != null) await preparation.future;
      await _tokenStorage.clearPendingPkce();
      try {
        await _platformChannel.invokeMethod('closeOAuthWebView');
      } catch (_) {}
      try {
        await closeInAppWebView();
      } catch (_) {}
    } finally {
      closing.complete();
      _closing = null;
    }
  }

  /// Cancels in-flight authorization flow and clears pending PKCE.
  Future<void> cancelAuthorizationFlow() async {
    await closeInAppLogin();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Deep-Link Callback Handling
  // ──────────────────────────────────────────────────────────────────────────

  /// Both native WebView and app-links callbacks enter the same serial queue.
  Future<void> handleAuthorizationCallback(Uri uri) {
    final operation = _callbackQueue.then((_) => _processAuthorizationCallback(uri));
    _callbackQueue = operation.catchError((Object error) {
      debugPrint('OAuth: Callback processing failed (${error.runtimeType})');
    });
    return operation;
  }

  Future<void> _processAuthorizationCallback(Uri uri) async {
    final expected = Uri.parse(ApiUrl.mobileRedirectUri);
    if (uri.scheme.toLowerCase() != expected.scheme.toLowerCase() ||
        uri.host.toLowerCase() != expected.host.toLowerCase() ||
        uri.port != expected.port || uri.path != expected.path ||
        uri.userInfo.isNotEmpty || uri.fragment.isNotEmpty) {
      return;
    }

    final fingerprint = sha256.convert(utf8.encode(uri.toString())).toString();
    // Duplicate delivery after success must be ignored before reading cleared state.
    if (_processedCodes.contains(fingerprint)) return;
    final generation = _authorizationGeneration;
    final state = uri.queryParameters['state'];
    final savedState = await _tokenStorage.getPendingState();
    if (generation != _authorizationGeneration) return;
    // An old initial link or mismatched callback cannot consume a newer login.
    if (state == null || savedState == null || savedState.isEmpty || state != savedState) return;

    final error = uri.queryParameters['error'];
    final code = uri.queryParameters['code'];
    if ((error == null || error.isEmpty) && (code == null || code.trim().isEmpty)) return;
    final verifier = await _tokenStorage.getPendingVerifier();
    if (generation != _authorizationGeneration) return;

    _processedCodes.add(fingerprint);
    if (_processedCodes.length > 64) _processedCodes.remove(_processedCodes.first);
    _isExchangingCode = true;
    _callbackClaimedGeneration = generation;
    OAuthCallbackResult result;
    try {
      // Closing the native dialog can deliver the same callback a second time.
      try { await _platformChannel.invokeMethod('closeOAuthWebView'); } catch (_) {}
      try { await closeInAppWebView(); } catch (_) {}
      if (generation != _authorizationGeneration) return;
      if (error != null && error.isNotEmpty) {
        throw ApiException(message: 'Sign in was not completed. Please try again.');
      }
      if (verifier == null || verifier.isEmpty) {
        throw ApiException(message: 'PKCE code verifier not found. Please restart login.');
      }
      final user = await exchangeAuthorizationCode(code: code!, codeVerifier: verifier);
      result = OAuthCallbackResult.success(user);
    } catch (error) {
      result = OAuthCallbackResult.failure(error is ApiException
          ? error.message : 'Unable to complete sign in. Please try again.');
    } finally {
      if (generation == _authorizationGeneration) {
        await _tokenStorage.clearPendingPkce();
        _authorizationFlowActive = false;
      }
      _isExchangingCode = false;
    }
    if (generation == _authorizationGeneration && !_callbackStreamController.isClosed) {
      _callbackStreamController.add(result);
    }
  }

  Future<User> exchangeAuthorizationCode({
    required String code,
    required String codeVerifier,
  }) async {
    final tokenUrl = ApiUrl.oauthTokenUrl;

    final response = await _dio.post(
      tokenUrl,
      data: {
        'grant_type': 'authorization_code',
        'client_id': ApiUrl.oauthClientId,
        'code': code,
        'redirect_uri': ApiUrl.mobileRedirectUri,
        'code_verifier': codeVerifier,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'Accept': 'application/json',
        },
      ),
    );

    final body = response.data;
    if (body == null || (body is! Map<String, dynamic> && body is! Map)) {
      throw ApiException(message: 'Empty or invalid token response from server');
    }

    final tokenMap = Map<String, dynamic>.from(body as Map);
    final tokenResponse = OAuthTokenResponse.fromJson(tokenMap);

    if (tokenResponse.accessToken.isEmpty) {
      throw ApiException(
        message: tokenMap['error_description'] ?? 'Token exchange returned empty access token',
      );
    }

    await _tokenStorage.saveTokens(
      accessToken: tokenResponse.accessToken,
      refreshToken: tokenResponse.refreshToken,
      expiresIn: tokenResponse.expiresIn,
      tokenType: tokenResponse.tokenType,
    );

    // Fetch Platform user profile (gracefully fallback if endpoint structure differs)
    User platformUser;
    try {
      platformUser = await fetchCurrentUser(
        tokenResponse.accessToken,
        tokenResponse: tokenResponse,
      );
    } catch (e) {
      debugPrint('OAuth: fetchCurrentUser non-fatal error: $e');
      platformUser = UserModel(
        accessToken: tokenResponse.accessToken,
        expiresIn: tokenResponse.expiresIn,
        tokenType: tokenResponse.tokenType,
        userId: '',
        userName: 'Tickora User',
        role: 'user',
        privileges: const [],
      );
    }

    // Verify CRM product access (non-fatal check so user is not blocked on valid login)
    try {
      final isCrmLaunchable = await verifyCrmProductAccess(tokenResponse.accessToken);
      if (!isCrmLaunchable) {
        debugPrint('OAuth: CRM product access check returned false, but proceeding with session');
      }
    } catch (e) {
      debugPrint('OAuth: verifyCrmProductAccess non-fatal warning: $e');
    }

    // Initialize CRM session & privileges
    User crmUser;
    try {
      crmUser = await initializeCrmSession(
        tokenResponse.accessToken,
        fallbackUser: platformUser,
      );
    } catch (e) {
      debugPrint('OAuth: initializeCrmSession non-fatal fallback: $e');
      crmUser = platformUser;
    }

    return crmUser;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Token Refresh
  // ──────────────────────────────────────────────────────────────────────────

  /// Refreshes the access token using the stored refresh token.
  /// Prevents concurrent refresh requests and race conditions using an in-flight Completer.
  Future<String?> refreshToken() async {
    if (_inFlightRefresh != null) {
      return await _inFlightRefresh!.future;
    }

    // Reserve the single flight before the first storage await.
    final flight = Completer<String?>();
    _inFlightRefresh = flight;
    final generation = _sessionGeneration;
    try {
      final currentRefreshToken = await _tokenStorage.getRefreshToken();
      if (currentRefreshToken == null || currentRefreshToken.isEmpty) {
        flight.complete(null);
        return null;
      }
      final tokenUrl = ApiUrl.oauthTokenUrl;

      final response = await _dio.post(
        tokenUrl,
        data: {
          'grant_type': 'refresh_token',
          'client_id': ApiUrl.oauthClientId,
          'refresh_token': currentRefreshToken,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'Accept': 'application/json',
          },
        ),
      );

      final body = response.data;
      if (body == null || (body is! Map<String, dynamic> && body is! Map)) {
        throw ApiException(message: 'Invalid refresh token response');
      }

      final tokenMap = Map<String, dynamic>.from(body as Map);
      final tokenResponse = OAuthTokenResponse.fromJson(tokenMap);

      if (tokenResponse.accessToken.isEmpty) {
        throw ApiException(message: 'Refresh token response contained empty access token');
      }

      final newRefreshToken = tokenResponse.refreshToken.isNotEmpty
          ? tokenResponse.refreshToken
          : currentRefreshToken;

      if (generation != _sessionGeneration) {
        flight.complete(null);
        return null;
      }
      await _tokenStorage.saveTokens(
        accessToken: tokenResponse.accessToken,
        refreshToken: newRefreshToken,
        expiresIn: tokenResponse.expiresIn,
        tokenType: tokenResponse.tokenType,
      );

      flight.complete(tokenResponse.accessToken);
      return tokenResponse.accessToken;
    } catch (e) {
      debugPrint('OAuth: Token refresh failed: $e');
      flight.complete(null);
      if (generation != _sessionGeneration) return null;

      // Only clear tokens and force logout if the server explicitly confirmed
      // the refresh token is revoked or invalid (e.g. invalid_grant).
      // Network timeouts, offline state, or 5xx server errors must NOT log the user out!
      bool isPermanentAuthFailure = false;
      if (e is DioException) {
        final status = e.response?.statusCode;
        final data = e.response?.data;
        final errorStr = (data is Map ? (data['errorCode'] ?? data['error'] ?? data['message'] ?? '') : (e.message ?? '')).toString().toLowerCase();
        if ((status == 400 || status == 401) &&
            (errorStr.contains('invalid_refresh_token') ||
             errorStr.contains('session_expired') ||
             errorStr.contains('user_not_active') ||
             errorStr.contains('invalid_grant') ||
             errorStr.contains('invalid_token') ||
             errorStr.contains('revoked') ||
             errorStr.contains('unauthorized'))) {
          isPermanentAuthFailure = true;
        }
      }

      if (isPermanentAuthFailure) {
        await _tokenStorage.clearTokens();
        NavigationService.handleSessionExpired();
      }
      return null;
    } finally {
      _inFlightRefresh = null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Current User Profile & Logout
  // ──────────────────────────────────────────────────────────────────────────

  Future<User> fetchCurrentUser(
    String accessToken, {
    OAuthTokenResponse? tokenResponse,
  }) async {
    final meUrl = ApiUrl.platformMeUrl;

    final response = await _dio.get(
      meUrl,
      options: Options(
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      ),
    );

    final body = response.data;
    Map<String, dynamic> data = {};
    if (body != null && body is Map) {
      if (body['data'] != null && body['data'] is Map) {
        data = Map<String, dynamic>.from(body['data']);
      } else {
        data = Map<String, dynamic>.from(body);
      }
    }

    Map<String, dynamic> jwtClaims = {};
    try {
      final parts = accessToken.split('.');
      if (parts.length == 3) {
        final payload = parts[1];
        final normalized = base64Url.normalize(payload);
        final decoded = utf8.decode(base64Url.decode(normalized));
        jwtClaims = jsonDecode(decoded);
      }
    } catch (_) {}

    final userId = (data['id'] ?? data['userId'] ?? jwtClaims['userId'] ?? jwtClaims['sub'] ?? '').toString();
    final userName = (data['fullName'] ??
            data['name'] ??
            data['username'] ??
            jwtClaims['fullName'] ??
            jwtClaims['name'] ??
            jwtClaims['preferred_username'] ??
            jwtClaims['username'] ??
            'User')
        .toString();
    final userEmail = (data['email'] ?? jwtClaims['email'] ?? '').toString();
    final userPhone = (data['phone'] ??
            data['phoneNumber'] ??
            data['mobile'] ??
            data['contactNumber'] ??
            jwtClaims['phone'] ??
            jwtClaims['mobile'] ??
            '')
        .toString();

    String userRole = '';
    if (data['roles'] is List) {
      userRole = (data['roles'] as List).join(', ');
    } else if (data['role'] != null) {
      userRole = data['role'].toString();
    } else if (jwtClaims['roles'] is List) {
      userRole = (jwtClaims['roles'] as List).join(', ');
    } else if (jwtClaims['role'] != null) {
      userRole = jwtClaims['role'].toString();
    }

    final orgId = (data['organizationId'] ??
            data['orgId'] ??
            jwtClaims['organizationId'] ??
            jwtClaims['orgId'] ??
            '')
        .toString();

    if (userId.isNotEmpty) await _sharedPreferences.setString('userId', userId);
    if (userName.isNotEmpty) await _sharedPreferences.setString('userName', userName);
    if (userEmail.isNotEmpty) await _sharedPreferences.setString('userEmail', userEmail);
    if (userRole.isNotEmpty) await _sharedPreferences.setString('userRole', userRole);
    if (userPhone.isNotEmpty) await _sharedPreferences.setString('userPhone', userPhone);
    if (orgId.isNotEmpty) await _sharedPreferences.setString('organizationId', orgId);

    final List<String> privileges = PrivilegeService.parsePrivilegeList(data);
    if (jwtClaims.isNotEmpty) {
      privileges.addAll(PrivilegeService.parsePrivilegeList(jwtClaims));
    }
    if (privileges.isNotEmpty && sl.isRegistered<PrivilegeService>()) {
      sl<PrivilegeService>().setPrivileges(privileges, replace: true);
    }

    return UserModel(
      accessToken: accessToken,
      expiresIn: tokenResponse?.expiresIn ?? 3600,
      tokenType: tokenResponse?.tokenType ?? 'Bearer',
      userId: userId,
      userName: userName,
      role: userRole,
      privileges: privileges,
    );
  }

  Future<void> logout() async {
    _sessionGeneration++;
    try {
      final token = await _tokenStorage.getAccessToken();
      if (token != null && token.isNotEmpty) {
        await _dio.post(
          ApiUrl.oauthLogoutUrl,
          options: Options(
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          ),
        );
      }
    } catch (e) {
      debugPrint('OAuth: Logout API error (clearing local session anyway): $e');
    } finally {
      await _tokenStorage.clearTokens();
      await _sharedPreferences.remove('token');
      await _sharedPreferences.remove('cached_privileges');
      if (sl.isRegistered<PrivilegeService>()) {
        sl<PrivilegeService>().setPrivileges([], replace: true);
      }
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
    _callbackStreamController.close();
  }
}

class OAuthCallbackResult {
  final bool isSuccess;
  final User? user;
  final String? errorMessage;

  const OAuthCallbackResult._({
    required this.isSuccess,
    this.user,
    this.errorMessage,
  });

  factory OAuthCallbackResult.success(User user) =>
      OAuthCallbackResult._(isSuccess: true, user: user);

  factory OAuthCallbackResult.failure(String message) =>
      OAuthCallbackResult._(isSuccess: false, errorMessage: message);
}
