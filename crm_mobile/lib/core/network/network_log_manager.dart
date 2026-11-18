import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Represents a single HTTP Request and Response cycle log.
class NetworkLogItem {
  final int id;
  final DateTime requestTime;
  DateTime? responseTime;
  final String method;
  final String url;
  final String path;
  final Map<String, dynamic> queryParameters;
  final Map<String, dynamic> requestHeaders;
  final dynamic requestBody;

  int? statusCode;
  dynamic responseBody;
  Map<String, dynamic>? responseHeaders;
  int? durationMs;
  String? errorMessage;
  bool isPending;
  bool isError;

  NetworkLogItem({
    required this.id,
    required this.requestTime,
    this.responseTime,
    required this.method,
    required this.url,
    required this.path,
    required this.queryParameters,
    required this.requestHeaders,
    required this.requestBody,
    this.statusCode,
    this.responseBody,
    this.responseHeaders,
    this.durationMs,
    this.errorMessage,
    this.isPending = true,
    this.isError = false,
  });

  String getFormattedRequestBody() {
    return _prettyJson(requestBody);
  }

  String getFormattedResponseBody() {
    return _prettyJson(responseBody ?? errorMessage);
  }

  static String _prettyJson(dynamic data) {
    if (data == null) return 'null';
    try {
      if (data is Map || data is List) {
        return const JsonEncoder.withIndent('  ').convert(data);
      }
      if (data is String) {
        try {
          final decoded = json.decode(data);
          return const JsonEncoder.withIndent('  ').convert(decoded);
        } catch (_) {
          return data;
        }
      }
      return data.toString();
    } catch (_) {
      return data.toString();
    }
  }

  /// Whether this request targets an audio-related endpoint or returns audio content.
  bool get isAudioEndpoint {
    final lowerPath = path.toLowerCase();
    final lowerUrl = url.toLowerCase();
    final uriPath = Uri.tryParse(lowerUrl)?.path ?? lowerPath;

    if (lowerPath.contains('/audios') ||
        lowerPath.contains('/audio') ||
        uriPath.contains('/audios') ||
        uriPath.contains('/audio') ||
        lowerPath.contains('audio-') ||
        lowerPath.contains('audio_')) {
      return true;
    }

    const audioExtensions = [
      '.mp3',
      '.m4a',
      '.wav',
      '.aac',
      '.3gp',
      '.amr',
      '.ogg',
      '.opus',
      '.flac',
      '.wma',
    ];
    for (final ext in audioExtensions) {
      if (uriPath.endsWith(ext) || lowerPath.endsWith(ext)) {
        return true;
      }
    }

    final contentType = (responseHeaders?['content-type'] ??
            responseHeaders?['Content-Type'])
        ?.toString()
        .toLowerCase();
    if (contentType != null && contentType.startsWith('audio/')) {
      return true;
    }

    return false;
  }

  /// Whether this request targets a call-log or call-report endpoint.
  bool get isCallLogEndpoint {
    final normalizedPath = path.toLowerCase();
    final parsedPath = Uri.tryParse(url.toLowerCase())?.path ?? '';
    const callLogSegments = <String>[
      '/call-logs',
      '/call-log',
      '/call_logs',
      '/call_log',
      '/calllogs',
      '/owner-call-report',
      '/call-report',
    ];
    for (final segment in callLogSegments) {
      if (normalizedPath.contains(segment) || parsedPath.contains(segment)) {
        return true;
      }
    }
    return false;
  }

  /// Whether this request belongs in the combined Audio & Calls logs tab.
  bool get isAudioOrCallLogEndpoint => isAudioEndpoint || isCallLogEndpoint;

  String toCurl() {
    final buffer = StringBuffer('curl -X $method "$url"');
    for (final entry in requestHeaders.entries) {
      buffer.write(' \\\n  -H "${entry.key}: ${entry.value}"');
    }
    if (requestBody != null) {
      if (requestBody is Map || requestBody is List) {
        final jsonStr = json.encode(requestBody).replaceAll('"', '\\"');
        buffer.write(' \\\n  -d "$jsonStr"');
      } else if (requestBody is String && requestBody.isNotEmpty) {
        buffer.write(' \\\n  -d "${requestBody.replaceAll('"', '\\"')}"');
      }
    }
    return buffer.toString();
  }
}

/// Global manager for recording, observing, and clearing in-app network logs.
class NetworkLogManager extends ChangeNotifier {
  static final NetworkLogManager instance = NetworkLogManager._internal();
  NetworkLogManager._internal();

  static const int _maxLogs = 200;
  static int _idCounter = 0;

  final List<NetworkLogItem> _logs = [];

  List<NetworkLogItem> get logs => List.unmodifiable(_logs);

  List<NetworkLogItem> get generalLogs => _logs
      .where((item) => !item.isAudioOrCallLogEndpoint)
      .toList(growable: false);

  List<NetworkLogItem> get audioLogs =>
      _logs.where((item) => item.isAudioEndpoint).toList(growable: false);

  List<NetworkLogItem> get audioAndCallLogs => _logs
      .where((item) => item.isAudioOrCallLogEndpoint)
      .toList(growable: false);

  int get count => _logs.length;

  int get generalCount =>
      _logs.where((item) => !item.isAudioOrCallLogEndpoint).length;

  int get audioCount => _logs.where((item) => item.isAudioEndpoint).length;

  int get audioAndCallCount =>
      _logs.where((item) => item.isAudioOrCallLogEndpoint).length;

  /// Logs an outgoing HTTP request and returns the assigned request ID.
  int logRequest(RequestOptions options) {
    final reqId = ++_idCounter;
    final now = DateTime.now();

    // Parse payload into serializable data
    dynamic payload = options.data;
    if (payload is FormData) {
      final map = <String, dynamic>{};
      for (final f in payload.fields) {
        map[f.key] = f.value;
      }
      if (payload.files.isNotEmpty) {
        final filesMap = <String, String>{};
        for (final f in payload.files) {
          final len = f.value.length;
          final lenStr = len > 1024 * 1024
              ? '${(len / (1024 * 1024)).toStringAsFixed(1)} MB'
              : '${(len / 1024).toStringAsFixed(0)} KB';
          final cType = f.value.contentType?.mimeType ?? '';
          final details = [
            if (cType.isNotEmpty) cType,
            if (len > 0) lenStr,
          ].join(', ');
          filesMap[f.key] =
              '${f.value.filename ?? "file"}${details.isNotEmpty ? " ($details)" : ""}';
        }
        map['[FILES]'] = filesMap;
      }
      payload = map;
    }

    final headersMap = <String, dynamic>{};
    options.headers.forEach((key, value) {
      headersMap[key] = value;
    });

    final item = NetworkLogItem(
      id: reqId,
      requestTime: now,
      method: options.method.toUpperCase(),
      url: options.uri.toString(),
      path: options.uri.path.isEmpty ? '/' : options.uri.path,
      queryParameters: Map<String, dynamic>.from(options.queryParameters),
      requestHeaders: headersMap,
      requestBody: payload,
    );

    _logs.insert(0, item);
    if (_logs.length > _maxLogs) {
      _logs.removeLast();
    }

    notifyListeners();
    return reqId;
  }

  /// Updates the matching log item with response details.
  void logResponse(Response response) {
    final reqId = response.requestOptions.extra['_req_id'];
    final item = _findItem(reqId);
    if (item == null) return;

    final now = DateTime.now();
    item.responseTime = now;
    item.statusCode = response.statusCode ?? 200;
    item.responseBody = response.data;
    item.durationMs = now.difference(item.requestTime).inMilliseconds;
    item.isPending = false;
    item.isError = (item.statusCode ?? 200) >= 400;

    final respHeaders = <String, dynamic>{};
    response.headers.forEach((name, values) {
      respHeaders[name] = values.length == 1 ? values.first : values;
    });
    item.responseHeaders = respHeaders;

    notifyListeners();
  }

  /// Updates the matching log item with error details.
  void logError(DioException error) {
    final reqId = error.requestOptions.extra['_req_id'];
    final item = _findItem(reqId);
    if (item == null) return;

    final now = DateTime.now();
    item.responseTime = now;
    item.statusCode = error.response?.statusCode;
    item.responseBody = error.response?.data;
    item.errorMessage = error.message ?? error.error?.toString() ?? 'Unknown Network Error';
    item.durationMs = now.difference(item.requestTime).inMilliseconds;
    item.isPending = false;
    item.isError = true;

    if (error.response?.headers != null) {
      final respHeaders = <String, dynamic>{};
      error.response!.headers.forEach((name, values) {
        respHeaders[name] = values.length == 1 ? values.first : values;
      });
      item.responseHeaders = respHeaders;
    }

    notifyListeners();
  }

  NetworkLogItem? _findItem(dynamic reqId) {
    if (reqId == null) return null;
    final intId = reqId is int ? reqId : int.tryParse(reqId.toString());
    if (intId == null) return null;
    try {
      return _logs.firstWhere((e) => e.id == intId);
    } catch (_) {
      return null;
    }
  }

  /// Clears all recorded logs.
  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  /// Clears only general API logs (excluding audio and call-log endpoints).
  void clearGeneralLogs() {
    _logs.removeWhere((item) => !item.isAudioOrCallLogEndpoint);
    notifyListeners();
  }

  /// Clears only audio-related endpoint logs.
  void clearAudioLogs() {
    _logs.removeWhere((item) => item.isAudioEndpoint);
    notifyListeners();
  }

  /// Clears both audio and call-log endpoint logs.
  void clearAudioAndCallLogs() {
    _logs.removeWhere((item) => item.isAudioOrCallLogEndpoint);
    notifyListeners();
  }
}
