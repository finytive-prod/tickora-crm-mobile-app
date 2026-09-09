import 'package:equatable/equatable.dart';

abstract class FollowUpsEvent extends Equatable {
  const FollowUpsEvent();

  @override
  List<Object?> get props => [];
}

class FetchFollowUps extends FollowUpsEvent {
  final String category;
  final int page;
  final int size;
  final bool isLoadMore;
  final bool isRefresh;
  final String? searchQuery;

  const FetchFollowUps({
    required this.category,
    this.page = 0,
    this.size = 10,
    this.isLoadMore = false,
    this.isRefresh = false,
    this.searchQuery,
  });

  @override
  List<Object?> get props => [category, page, size, isLoadMore, isRefresh, searchQuery];
}

class FetchLeadFollowUps extends FollowUpsEvent {
  final String leadId;

  const FetchLeadFollowUps(this.leadId);

  @override
  List<Object?> get props => [leadId];
}

class UpdateFollowUp extends FollowUpsEvent {
  final String followupId;
  final Map<String, dynamic> updateData;

  const UpdateFollowUp({required this.followupId, required this.updateData});

  @override
  List<Object?> get props => [followupId, updateData];
}

class AddFollowUpEvent extends FollowUpsEvent {
  final String leadId;
  final Map<String, dynamic> data;

  const AddFollowUpEvent({required this.leadId, required this.data});

  @override
  List<Object?> get props => [leadId, data];
}

