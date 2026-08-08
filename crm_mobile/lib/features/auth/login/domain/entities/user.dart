import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String accessToken;
  final int expiresIn;
  final String tokenType;
  final String userId;
  final String userName;
  final String role;
  final List<String> privileges;

  const User({
    required this.accessToken,
    required this.expiresIn,
    required this.tokenType,
    required this.userId,
    required this.userName,
    required this.role,
    required this.privileges,
  });

  @override
  List<Object?> get props => [
        accessToken,
        expiresIn,
        tokenType,
        userId,
        userName,
        role,
        privileges,
      ];
}
