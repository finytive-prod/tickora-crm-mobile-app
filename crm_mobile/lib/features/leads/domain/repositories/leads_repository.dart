import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../entities/custom_field.dart';
import '../entities/lead.dart';
import '../entities/staff_user.dart';
import '../entities/lead_detail.dart';
import '../entities/activity_lead.dart';
import '../entities/attachment.dart';

abstract class LeadsRepository {
  Future<Either<Failure, List<Lead>>> getLeads(int page, int size, {String? statusId});
  Future<Either<Failure, List<LeadStatus>>> getLeadStatuses();
  Future<Either<Failure, List<LeadSource>>> getLeadSources();
  Future<Either<Failure, List<String>>> getLeadPriorities();
  Future<Either<Failure, List<StaffUser>>> getStaffUsers({String? search});
  Future<Either<Failure, List<CustomField>>> getCustomFieldsForm();
  Future<Either<Failure, List<CustomField>>> getCustomFields();
  Future<Either<Failure, void>> createCustomFields(List<Map<String, dynamic>> fields);
  Future<Either<Failure, void>> updateCustomFields(List<Map<String, dynamic>> fields);
  Future<Either<Failure, void>> reorderLeadStatus(String id, int displayOrder);
  Future<Either<Failure, void>> setDefaultLeadStatus(String id);
  Future<Either<Failure, void>> createLeadStatus(Map<String, dynamic> statusData);
  Future<Either<Failure, List<String>>> getCustomFieldTypes();
  Future<Either<Failure, void>> createLead(Map<String, dynamic> leadData, List<String> filePaths, {String? leadFileName});

  Future<Either<Failure, LeadDetail>> getLeadDetails(String id);
  Future<Either<Failure, AuditLogResponse>> getLeadAuditLogs(String id, {int page = 0, int size = 20});
  Future<Either<Failure, List<Attachment>>> getLeadAttachments(String id);
  Future<Either<Failure, void>> uploadLeadAttachment(String leadId, String filePath);
}
