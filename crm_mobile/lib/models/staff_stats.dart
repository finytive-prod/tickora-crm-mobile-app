import 'package:equatable/equatable.dart';

class StaffStats extends Equatable {
  final int activeMembers;
  final int inactiveMembers;
  final int totalMembers;

  const StaffStats({
    required this.activeMembers,
    required this.inactiveMembers,
    required this.totalMembers,
  });

  factory StaffStats.fromJson(Map<String, dynamic> json) {
    return StaffStats(
      activeMembers: json['activeMembers'] ?? 0,
      inactiveMembers: json['inactiveMembers'] ?? 0,
      totalMembers: json['totalMembers'] ?? 0,
    );
  }

  @override
  List<Object?> get props => [activeMembers, inactiveMembers, totalMembers];
}
