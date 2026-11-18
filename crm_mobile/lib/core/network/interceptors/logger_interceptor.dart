import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../network_log_manager.dart';

class LoggerInterceptor extends Interceptor {
  final Logger logger;

  LoggerInterceptor(this.logger);

  void _printLog(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  String _formatPayload(dynamic data, {int maxLines = 45}) {
    if (data == null) return 'null';
    String str;
    try {
      if (data is Map || data is List) {
        str = const JsonEncoder.withIndent('  ').convert(data);
      } else if (data is String) {
        try {
          final decoded = json.decode(data);
          str = const JsonEncoder.withIndent('  ').convert(decoded);
        } catch (_) {
          str = data;
        }
      } else {
        str = data.toString();
      }
    } catch (_) {
      str = data.toString();
    }

    final lines = str.split('\n');
    if (lines.length > maxLines) {
      final kept = lines.take(maxLines).join('\n');
      final remaining = lines.length - maxLines;
      return '$kept\n... [+$remaining lines truncated to keep terminal readable]';
    }
    return str;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final reqId = NetworkLogManager.instance.logRequest(options);
    options.extra['_req_id'] = reqId;
    options.extra['_req_time'] = DateTime.now();

    if (kDebugMode) {
      final buffer = StringBuffer();
      buffer.writeln('╔════ 🚀 [REQ #$reqId] ${options.method} ${options.uri.path}');
      buffer.writeln('║ Full URL: ${options.uri}');
      if (options.queryParameters.isNotEmpty) {
        buffer.writeln('║ Query: ${options.queryParameters}');
      }

      if (options.data != null) {
        buffer.writeln('║ Payload:');
        dynamic payloadData = options.data;

        if (options.data is FormData) {
          final formData = options.data as FormData;
          final map = <String, dynamic>{};
          for (final f in formData.fields) {
            map[f.key] = f.value;
          }
          if (formData.files.isNotEmpty) {
            final filesMap = <String, String>{};
            for (final f in formData.files) {
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
          payloadData = map;
        }

        for (final line in _formatPayload(payloadData, maxLines: 40).split('\n')) {
          buffer.writeln('║   $line');
        }
      }
      buffer.write('╚═══════════════════════════════════════════════════════');
      _printLog(buffer.toString());
    }
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    NetworkLogManager.instance.logResponse(response);

    if (kDebugMode) {
      final reqId = response.requestOptions.extra['_req_id'] ?? '?';
      final startTime = response.requestOptions.extra['_req_time'] as DateTime?;
      final duration = startTime != null
          ? DateTime.now().difference(startTime).inMilliseconds
          : -1;
      final status = response.statusCode ?? 200;
      final icon = (status >= 200 && status < 300) ? '🟢' : '🟡';

      final buffer = StringBuffer();
      buffer.writeln('╔════ $icon [RES #$reqId] $status ${response.requestOptions.method} (${duration}ms)');
      buffer.writeln('║ URL: ${response.requestOptions.uri}');
      buffer.writeln('║ Response:');
      for (final line in _formatPayload(response.data, maxLines: 40).split('\n')) {
        buffer.writeln('║   $line');
      }
      buffer.write('╚═══════════════════════════════════════════════════════');
      _printLog(buffer.toString());
    }
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    NetworkLogManager.instance.logError(err);

    if (kDebugMode) {
      final reqId = err.requestOptions.extra['_req_id'] ?? '?';
      final startTime = err.requestOptions.extra['_req_time'] as DateTime?;
      final duration = startTime != null
          ? DateTime.now().difference(startTime).inMilliseconds
          : -1;
      final status = err.response?.statusCode ?? 'FAIL';

      final buffer = StringBuffer();
      buffer.writeln('╔════ 🔴 [ERR #$reqId] $status ${err.requestOptions.method} (${duration}ms)');
      buffer.writeln('║ URL: ${err.requestOptions.uri}');
      buffer.writeln('║ Error: ${err.message}');
      if (err.response?.data != null) {
        buffer.writeln('║ Error Data:');
        for (final line in _formatPayload(err.response!.data, maxLines: 30).split('\n')) {
          buffer.writeln('║   $line');
        }
      }
      buffer.write('╚═══════════════════════════════════════════════════════');
      _printLog(buffer.toString());
    }
    super.onError(err, handler);
  }
}
