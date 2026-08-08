import 'package:dio/dio.dart';

class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Any generic logic on errors can be put here before reaching ErrorHandler.
    super.onError(err, handler);
  }
}
