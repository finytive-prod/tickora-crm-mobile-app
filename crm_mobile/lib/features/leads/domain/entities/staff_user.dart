class StaffUser {
  final String userId;
  final String name;

  StaffUser({
    required this.userId,
    required this.name,
  });

  factory StaffUser.fromJson(Map<String, dynamic> json) {
    return StaffUser(
      userId: json['userId'],
      name: json['name'],
    );
  }
}
