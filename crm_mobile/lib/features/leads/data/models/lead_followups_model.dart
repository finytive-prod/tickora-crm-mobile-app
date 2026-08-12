import '../../domain/entities/lead_followups.dart';
import 'lead_detail_model.dart';
import 'follow_up_model.dart';

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
