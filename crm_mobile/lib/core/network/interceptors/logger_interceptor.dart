import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

class LoggerInterceptor extends Interceptor {
  final Logger logger;
  final Map<String, DateTime> _requestTimers = {};

  LoggerInterceptor(this.logger);

  void _printLog(String message) {
    if (kDebugMode) {
      for (var line in message.split('\n')) {
        print(line);
      }
    }
  }

  String _getCurlCommand(RequestOptions options) {
    try {
      List<String> components = ['curl -i'];
      
      if (options.method.toUpperCase() != 'GET') {
        components.add('-X ${options.method}');
      }

      options.headers.forEach((k, v) {
        if (k != 'Cookie') {
          components.add('-H "$k: $v"');
        }
      });

      if (options.data != null) {
        if (options.data is FormData) {
          final formData = options.data as FormData;
          for (var field in formData.fields) {
            components.add('-F "${field.key}=${field.value.replaceAll('"', '\\"')}"');
          }
          for (var file in formData.files) {
            final fileName = file.value.filename ?? 'unnamed_file';
            components.add('-F "${file.key}=@$fileName"');
          }
        } else {
          final data = json.encode(options.data).replaceAll('"', '\\"');
          components.add('-d "$data"');
        }
      }

      components.add('"${options.uri.toString()}"');
      return components.join(' \\\n  ');
    } catch (e) {
      return 'Failed to generate cURL: $e';
    }
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      _requestTimers[options.uri.toString()] = DateTime.now();
      
      final curlCommand = _getCurlCommand(options);
      
      _printLog('========== API REQUEST ==========');
      _printLog('URL: ${options.uri}');
      _printLog('cURL Command:\n$curlCommand');

      if (options.data != null) {
        if (options.data is FormData) {
          final formData = options.data as FormData;
          _printLog('--- FormData Payload ---');
          for (var field in formData.fields) {
            _printLog('${field.key}: ${field.value}');
          }
          for (var file in formData.files) {
            _printLog('${file.key}: File(${file.value.filename}, contentType: ${file.value.contentType})');
          }
          _printLog('------------------------');
        } else {
          _printLog('--- Request Payload ---');
          try {
            _printLog(const JsonEncoder.withIndent('  ').convert(options.data));
          } catch (_) {
            _printLog(options.data.toString());
          }
          _printLog('-----------------------');
        }
      }
      _printLog('=================================\n');
    }
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      final requestTime = _requestTimers[response.requestOptions.uri.toString()];
      final duration = requestTime != null ? DateTime.now().difference(requestTime).inMilliseconds : -1;
      
      _printLog('========== API RESPONSE ==========');
      _printLog('URL: ${response.requestOptions.uri}');
      _printLog('Status Code: ${response.statusCode}');
      _printLog('Response Time: $duration ms');

      _printLog('--- Response Payload ---');
      try {
        if (response.data is Map || response.data is List) {
          _printLog(const JsonEncoder.withIndent('  ').convert(response.data));
        } else {
          _printLog(response.data.toString());
        }
      } catch (_) {
        _printLog(response.data.toString());
      }
      _printLog('------------------------');
      _printLog('==================================\n');

      _requestTimers.remove(response.requestOptions.uri.toString());
    }
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      final requestTime = _requestTimers[err.requestOptions.uri.toString()];
      final duration = requestTime != null ? DateTime.now().difference(requestTime).inMilliseconds : -1;

      _printLog('========== API ERROR ==========');
      _printLog('URL: ${err.requestOptions.uri}');
      _printLog('Method: ${err.requestOptions.method}');
      _printLog('Status Code: ${err.response?.statusCode}');
      _printLog('Response Time: $duration ms');
      _printLog('Error: ${err.message}');

      if (err.response?.data != null) {
        _printLog('--- Error Response Payload ---');
        try {
          if (err.response!.data is Map || err.response!.data is List) {
            _printLog(const JsonEncoder.withIndent('  ').convert(err.response!.data));
          } else {
            _printLog(err.response!.data.toString());
          }
        } catch (_) {
          _printLog(err.response!.data.toString());
        }
        _printLog('------------------------------');
      }
      _printLog('===============================\n');

      _requestTimers.remove(err.requestOptions.uri.toString());
    }
    super.onError(err, handler);
  }
}
