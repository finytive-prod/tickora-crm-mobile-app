import 'package:equatable/equatable.dart';
import '../../domain/entities/lead.dart';

abstract class LeadsState extends Equatable {
  const LeadsState();

  @override
  List<Object> get props => [];
}

class LeadsInitial extends LeadsState {}

class LeadsLoading extends LeadsState {}

class LeadsLoaded extends LeadsState {
  final List<Lead> leads;
  final List<LeadStatus> statuses;
  final String? selectedStatusId;

  const LeadsLoaded(this.leads, {this.statuses = const [], this.selectedStatusId});

  LeadsLoaded copyWith({
    List<Lead>? leads,
    List<LeadStatus>? statuses,
    String? selectedStatusId,
    bool clearSelectedStatusId = false,
  }) {
    return LeadsLoaded(
      leads ?? this.leads,
      statuses: statuses ?? this.statuses,
      selectedStatusId: clearSelectedStatusId ? null : (selectedStatusId ?? this.selectedStatusId),
    );
  }

  @override
  List<Object> get props => [
    leads, 
    statuses, 
    if (selectedStatusId != null) selectedStatusId!
  ];
}

class LeadsError extends LeadsState {
  final String message;

  const LeadsError(this.message);

  @override
  List<Object> get props => [message];
}
