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

  const FetchFollowUps({required this.category, this.page = 0, this.size = 10});

  @override
  List<Object?> get props => [category, page, size];
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
