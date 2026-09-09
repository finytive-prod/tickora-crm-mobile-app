import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConstants {
  ApiConstants._();

  static const String baseUrlEnvKey = 'BASE_URL';
  static const int connectTimeout = 60000;
  static const int receiveTimeout = 120000;
  static const int sendTimeout = 120000;
}

class ApiUrl {
  ApiUrl._();

  static String get rawBaseUrl {
    var url = dotenv.env['BASE_URL'] ?? 'http://50.117.0.165:8080';
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
      return raw.replaceAll('/api/crm/lead-service', '/api/crm/identity-service');
    }
    if (raw.endsWith('/api/crm')) {
      return '$raw/identity-service';
    }
    return '$serverOrigin/api/crm/identity-service';
  }

  static String get customerService {
    final raw = rawBaseUrl;
    if (raw.contains('/api/crm/lead-service')) {
      return raw.replaceAll('/api/crm/lead-service', '/api/crm/customer-service');
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
      return raw.replaceAll('/api/crm/lead-service', '/api/crm/notification-service');
    }
    if (raw.endsWith('/api/crm')) {
      return '$raw/notification-service';
    }
    return '$serverOrigin/api/crm/notification-service';
  }
}
