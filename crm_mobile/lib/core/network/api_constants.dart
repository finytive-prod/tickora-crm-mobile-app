import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConstants {
  ApiConstants._();

  static const String baseUrlEnvKey = 'BASE_URL';
  static const int connectTimeout = 15000;
  static const int receiveTimeout = 15000;
  static const int sendTimeout = 15000;
}

class ApiUrl {
  ApiUrl._();

  static String get rawBaseUrl {
    var url = 'http://50.117.0.165:8080';
    try {
      if (dotenv.isInitialized) {
        url = dotenv.env['BASE_URL'] ?? url;
      }
    } catch (_) {}
    url = url.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  static String get serverOrigin {
    final raw = rawBaseUrl;
    try {
      final uri = Uri.parse(raw);
      if (uri.scheme.isNotEmpty && uri.host.isNotEmpty) {
        return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      }
    } catch (_) {}
    return raw.replaceAll(RegExp(r'/api/crm.*$'), '');
  }

  static String get leadService {
    final raw = rawBaseUrl;
    if (raw.contains('/api/crm/lead-service')) {
      return raw;
    }
    if (raw.endsWith('/api/crm')) {
      return '$raw/lead-service';
    }
    return '$serverOrigin/api/crm/lead-service';
  }

  static String get identityService {
    final raw = rawBaseUrl;
    if (raw.contains('/api/crm/lead-service')) {
      return raw.replaceAll(
        '/api/crm/lead-service',
        '/api/crm/identity-service',
      );
    }
    if (raw.endsWith('/api/crm')) {
      return '$raw/identity-service';
    }
    return '$serverOrigin/api/crm/identity-service';
  }

  static String get customerService {
    final raw = rawBaseUrl;
    if (raw.contains('/api/crm/lead-service')) {
      return raw.replaceAll(
        '/api/crm/lead-service',
        '/api/crm/customer-service',
      );
    }
    if (raw.endsWith('/api/crm')) {
      return '$raw/customer-service';
    }
    return '$serverOrigin/api/crm/customer-service';
  }

  static String get taskService {
    final raw = rawBaseUrl;
    if (raw.contains('/api/crm/lead-service')) {
      return raw.replaceAll('/api/crm/lead-service', '/api/crm/task-service');
    }
    if (raw.endsWith('/api/crm')) {
      return '$raw/task-service';
    }
    return '$serverOrigin/api/crm/task-service';
  }

  static String get notificationService {
    final raw = rawBaseUrl;
    if (raw.contains('/api/crm/lead-service')) {
      return raw.replaceAll(
        '/api/crm/lead-service',
        '/api/crm/notification-service',
      );
    }
    if (raw.endsWith('/api/crm')) {
      return '$raw/notification-service';
    }
    return '$serverOrigin/api/crm/notification-service';
  }

  // ── Platform OAuth 2.0 PKCE configuration & endpoints ──
  static String get oauthClientId {
    try {
      if (dotenv.isInitialized) {
        return dotenv.env['OAUTH_CLIENT_ID'] ?? 'tickora-launcher-web';
      }
    } catch (_) {}
    return 'tickora-launcher-web';
  }

  static String get mobileRedirectUri {
    try {
      if (dotenv.isInitialized) {
        return dotenv.env['OAUTH_REDIRECT_URI'] ?? '$serverOrigin/callback';
      }
    } catch (_) {}
    return '$serverOrigin/callback';
  }

  static String get platformLoginUrl => '$serverOrigin/api/v1/auth/login';
  static String get oauthAuthorizeUrl => '$serverOrigin/login';
  static String get oauthTokenUrl => '$serverOrigin/oauth2/token';
  static String get platformMeUrl => '$serverOrigin/api/v1/platform/me';
  static String get platformProductsAccessUrl => '$serverOrigin/api/v1/platform/products/access';
  static String get crmPlatformSessionUrl => '$serverOrigin/api/crm/identity-service/platform/session';
  static String get oauthLogoutUrl => '$serverOrigin/api/platform/auth/session/logout';
}
