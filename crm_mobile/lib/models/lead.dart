import 'package:equatable/equatable.dart';

class LeadSource extends Equatable {
  final String id;
  final String name;
  final String category;
  final String description;
  final bool active;

  const LeadSource({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    this.active = true,
  });

  @override
  List<Object?> get props => [id, name, category, description, active];
}

class LeadStatus extends Equatable {
  final String id;
  final String statusName;
  final String color;
  final bool isDefault;
  final bool isClosed;
  final int displayOrder;

  const LeadStatus({
    required this.id,
    required this.statusName,
    required this.color,
    required this.isDefault,
    required this.isClosed,
    required this.displayOrder,
  });

  @override
  List<Object?> get props => [id, statusName, color, isDefault, isClosed, displayOrder];
}

class Lead extends Equatable {
  final String id;
  final String leadNumber;
  final String firstName;
  final String lastName;
  final String companyName;
  final String email;
  final String phone;
  final LeadSource? source;
  final LeadStatus? status;
  final String? priority;
  final String? ownerUserId;
  final String? ownerUserName;
  final DateTime? createdAt;

  const Lead({
    required this.id,
    required this.leadNumber,
    required this.firstName,
    required this.lastName,
    required this.companyName,
    required this.email,
    required this.phone,
    this.source,
    this.status,
    this.priority,
    this.ownerUserId,
    this.ownerUserName,
    this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        leadNumber,
        firstName,
        lastName,
        companyName,
        email,
        phone,
        source,
        status,
        priority,
        ownerUserId,
        ownerUserName,
        createdAt,
      ];
}
