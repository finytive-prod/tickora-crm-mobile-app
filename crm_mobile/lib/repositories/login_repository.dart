import 'dart:convert';
import 'package:dartz/dartz.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_exception.dart';
import 'package:crm_mobile/core/network/error_handler.dart';
import 'package:crm_mobile/models/user.dart';
import 'package:crm_mobile/models/user_model.dart';

abstract class LoginRepository {
  Future<Either<Failure, User>> login(String email, String password);
  Future<Either<Failure, void>> verifyMail(String email);
  Future<Either<Failure, void>> resetPassword(String email, String currentPassword, String newPassword);
}

class LoginRepositoryImpl implements LoginRepository {
  final ApiClient apiClient;
  final SharedPreferences sharedPreferences;

  LoginRepositoryImpl({
    required this.apiClient,
    required this.sharedPreferences,
  });

  @override
  Future<Either<Failure, User>> login(String email, String password) async {
    try {
      final baseUrl = dotenv.env['BASE_URL'] ?? '';
      String loginUrl = baseUrl;
      if (baseUrl.contains('/api/crm/lead-service')) {
        loginUrl = baseUrl.replaceAll('/api/crm/lead-service', '/api/crm/identity-service/auth/login');
      } else {
        final uri = Uri.parse(baseUrl);
        loginUrl = '${uri.scheme}://${uri.host}:${uri.port}/api/crm/identity-service/auth/login';
      }

      final response = await apiClient.post(
        loginUrl,
        data: {
          'username': email,
          'password': password,
        },
      );
      
      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final userModel = UserModel.fromJson(body['data']);
        // Save token on successful login
        await sharedPreferences.setString('token', userModel.accessToken);
        
        // Extract userName and email from JWT
        Map<String, dynamic> decoded = {};
        try {
          final parts = userModel.accessToken.split('.');
          if (parts.length == 3) {
            final payload = parts[1];
            var normalized = base64Url.normalize(payload);
            final resp = utf8.decode(base64Url.decode(normalized));
            decoded = jsonDecode(resp);
          }
        } catch (_) {}
        
        final name = userModel.userName.isNotEmpty ? userModel.userName : (decoded['name'] ?? 'Ezhil Kumar');
        final userEmail = decoded['email'] ?? 'admin@lumen.io';
        await sharedPreferences.setString('userName', name);
        await sharedPreferences.setString('userEmail', userEmail);

        return Right(userModel);
      } else {
        throw ApiException(message: body?['message'] ?? 'Login failed');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> verifyMail(String email) async {
    try {
      final baseUrl = dotenv.env['BASE_URL'] ?? '';
      String verifyUrl = baseUrl;
      if (baseUrl.contains('/api/crm/lead-service')) {
        verifyUrl = baseUrl.replaceAll('/api/crm/lead-service', '/api/crm/identity-service/auth/verify-mail');
      } else {
        final uri = Uri.parse(baseUrl);
        verifyUrl = '${uri.scheme}://${uri.host}:${uri.port}/api/crm/identity-service/auth/verify-mail';
      }

      final response = await apiClient.post(
        verifyUrl,
        data: {
          'email': email,
        },
      );
      
      final body = response.data;
      if (body != null && (body['success'] == true || response.statusCode == 200)) {
        return const Right(null);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to send reset link');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> resetPassword(String email, String currentPassword, String newPassword) async {
    try {
      final baseUrl = dotenv.env['BASE_URL'] ?? '';
      String resetUrl = baseUrl;
      if (baseUrl.contains('/api/crm/lead-service')) {
        resetUrl = baseUrl.replaceAll('/api/crm/lead-service', '/api/crm/identity-service/auth/reset-password');
      } else {
        final uri = Uri.parse(baseUrl);
        resetUrl = '${uri.scheme}://${uri.host}:${uri.port}/api/crm/identity-service/auth/reset-password';
      }

      final response = await apiClient.post(
        resetUrl,
        data: {
          'email': email,
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
      );
      
      final body = response.data;
      if (body != null && (body['success'] == true || response.statusCode == 200)) {
        return const Right(null);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to reset password');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }
}
