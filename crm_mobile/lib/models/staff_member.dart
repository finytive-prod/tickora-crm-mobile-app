import 'package:equatable/equatable.dart';

class StaffMember extends Equatable {
  final String id;
  final String? organizationId;
  final String userCode;
  final String username;
  final String email;
  final String phone;
  final String accountStatus;
  final bool emailVerified;
  final bool phoneVerified;
  final String? lastLogin;
  final String createdAt;
  final String? updatedAt;
  final String fullName;
  final String? gender;
  final String? joiningDate;
  final String? designation;
  final List<String> roles;

  const StaffMember({
    required this.id,
    this.organizationId,
    required this.userCode,
    required this.username,
    required this.email,
    required this.phone,
    required this.accountStatus,
    this.emailVerified = false,
    this.phoneVerified = false,
    this.lastLogin,
    required this.createdAt,
    this.updatedAt,
    required this.fullName,
    this.gender,
    this.joiningDate,
    this.designation,
    required this.roles,
  });

  bool get isActive {
    final statusUpper = accountStatus.toUpperCase();
    return statusUpper == 'ACTIVE' || statusUpper == 'ENABLED' || statusUpper == 'TRUE';
  }

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
  }

  String get primaryRole {
    return roles.isNotEmpty ? roles.first : 'N/A';
  }

  @override
  List<Object?> get props => [id, accountStatus, fullName, email, phone, updatedAt];
}

class StaffMemberModel extends StaffMember {
  const StaffMemberModel({
    required super.id,
    super.organizationId,
    required super.userCode,
    required super.username,
    required super.email,
    required super.phone,
    required super.accountStatus,
    super.emailVerified,
    super.phoneVerified,
    super.lastLogin,
    required super.createdAt,
    super.updatedAt,
    required super.fullName,
    super.gender,
    super.joiningDate,
    super.designation,
    required super.roles,
  });

  static String _parseAccountStatus(Map<String, dynamic> json) {
    if (json['isActive'] == false || json['isActive'] == 'false' || json['isActive'] == 'FALSE') {
      return 'INACTIVE';
    }
    if (json['enabled'] == false || json['enabled'] == 'false' || json['enabled'] == 'FALSE') {
      return 'INACTIVE';
    }

    final rawAccountStatus = json['accountStatus']?.toString();
    if (rawAccountStatus != null && rawAccountStatus.isNotEmpty) {
      final upper = rawAccountStatus.toUpperCase();
      if (upper == 'INACTIVE' || upper == 'DISABLED' || upper == 'DEACTIVATED' || upper == 'FALSE') {
        return 'INACTIVE';
      }
      return rawAccountStatus;
    }

    final rawStatus = json['status']?.toString();
    if (rawStatus != null && rawStatus.isNotEmpty) {
      final upper = rawStatus.toUpperCase();
      if (upper == 'INACTIVE' || upper == 'DISABLED' || upper == 'DEACTIVATED' || upper == 'FALSE') {
        return 'INACTIVE';
      }
      return rawStatus;
    }

    if (json['isActive'] == true || json['isActive'] == 'true' || json['isActive'] == 'TRUE') {
      return 'ACTIVE';
    }

    return 'ACTIVE';
  }

  factory StaffMemberModel.fromJson(Map<String, dynamic> json) {
    return StaffMemberModel(
      id: json['id'] ?? '',
      organizationId: json['organizationId'],
      userCode: json['userCode'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      accountStatus: _parseAccountStatus(json),
      emailVerified: json['emailVerified'] ?? false,
      phoneVerified: json['phoneVerified'] ?? false,
      lastLogin: json['lastLogin'],
      createdAt: json['createdAt'] ?? '',
      updatedAt: json['updatedAt'],
      fullName: json['fullName'] ?? '',
      gender: json['gender'],
      joiningDate: json['joiningDate'],
      designation: json['designation'],
      roles: (json['roles'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}
