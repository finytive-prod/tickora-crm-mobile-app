import 'package:equatable/equatable.dart';
import '../../domain/entities/follow_up.dart';
import '../../domain/entities/lead_followups.dart';

abstract class FollowUpsState extends Equatable {
  const FollowUpsState();

  @override
  List<Object?> get props => [];
}

class FollowUpsInitial extends FollowUpsState {}

class FollowUpsLoading extends FollowUpsState {}

class FollowUpsLoaded extends FollowUpsState {
  final FollowUpResponse response;

  const FollowUpsLoaded(this.response);

  @override
  List<Object?> get props => [response];
}

class FollowUpsError extends FollowUpsState {
  final String message;

  const FollowUpsError(this.message);

  @override
  List<Object?> get props => [message];
}

class LeadFollowUpsLoading extends FollowUpsState {}

class LeadFollowUpsLoaded extends FollowUpsState {
  final LeadFollowUps leadFollowUps;

  const LeadFollowUpsLoaded(this.leadFollowUps);

  @override
  List<Object?> get props => [leadFollowUps];
}

class LeadFollowUpsError extends FollowUpsState {
  final String message;

  const LeadFollowUpsError(this.message);

  @override
  List<Object?> get props => [message];
}

class UpdateFollowUpLoading extends FollowUpsState {}

class UpdateFollowUpSuccess extends FollowUpsState {}

class UpdateFollowUpError extends FollowUpsState {
  final String message;

  const UpdateFollowUpError(this.message);

  @override
  List<Object?> get props => [message];
}
