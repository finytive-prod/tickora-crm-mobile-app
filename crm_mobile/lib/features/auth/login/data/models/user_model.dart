import '../../domain/entities/user.dart';

class UserModel extends User {
  const UserModel({
    required super.accessToken,
    required super.expiresIn,
    required super.tokenType,
    required super.userId,
    required super.userName,
    required super.role,
    required super.privileges,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      accessToken: json['accessToken'] ?? '',
      expiresIn: json['expiresIn'] ?? 0,
      tokenType: json['tokenType'] ?? '',
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? '',
      role: json['role'] ?? '',
      privileges: (json['privileges'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'expiresIn': expiresIn,
      'tokenType': tokenType,
      'userId': userId,
      'userName': userName,
      'role': role,
      'privileges': privileges,
    };
  }
}
