import 'dart:convert';
import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_exception.dart';
import 'package:crm_mobile/core/network/error_handler.dart';
import 'package:crm_mobile/models/user.dart';
import 'package:crm_mobile/core/network/api_constants.dart';
import 'package:crm_mobile/core/utils/staff_phone_resolver.dart';

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
      final loginUrl = '${ApiUrl.identityService}/auth/login';

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
        
        // Determine real user name (without hardcoded defaults)
        String name = userModel.userName;
        if (name.isEmpty) {
          name = (decoded['fullName'] ?? decoded['name'] ?? decoded['preferred_username'] ?? decoded['username'] ?? decoded['sub'] ?? '').toString();
        }
        if (name.isEmpty && email.isNotEmpty) {
          name = email.split('@').first;
        }
        if (name.isEmpty) {
          name = 'User';
        }

        // Determine real user email (fallback to the email entered at login)
        String userEmail = (decoded['email'] ?? body['data']['email'] ?? body['data']['username'] ?? '').toString();
        if (userEmail.isEmpty || !userEmail.contains('@')) {
          userEmail = email.trim();
        }

        String userPhone = (decoded['phone'] ?? decoded['phoneNumber'] ?? decoded['mobile'] ?? '').toString();
        if (userPhone.isEmpty) {
          userPhone = (body['data']['phone'] ?? body['data']['phoneNumber'] ?? body['data']['mobile'] ?? body['data']['contactNumber'] ?? '').toString();
        }

        await sharedPreferences.setString('userName', name);
        await sharedPreferences.setString('userEmail', userEmail);
        if (userModel.userId.isNotEmpty) {
          await sharedPreferences.setString('userId', userModel.userId);
        }
        if (userPhone.isNotEmpty) {
          await sharedPreferences.setString('userPhone', userPhone);
        }

        // If phone is still not found, fetch the staff profile to get the phone number
        if (userPhone.isEmpty && userModel.userId.isNotEmpty) {
          _fetchAndSaveStaffPhone(userModel.userId);
        }

        return Right(userModel);
      } else {
        throw ApiException(message: body?['message'] ?? 'Login failed');
      }
    } catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  /// Fetches the current staff member's profile to get their phone number.
  /// This is a fire-and-forget call that runs after login.
  void _fetchAndSaveStaffPhone(String userId) async {
    try {
      await StaffPhoneResolver.getOrFetchStaffPhone(
        apiClient: apiClient,
        prefs: sharedPreferences,
      );
    } catch (e) {
      debugPrint('Failed to fetch staff phone: $e');
    }
  }

  @override
  Future<Either<Failure, void>> verifyMail(String email) async {
    try {
      final verifyUrl = '${ApiUrl.identityService}/auth/verify-mail';

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
    } catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> resetPassword(String email, String currentPassword, String newPassword) async {
    try {
      final resetUrl = '${ApiUrl.identityService}/auth/reset-password';

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
    } catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }
}
