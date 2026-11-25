import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/core/network/api_constants.dart';
import 'package:crm_mobile/core/services/secure_token_storage.dart';
import 'package:crm_mobile/core/services/oauth_service.dart';
import 'package:crm_mobile/injection/injection.dart';

class AuthInterceptor extends Interceptor {
  final SecureTokenStorage _tokenStorage;
  final Function() onSessionExpired;
  OAuthService? _oauthService;

  AuthInterceptor(
    this._tokenStorage, {
    required this.onSessionExpired,
    OAuthService? oauthService,
  }) : _oauthService = oauthService;

  void setOAuthService(OAuthService oauthService) {
    _oauthService = oauthService;
  }

  /// Determines whether a string is a non-empty, non-null representation of a tenant/org ID.
  static bool isValidTenantId(String? id) {
    if (id == null) return false;
    final trimmed = id.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    return lower != 'null' && lower != 'undefined' && lower != 'none' && lower != '{}';
  }

  /// Extracts tenant/organization ID from SharedPreferences if available.
  static String? getStoredTenantId() {
    if (!sl.isRegistered<SharedPreferences>()) return null;
    final prefs = sl<SharedPreferences>();
    for (final key in const [
      'organizationId',
      'tenantId',
      'tenant_id',
      'orgId',
      'organization_id',
      'org_id',
    ]) {
      final val = prefs.getString(key);
      if (isValidTenantId(val)) {
        return val!.trim();
      }
    }
    return null;
  }

  /// Extracts tenant/organization ID from JWT claims.
  static String? extractTenantIdFromToken(String? token) {
    if (token == null || token.isEmpty) return null;
    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = parts[1];
        final normalized = base64Url.normalize(payload);
        final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
        if (decoded is Map) {
          // Check top-level claims
          for (final key in const [
            'organizationId',
            'orgId',
            'tenantId',
            'tenant_id',
            'organization_id',
            'org_id',
            'tenant',
            'tid',
            'currentOrgId',
          ]) {
            final val = decoded[key]?.toString();
            if (isValidTenantId(val)) {
              final trimmed = val!.trim();
              if (sl.isRegistered<SharedPreferences>()) {
                sl<SharedPreferences>().setString('organizationId', trimmed);
              }
              return trimmed;
            }
          }

          // Check nested claims (user_metadata, app_metadata, crm, etc.)
          for (final parentKey in const [
            'user',
            'user_metadata',
            'app_metadata',
            'crm',
            'attributes',
            'data',
          ]) {
            final nested = decoded[parentKey];
            if (nested is Map) {
              for (final key in const [
                'organizationId',
                'tenantId',
                'tenant_id',
                'orgId',
              ]) {
                final val = nested[key]?.toString();
                if (isValidTenantId(val)) {
                  final trimmed = val!.trim();
                  if (sl.isRegistered<SharedPreferences>()) {
                    sl<SharedPreferences>().setString('organizationId', trimmed);
                  }
                  return trimmed;
                }
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Resolves the valid tenant ID either from storage or from token claims.
  static String? resolveTenantId(String? token) {
    return getStoredTenantId() ?? extractTenantIdFromToken(token);
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final path = options.path.toLowerCase();
    final isOAuthEndpoint = path.contains('/oauth2/') ||
        path.contains('/auth/login') ||
        path.contains('/auth/verify-mail') ||
        path.contains('/auth/reset-password');

    if (isOAuthEndpoint) {
      return super.onRequest(options, handler);
    }

    try {
      String? token = await _tokenStorage.getAccessToken();

      if (token != null && token.isNotEmpty) {
        final isExpired = await _tokenStorage.isTokenExpired();
        if (isExpired && _oauthService != null) {
          final refreshToken = await _tokenStorage.getRefreshToken();
          // Only attempt proactive refresh if we actually have a refresh token
          if (refreshToken != null && refreshToken.isNotEmpty) {
            try {
              final refreshed = await _oauthService!.refreshToken();
              if (refreshed != null && refreshed.isNotEmpty) {
                token = refreshed;
              }
            } catch (e) {
              debugPrint('AuthInterceptor: Proactive refresh error, continuing with current token: $e');
            }
          }
          // Do NOT aggressively clear tokens or log out here!
          // Let the server make the final decision with the current token.
        }

        options.headers['Authorization'] = 'Bearer $token';

        // Check if existing tenant header is present and valid
        final existingTenantHeader = options.headers['X-Tenant-ID']?.toString() ??
            options.headers['x-tenant-id']?.toString();

        if (isValidTenantId(existingTenantHeader)) {
          // Normalize to standard 'X-Tenant-ID'
          options.headers['X-Tenant-ID'] = existingTenantHeader!.trim();
          options.headers.remove('x-tenant-id');
        } else {
          // Resolve valid tenant ID from prefs or token claims
          final resolvedTenant = resolveTenantId(token);
          if (isValidTenantId(resolvedTenant)) {
            options.headers['X-Tenant-ID'] = resolvedTenant!.trim();
            options.headers.remove('x-tenant-id');
          } else {
            // Strip any invalid or 'null' tenant headers
            options.headers.remove('X-Tenant-ID');
            options.headers.remove('x-tenant-id');
          }
        }
      }
    } catch (e) {
      debugPrint('AuthInterceptor: onRequest token retrieval warning: $e');
    }

    super.onRequest(options, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final path = err.requestOptions.path.toLowerCase();
    final isAuthEndpoint = path.contains('/oauth2/') ||
        path.contains('/auth/login') ||
        path.contains('/auth/verify-mail') ||
        path.contains('/auth/reset-password') ||
        path.contains('/auth/privileges') ||
        path.contains('/auth/permissions');

    final isBackground = err.requestOptions.extra['isBackground'] == true;
    final is401 = err.response?.statusCode == 401;
    final isRetry = err.requestOptions.extra['isRetry'] == true;

    // Never log out on background/non-critical probe requests
    if (isBackground) {
      return super.onError(err, handler);
    }

    if (is401 && !isAuthEndpoint && !isRetry && _oauthService != null) {
      err.requestOptions.extra['isRetry'] = true;

      final refreshToken = await _tokenStorage.getRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        String? newToken;
        try {
          newToken = await _oauthService!.refreshToken();
        } catch (e) {
          debugPrint('AuthInterceptor: Retry refresh error: $e');
        }

        if (newToken != null && newToken.isNotEmpty) {
          // Update authorization header with refreshed token
          err.requestOptions.headers['Authorization'] = 'Bearer $newToken';

          // Ensure X-Tenant-ID header is present and valid
          final currentTenant = err.requestOptions.headers['X-Tenant-ID']?.toString();
          if (!isValidTenantId(currentTenant)) {
            final validTenant = resolveTenantId(newToken);
            if (isValidTenantId(validTenant)) {
              err.requestOptions.headers['X-Tenant-ID'] = validTenant!.trim();
              err.requestOptions.headers.remove('x-tenant-id');
            }
          }

          // Build retry client with proper base URL and timeout configuration
          String reqBaseUrl = err.requestOptions.baseUrl;
          if (reqBaseUrl.isEmpty) {
            reqBaseUrl = dotenv.isInitialized
                ? (dotenv.env[ApiConstants.baseUrlEnvKey] ?? ApiUrl.rawBaseUrl)
                : ApiUrl.rawBaseUrl;
          }

          final retryDio = Dio(
            BaseOptions(
              baseUrl: reqBaseUrl,
              connectTimeout: err.requestOptions.connectTimeout ??
                  const Duration(milliseconds: ApiConstants.connectTimeout),
              receiveTimeout: err.requestOptions.receiveTimeout ??
                  const Duration(milliseconds: ApiConstants.receiveTimeout),
              sendTimeout: err.requestOptions.sendTimeout ??
                  const Duration(milliseconds: ApiConstants.sendTimeout),
            ),
          );

          try {
            final response = await retryDio.fetch(err.requestOptions);
            return handler.resolve(response);
          } on DioException catch (retryErr) {
            // Only if the retried request with a fresh token STILL gives 401 is session invalid
            if (retryErr.response?.statusCode == 401) {
              debugPrint('AuthInterceptor: Retried request returned 401 even with fresh token; session invalid.');
              await _tokenStorage.clearTokens();
              onSessionExpired();
            }
            return handler.reject(retryErr);
          } catch (retryOtherErr) {
            debugPrint('AuthInterceptor: Retry request non-dio error: $retryOtherErr');
            return handler.reject(err);
          }
        }
      }

      // If refresh token was present but failed, check if token is genuinely expired
      final isExpired = await _tokenStorage.isTokenExpired();
      if (isExpired && (refreshToken == null || refreshToken.isEmpty)) {
        await _tokenStorage.clearTokens();
        onSessionExpired();
      }
    } else if (is401 && !isAuthEndpoint && !isRetry) {
      // For requests without OAuthService, only expire session if token is truly expired
      final isExpired = await _tokenStorage.isTokenExpired();
      if (isExpired) {
        await _tokenStorage.clearTokens();
        onSessionExpired();
      }
    }

    super.onError(err, handler);
  }
}
