import 'package:equatable/equatable.dart';
import 'package:crm_mobile/models/lead_detail.dart';
import 'package:crm_mobile/models/follow_up.dart';

class LeadFollowUps extends Equatable {
  final LeadDetail? leadDetails;
  final List<FollowUp> followups;

  const LeadFollowUps({
    this.leadDetails,
    required this.followups,
  });

  @override
  List<Object?> get props => [leadDetails, followups];
}

class LeadFollowUpsModel extends LeadFollowUps {
  const LeadFollowUpsModel({
    super.leadDetails,
    required super.followups,
  });

  factory LeadFollowUpsModel.fromJson(dynamic json) {
    if (json is List) {
      final followups = json.map((e) => FollowUpModel.fromJson(e as Map<String, dynamic>)).toList();
      return LeadFollowUpsModel(
        leadDetails: null,
        followups: followups,
      );
    }

    if (json is Map<String, dynamic>) {
      if (json['data'] != null && json['data'] is Map<String, dynamic> && (json.containsKey('statusCode') || json.containsKey('success'))) {
        return LeadFollowUpsModel.fromJson(json['data']);
      }
      if (json['data'] != null && json['data'] is List) {
        return LeadFollowUpsModel.fromJson(json['data']);
      }

      LeadDetail? leadDetails;
      if (json['leadDetails'] != null && json['leadDetails'] is Map<String, dynamic>) {
        leadDetails = LeadDetailModel.fromJson(json['leadDetails']);
      }

      List<FollowUp> followups = [];
      if (json['content'] != null && json['content'] is List) {
        final List<dynamic> list = json['content'];
        followups = list
            .map((e) => FollowUpModel.fromJson(e as Map<String, dynamic>))
            .where((f) => f.isRealFollowUp)
            .toList();
      } else if (json['followups'] != null && json['followups'] is List) {
        final List<dynamic> list = json['followups'];
        followups = list
            .map((e) => FollowUpModel.fromJson(e as Map<String, dynamic>))
            .where((f) => f.isRealFollowUp)
            .toList();
      } else if (json.containsKey('id') || json.containsKey('leadId') || json.containsKey('followUpDate')) {
        final f = FollowUpModel.fromJson(json);
        if (f.isRealFollowUp) {
          followups = [f];
        }
      }

      return LeadFollowUpsModel(
        leadDetails: leadDetails,
        followups: followups,
      );
    }

    return const LeadFollowUpsModel(
      leadDetails: null,
      followups: [],
    );
  }
}
