import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

class LoggerInterceptor extends Interceptor {
  final Logger logger;
  final Map<String, DateTime> _requestTimers = {};

  LoggerInterceptor(this.logger);

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
      return components.join(' ');
    } catch (e) {
      return 'Failed to generate cURL: $e';
    }
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      _requestTimers[options.uri.toString()] = DateTime.now();
      
      final curlCommand = _getCurlCommand(options);
      
      logger.d('*** API Request - Start ***\nURL: ${options.uri}');
      debugPrint('cURL: $curlCommand');

      if (options.data != null) {
        if (options.data is FormData) {
          final formData = options.data as FormData;
          debugPrint('--- FormData Payload ---');
          for (var field in formData.fields) {
            debugPrint('${field.key}: ${field.value}');
          }
          for (var file in formData.files) {
            debugPrint('${file.key}: File(${file.value.filename}, contentType: ${file.value.contentType})');
          }
          debugPrint('------------------------');
        } else {
          debugPrint('--- Request Payload ---');
          try {
            debugPrint(const JsonEncoder.withIndent('  ').convert(options.data));
          } catch (_) {
            debugPrint(options.data.toString());
          }
          debugPrint('-----------------------');
        }
      }
    }
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      final requestTime = _requestTimers[response.requestOptions.uri.toString()];
      final duration = requestTime != null ? DateTime.now().difference(requestTime).inMilliseconds : -1;
      
      logger.i(
        '*** API Response - End ***\n'
        'URL: ${response.requestOptions.uri}\n'
        'Status Code: ${response.statusCode}\n'
        'Response Time: $duration ms\n'
        'Response Data: ${response.data}\n',
      );
      _requestTimers.remove(response.requestOptions.uri.toString());
    }
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      final requestTime = _requestTimers[err.requestOptions.uri.toString()];
      final duration = requestTime != null ? DateTime.now().difference(requestTime).inMilliseconds : -1;

      logger.e(
        '*** API Error - End ***\n'
        'URL: ${err.requestOptions.uri}\n'
        'Method: ${err.requestOptions.method}\n'
        'Status Code: ${err.response?.statusCode}\n'
        'Response Time: $duration ms\n'
        'Error: ${err.message}\n'
        'Response Data: ${err.response?.data}\n',
      );
      _requestTimers.remove(err.requestOptions.uri.toString());
    }
    super.onError(err, handler);
  }
}
