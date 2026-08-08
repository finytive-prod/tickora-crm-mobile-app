import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthInterceptor extends Interceptor {
  final SharedPreferences _sharedPreferences;
  final Function() onSessionExpired;

  AuthInterceptor(this._sharedPreferences, {required this.onSessionExpired});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _sharedPreferences.getString('token');
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    super.onRequest(options, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      await _sharedPreferences.clear(); // Clears all SharedPreferences, including token
      onSessionExpired(); // Navigates to Login, Shows Session Expired Dialog
    }
    super.onError(err, handler);
  }
}
