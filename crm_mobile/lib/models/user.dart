import 'dart:convert';
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
      userId: json['userId'] ?? json['id'] ?? decoded['userId'] ?? decoded['sub'] ?? '',
      userName: json['userName'] ?? json['fullName'] ?? json['username'] ?? decoded['fullName'] ?? decoded['name'] ?? decoded['preferred_username'] ?? decoded['username'] ?? decoded['sub'] ?? '',
      role: json['role'] ?? json['roleName'] ?? decoded['role'] ?? '',
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
