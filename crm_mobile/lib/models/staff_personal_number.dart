class StaffPersonalNumber {
  final String id;
  final String? organizationId;
  final String? userId;
  final String? staffName;
  final String phoneNumber;
  final String contactName;
  final String? notes;
  final bool isActive;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  StaffPersonalNumber({
    required this.id,
    this.organizationId,
    this.userId,
    this.staffName,
    required this.phoneNumber,
    required this.contactName,
    this.notes,
    this.isActive = true,
    this.createdBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
  });

  factory StaffPersonalNumber.fromJson(Map<String, dynamic> json) {
    return StaffPersonalNumber(
      id: json['id']?.toString() ?? '',
      organizationId: json['organizationId']?.toString(),
      userId: json['userId']?.toString(),
      staffName: json['staffName']?.toString(),
      phoneNumber: json['phoneNumber']?.toString() ?? '',
      contactName: json['contactName']?.toString() ?? '',
      notes: json['notes']?.toString(),
      isActive: json['isActive'] == true ||
          json['isActive'] == 1 ||
          json['isActive']?.toString().toLowerCase() == 'true',
      createdBy: json['createdBy']?.toString(),
      updatedBy: json['updatedBy']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'phoneNumber': phoneNumber,
      'contactName': contactName,
      'notes': notes,
      'isActive': isActive,
    };
  }
}
