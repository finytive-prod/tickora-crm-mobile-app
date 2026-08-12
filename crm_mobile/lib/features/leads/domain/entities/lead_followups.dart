import 'package:equatable/equatable.dart';
import 'lead_detail.dart';
import 'follow_up.dart';

class LeadFollowUps extends Equatable {
  final LeadDetail leadDetails;
  final List<FollowUp> followups;

  const LeadFollowUps({
    required this.leadDetails,
    required this.followups,
  });

  @override
  List<Object?> get props => [leadDetails, followups];
}
