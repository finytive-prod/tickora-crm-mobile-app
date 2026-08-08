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
          components.add('--data-binary "@[FormData]"');
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
