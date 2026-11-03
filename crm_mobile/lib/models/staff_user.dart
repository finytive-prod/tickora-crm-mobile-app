class StaffUser 
{
  final String userId;
  final String name;
  final String? organizationId;
  final String? userCode;
  final String? role;
  final bool? isDefault;

  StaffUser({
    required this.userId,
    required this.name,
    this.organizationId,
    this.userCode,
    this.role,
    this.isDefault,
  });

  factory StaffUser.fromJson(Map<String, dynamic> json) {
    final rawUserId = json['userId']?.toString() ?? '';
    final id = rawUserId.trim().isNotEmpty
        ? rawUserId
        : (json['id']?.toString() ??
            json['uuid']?.toString() ??
            json['userUuid']?.toString() ??
            '');

    final rawName = json['name']?.toString() ?? '';
    String name = rawName.trim().isNotEmpty
        ? rawName
        : (json['fullName']?.toString() ?? '');
    if (name.trim().isEmpty) {
      name = json['username']?.toString() ??
          json['staffName']?.toString() ??
          '';
    }
    final orgId = json['organizationId']?.toString() ??
        json['orgId']?.toString() ??
        (json['organization'] is Map ? json['organization']['id']?.toString() : null);

    final userCode = json['userCode']?.toString();
    final role = json['role']?.toString();
    final isDefault = json['isDefault'] is bool ? json['isDefault'] as bool : null;

    return StaffUser(
      userId: id.trim(),
      name: name.trim(),
      organizationId: orgId?.trim().isNotEmpty == true ? orgId!.trim() : null,
      userCode: userCode?.trim(),
      role: role?.trim(),
      isDefault: isDefault,
    );
  }
}

