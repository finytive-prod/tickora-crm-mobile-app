import 'package:dartz/dartz.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../../core/error/failure.dart';
import '../../../../../core/network/api_client.dart';
import '../../../../../core/network/api_exception.dart';
import '../../../../../core/network/error_handler.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/login_repository.dart';
import '../models/user_model.dart';

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
      final response = await apiClient.post(
        '/auth/login',
        data: {
          'email': email,
          'password': password,
        },
      );
      
      final body = response.data;
      if (body['status'] == 'SUCCESS' && body['data'] != null) {
        final userModel = UserModel.fromJson(body['data']);
        // Save token on successful login
        await sharedPreferences.setString('token', userModel.accessToken);
        return Right(userModel);
      } else {
        throw ApiException(message: body['message'] ?? 'Login failed');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }
}
