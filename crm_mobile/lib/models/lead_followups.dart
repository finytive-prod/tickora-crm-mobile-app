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

class LeadFollowUpsModel extends LeadFollowUps {
  const LeadFollowUpsModel({
    required super.leadDetails,
    required super.followups,
  });

  factory LeadFollowUpsModel.fromJson(Map<String, dynamic> json) {
    final leadDetails = LeadDetailModel.fromJson(json['leadDetails'] ?? {});
    final List<dynamic> list = json['followups'] ?? [];
    final followups = list.map((e) => FollowUpModel.fromJson(e)).toList();

    return LeadFollowUpsModel(
      leadDetails: leadDetails,
      followups: followups,
    );
  }
}
