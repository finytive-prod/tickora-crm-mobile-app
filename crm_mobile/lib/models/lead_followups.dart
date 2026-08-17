import 'package:equatable/equatable.dart';
import 'package:crm_mobile/models/lead_detail.dart';
import 'package:crm_mobile/models/follow_up.dart';

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
