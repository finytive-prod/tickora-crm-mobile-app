import 'package:dartz/dartz.dart';
import '../../../../../core/error/failure.dart';
import 'package:crm_mobile/models/user.dart';
import 'package:crm_mobile/repositories/login_repository.dart';

class LoginUseCase {
  final LoginRepository repository;

  LoginUseCase(this.repository);

  Future<Either<Failure, User>> call(String email, String password) {
    return repository.login(email, password);
  }
}
