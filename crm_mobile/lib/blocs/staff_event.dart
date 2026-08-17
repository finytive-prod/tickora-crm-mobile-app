import 'package:equatable/equatable.dart';

abstract class StaffEvent extends Equatable {
  const StaffEvent();

  @override
  List<Object?> get props => [];
}

class FetchStaffMembers extends StaffEvent {
  final int page;
  final int size;
  final String status;

  const FetchStaffMembers({this.page = 0, this.size = 20, this.status = 'ACTIVE'});

  @override
  List<Object?> get props => [page, size, status];
}

class LoadMoreStaffMembers extends StaffEvent {
  final int page;
  final int size;
  final String status;

  const LoadMoreStaffMembers({required this.page, this.size = 20, required this.status});

  @override
  List<Object?> get props => [page, size, status];
}

class UpdateStaffMemberEvent extends StaffEvent {
  final String id;
  final Map<String, dynamic> data;

  const UpdateStaffMemberEvent({required this.id, required this.data});

  @override
  List<Object?> get props => [id, data];
}

class ToggleStaffStatusEvent extends StaffEvent {
  final String id;
  final bool isActive;

  const ToggleStaffStatusEvent({required this.id, required this.isActive});

  @override
  List<Object?> get props => [id, isActive];
}
