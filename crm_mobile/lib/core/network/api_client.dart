import 'package:dio/dio.dart';

abstract class ApiClient {
  Future<Response> get(String url, {Map<String, dynamic>? queryParameters, Options? options, CancelToken? cancelToken, ProgressCallback? onReceiveProgress});
  
  Future<Response> post(String url, {dynamic data, Map<String, dynamic>? queryParameters, Options? options, CancelToken? cancelToken, ProgressCallback? onSendProgress, ProgressCallback? onReceiveProgress});
  
  Future<Response> put(String url, {dynamic data, Map<String, dynamic>? queryParameters, Options? options, CancelToken? cancelToken, ProgressCallback? onSendProgress, ProgressCallback? onReceiveProgress});
  
  Future<Response> patch(String url, {dynamic data, Map<String, dynamic>? queryParameters, Options? options, CancelToken? cancelToken, ProgressCallback? onSendProgress, ProgressCallback? onReceiveProgress});
  
  Future<Response> delete(String url, {dynamic data, Map<String, dynamic>? queryParameters, Options? options, CancelToken? cancelToken});
  
  Future<Response> download(String urlPath, dynamic savePath, {ProgressCallback? onReceiveProgress, Map<String, dynamic>? queryParameters, CancelToken? cancelToken, bool deleteOnError = true, String lengthHeader = Headers.contentLengthHeader, dynamic data, Options? options});
}
