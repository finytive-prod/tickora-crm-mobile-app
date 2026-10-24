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
  final String? roleId;
  final bool? isDefault;
  final String? reportingManagerId;
  final int? callTarget;
  final String? callTimeTarget;

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
    this.roleId,
    this.isDefault,
    this.reportingManagerId,
    this.callTarget,
    this.callTimeTarget,
  });

  bool get isSuperAdmin {
    return (isDefault == true) || roles.any((r) {
      final clean = r.toUpperCase().replaceAll(' ', '').replaceAll('_', '');
      return clean.contains('SUPERADMIN');
    });
  }

  bool get isActive {
    if (isSuperAdmin) return true;
    final statusUpper = accountStatus.toUpperCase();
    return statusUpper == 'ACTIVE' || statusUpper == 'ENABLED' || statusUpper == 'TRUE';
  }

  String get initials {
    final parts = fullName.trim().split(' ').where((e) => e.trim().isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return parts.isNotEmpty ? parts.first[0].toUpperCase() : '?';
  }

  String get primaryRole {
    return roles.isNotEmpty ? roles.join(', ') : 'N/A';
  }

  @override
  List<Object?> get props => [
        id,
        organizationId,
        userCode,
        username,
        email,
        phone,
        accountStatus,
        emailVerified,
        phoneVerified,
        lastLogin,
        createdAt,
        updatedAt,
        fullName,
        gender,
        joiningDate,
        designation,
        roles,
        roleId,
        isDefault,
        reportingManagerId,
        callTarget,
        callTimeTarget,
      ];
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
    super.roleId,
    super.isDefault,
    super.reportingManagerId,
    super.callTarget,
    super.callTimeTarget,
  });

  static String _parseAccountStatus(Map<String, dynamic> json, List<String> parsedRoles) {
    final isSuper = (json['isDefault'] == true) || parsedRoles.any((r) {
      final clean = r.toUpperCase().replaceAll(' ', '').replaceAll('_', '');
      return clean.contains('SUPERADMIN');
    });

    if (isSuper) {
      return 'ACTIVE';
    }

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

    if (json['isActive'] == true || json['isActive'] == 'true' || json['isActive'] == 'TRUE' ||
        json['active'] == true || json['active'] == 'true' || json['active'] == 'TRUE') {
      return 'ACTIVE';
    }

    return 'ACTIVE';
  }

  factory StaffMemberModel.fromJson(Map<String, dynamic> json) {
    List<String> parsedRoles = [];
    if (json['roles'] is List) {
      parsedRoles = (json['roles'] as List<dynamic>).map((e) => e.toString()).toList();
    } else if (json['role'] != null) {
      parsedRoles = [json['role'].toString()];
    }

    String fullName = '';
    if (json['fullName'] != null && json['fullName'].toString().isNotEmpty) {
      fullName = json['fullName'].toString();
    } else if (json['name'] != null && json['name'].toString().isNotEmpty) {
      fullName = json['name'].toString();
    } else if (json['username'] != null && json['username'].toString().isNotEmpty) {
      fullName = json['username'].toString();
    }

    String parsedEmail = '';
    if (json['email'] != null && json['email'].toString().trim().isNotEmpty) {
      parsedEmail = json['email'].toString().trim();
    } else if (json['emailId'] != null && json['emailId'].toString().trim().isNotEmpty) {
      parsedEmail = json['emailId'].toString().trim();
    } else if (json['emailAddress'] != null && json['emailAddress'].toString().trim().isNotEmpty) {
      parsedEmail = json['emailAddress'].toString().trim();
    } else if (json['mail'] != null && json['mail'].toString().trim().isNotEmpty) {
      parsedEmail = json['mail'].toString().trim();
    } else if (json['userEmail'] != null && json['userEmail'].toString().trim().isNotEmpty) {
      parsedEmail = json['userEmail'].toString().trim();
    } else if (json['officialEmail'] != null && json['officialEmail'].toString().trim().isNotEmpty) {
      parsedEmail = json['officialEmail'].toString().trim();
    } else if (json['workEmail'] != null && json['workEmail'].toString().trim().isNotEmpty) {
      parsedEmail = json['workEmail'].toString().trim();
    } else if (json['contactEmail'] != null && json['contactEmail'].toString().trim().isNotEmpty) {
      parsedEmail = json['contactEmail'].toString().trim();
    } else if (json['username'] != null && json['username'].toString().contains('@')) {
      parsedEmail = json['username'].toString().trim();
    }

    return StaffMemberModel(
      id: json['id'] ?? '',
      organizationId: json['organizationId'],
      userCode: json['userCode'] ?? '',
      username: json['username'] ?? '',
      email: parsedEmail,
      phone: json['phone'] ?? json['phoneNumber'] ?? '',
      accountStatus: _parseAccountStatus(json, parsedRoles),
      emailVerified: json['emailVerified'] == true,
      phoneVerified: json['phoneVerified'] == true,
      lastLogin: json['lastLogin'],
      createdAt: json['createdAt'] ?? '',
      updatedAt: json['updatedAt'],
      fullName: fullName,
      gender: json['gender'],
      joiningDate: json['joiningDate'],
      designation: json['designation'],
      roles: parsedRoles,
      roleId: json['roleId'],
      isDefault: json['isDefault'] == true,
      reportingManagerId: json['reportingManagerId']?.toString(),
      callTarget: (json['callTarget'] as num?)?.toInt(),
      callTimeTarget: json['callTimeTarget']?.toString(),
    );
  }
}
