import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthInterceptor extends Interceptor {
  final SharedPreferences _sharedPreferences;
  final Function() onSessionExpired;

  AuthInterceptor(this._sharedPreferences, {required this.onSessionExpired});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _sharedPreferences.getString('token');
    if (token != null && token.isNotEmpty) {
      if (_isTokenExpired(token)) {
        _sharedPreferences.remove('token');
        onSessionExpired();
        return handler.reject(
          DioException(
            requestOptions: options,
            error: 'Token expired',
            type: DioExceptionType.cancel,
          ),
        );
      }
      options.headers['Authorization'] = 'Bearer $token';
    }
    super.onRequest(options, handler);
  }

  bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = parts[1];
        var normalized = base64Url.normalize(payload);
        final resp = utf8.decode(base64Url.decode(normalized));
        final Map<String, dynamic> decoded = jsonDecode(resp);
        if (decoded.containsKey('exp')) {
          final exp = decoded['exp'] as int;
          final expDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
          return DateTime.now().add(const Duration(seconds: 30)).isAfter(expDate);
        }
      }
    } catch (_) {}
    return false;
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      await _sharedPreferences.remove('token');
      onSessionExpired();
    }
    super.onError(err, handler);
  }
}
