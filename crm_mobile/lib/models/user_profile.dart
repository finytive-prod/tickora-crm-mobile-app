class UserProfile {
  final String id;
  final String organizationId;
  final String userCode;
  final String username;
  final String email;
  final String phone;
  final String accountStatus;
  final bool emailVerified;
  final bool phoneVerified;
  final String? lastLogin;
  final String? createdAt;
  final String? updatedAt;
  final String fullName;
  final String? gender;
  final String? joiningDate;
  final String? designation;
  final List<String> roles;
  final String? reportingManagerId;
  final String? reportingManagerName;

  UserProfile({
    required this.id,
    required this.organizationId,
    required this.userCode,
    required this.username,
    required this.email,
    required this.phone,
    required this.accountStatus,
    required this.emailVerified,
    required this.phoneVerified,
    this.lastLogin,
    this.createdAt,
    this.updatedAt,
    required this.fullName,
    this.gender,
    this.joiningDate,
    this.designation,
    required this.roles,
    this.reportingManagerId,
    this.reportingManagerName,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id']?.toString() ?? '',
      organizationId: json['organizationId']?.toString() ?? '',
      userCode: json['userCode']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      accountStatus: json['accountStatus']?.toString() ?? 'ACTIVE',
      emailVerified: json['emailVerified'] as bool? ?? false,
      phoneVerified: json['phoneVerified'] as bool? ?? false,
      lastLogin: json['lastLogin']?.toString(),
      createdAt: json['createdAt']?.toString(),
      updatedAt: json['updatedAt']?.toString(),
      fullName: json['fullName']?.toString() ?? json['username']?.toString() ?? '',
      gender: json['gender']?.toString(),
      joiningDate: json['joiningDate']?.toString(),
      designation: json['designation']?.toString(),
      roles: (json['roles'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      reportingManagerId: json['reportingManagerId']?.toString(),
      reportingManagerName: json['reportingManagerName']?.toString() ??
          (json['reportingManager'] is String
              ? json['reportingManager'].toString()
              : json['reportingManager']?['name']?.toString() ??
                  json['reportingManager']?['fullName']?.toString()) ??
          json['managerName']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'organizationId': organizationId,
        'userCode': userCode,
        'username': username,
        'email': email,
        'phone': phone,
        'accountStatus': accountStatus,
        'emailVerified': emailVerified,
        'phoneVerified': phoneVerified,
        'lastLogin': lastLogin,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'fullName': fullName,
        'gender': gender,
        'joiningDate': joiningDate,
        'designation': designation,
        'roles': roles,
        'reportingManagerId': reportingManagerId,
        'reportingManagerName': reportingManagerName,
      };
}
