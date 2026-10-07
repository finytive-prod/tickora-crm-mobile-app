class DialpadLeadSearchResult {
  final bool alreadyMapped;
  final String? leadId;
  final String? leadNumber;
  final String? name;
  final String? initial;
  final String? phone;
  final String? sourceName;
  final String? statusName;
  final String? statusColor;
  final String? assignedToName;
  final String? assignedToRole;
  final String? assignedToInfo;
  final String? createdAt;

  DialpadLeadSearchResult({
    required this.alreadyMapped,
    this.leadId,
    this.leadNumber,
    this.name,
    this.initial,
    this.phone,
    this.sourceName,
    this.statusName,
    this.statusColor,
    this.assignedToName,
    this.assignedToRole,
    this.assignedToInfo,
    this.createdAt,
  });

  factory DialpadLeadSearchResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    if (data != null && data is Map<String, dynamic>) {
      final alreadyMapped = data['alreadyMapped'] == true || data['alreadyMapped'] == 'true';

      String? assignedToName;
      if (data['assignedToName'] != null && data['assignedToName'].toString().trim().isNotEmpty) {
        assignedToName = data['assignedToName'].toString().trim();
      } else if (data['assignedToInfo'] != null && data['assignedToInfo'].toString().trim().isNotEmpty) {
        assignedToName = data['assignedToInfo'].toString().trim();
      } else if (data['ownerName'] != null && data['ownerName'].toString().trim().isNotEmpty) {
        assignedToName = data['ownerName'].toString().trim();
      } else if (data['ownerUserName'] != null && data['ownerUserName'].toString().trim().isNotEmpty) {
        assignedToName = data['ownerUserName'].toString().trim();
      } else if (data['assignedTo'] is String && data['assignedTo'].toString().trim().isNotEmpty) {
        assignedToName = data['assignedTo'].toString().trim();
      } else if (data['assignedTo'] is Map) {
        final val = data['assignedTo']['name'] ?? data['assignedTo']['fullName'] ?? data['assignedTo']['userName'];
        assignedToName = val?.toString().trim();
      } else if (data['owner'] is Map) {
        final val = data['owner']['name'] ?? data['owner']['fullName'] ?? data['owner']['userName'];
        assignedToName = val?.toString().trim();
      }

      String? rawCreatedAt;
      if (data['createdAt'] != null) {
        rawCreatedAt = data['createdAt'].toString();
      } else if (data['createdDate'] != null) {
        rawCreatedAt = data['createdDate'].toString();
      } else if (data['created_at'] != null) {
        rawCreatedAt = data['created_at'].toString();
      } else if (data['creationDate'] != null) {
        rawCreatedAt = data['creationDate'].toString();
      }

      return DialpadLeadSearchResult(
        alreadyMapped: alreadyMapped,
        leadId: data['leadId']?.toString() ?? data['id']?.toString(),
        leadNumber: data['leadNumber']?.toString(),
        name: data['name']?.toString() ?? data['leadName']?.toString(),
        initial: data['initial']?.toString(),
        phone: data['phone']?.toString(),
        sourceName: data['sourceName']?.toString(),
        statusName: data['statusName']?.toString(),
        statusColor: data['statusColor']?.toString(),
        assignedToName: assignedToName,
        assignedToRole: data['assignedToRole']?.toString(),
        assignedToInfo: data['assignedToInfo']?.toString(),
        createdAt: rawCreatedAt,
      );
    }
    return DialpadLeadSearchResult(alreadyMapped: false);
  }
}
