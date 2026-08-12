import 'dart:convert';
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
    final accessToken = json['accessToken'] ?? '';
    final expiresIn = json['expiresIn'] ?? 0;
    final tokenType = json['tokenType'] ?? '';

    Map<String, dynamic> decoded = {};
    if (accessToken.isNotEmpty) {
      try {
        final parts = accessToken.split('.');
        if (parts.length == 3) {
          final payload = parts[1];
          var normalized = base64Url.normalize(payload);
          final resp = utf8.decode(base64Url.decode(normalized));
          decoded = jsonDecode(resp);
        }
      } catch (_) {}
    }

    return UserModel(
      accessToken: accessToken,
      expiresIn: expiresIn,
      tokenType: tokenType,
      userId: json['userId'] ?? decoded['userId'] ?? decoded['sub'] ?? '',
      userName: json['userName'] ?? decoded['name'] ?? '',
      role: json['role'] ?? decoded['role'] ?? '',
      privileges: (json['privileges'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
                  (decoded['privileges'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
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
