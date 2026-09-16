import 'package:equatable/equatable.dart';
import 'package:crm_mobile/models/staff_member.dart';
import 'package:crm_mobile/models/staff_stats.dart';

abstract class StaffState extends Equatable {
  const StaffState();

  @override
  List<Object?> get props => [];
}

class StaffInitial extends StaffState {}

class StaffLoading extends StaffState {}

class StaffLoaded extends StaffState {
  final List<StaffMember> staffMembers;
  final StaffStats? stats;
  final int currentPage;
  final bool hasMore;
  final bool isLoadingMore;
  final String currentStatus;
  final String? searchQuery;

  const StaffLoaded({
    required this.staffMembers,
    this.stats,
    this.currentPage = 0,
    this.hasMore = true,
    this.isLoadingMore = false,
    this.currentStatus = 'ACTIVE',
    this.searchQuery,
  });

  StaffLoaded copyWith({
    List<StaffMember>? staffMembers,
    StaffStats? stats,
    int? currentPage,
    bool? hasMore,
    bool? isLoadingMore,
    String? currentStatus,
    String? searchQuery,
  }) {
    return StaffLoaded(
      staffMembers: staffMembers ?? this.staffMembers,
      stats: stats ?? this.stats,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      currentStatus: currentStatus ?? this.currentStatus,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  @override
  List<Object?> get props => [staffMembers, stats, currentPage, hasMore, isLoadingMore, currentStatus, searchQuery];
}

class StaffError extends StaffState {
  final String message;

  const StaffError(this.message);

  @override
  List<Object?> get props => [message];
}

class StaffUpdateLoading extends StaffState {}

class StaffUpdateSuccess extends StaffState {}

class StaffUpdateError extends StaffState {
  final String message;

  const StaffUpdateError(this.message);

  @override
  List<Object?> get props => [message];
}

class StaffStatusToggled extends StaffState {}

class StaffStatusToggleError extends StaffState {
  final String message;

  const StaffStatusToggleError(this.message);

  @override
  List<Object?> get props => [message];
}

class StaffCreateSuccess extends StaffState {
  final StaffMember member;

  const StaffCreateSuccess(this.member);

  @override
  List<Object?> get props => [member];
}

class StaffCreateError extends StaffState {
  final String message;

  const StaffCreateError(this.message);

  @override
  List<Object?> get props => [message];
}

class StaffDetailLoaded extends StaffState {
  final StaffMember staffMember;

  const StaffDetailLoaded(this.staffMember);

  @override
  List<Object?> get props => [staffMember];
}

class StaffDetailError extends StaffState {
  final String message;

  const StaffDetailError(this.message);

  @override
  List<Object?> get props => [message];
}
