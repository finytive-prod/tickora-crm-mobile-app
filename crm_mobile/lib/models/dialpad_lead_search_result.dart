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
  });

  factory DialpadLeadSearchResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    if (data != null && data is Map<String, dynamic>) {
      final alreadyMapped = data['alreadyMapped'] == true || data['alreadyMapped'] == 'true';
      return DialpadLeadSearchResult(
        alreadyMapped: alreadyMapped,
        leadId: data['leadId']?.toString(),
        leadNumber: data['leadNumber']?.toString(),
        name: data['name']?.toString(),
        initial: data['initial']?.toString(),
        phone: data['phone']?.toString(),
        sourceName: data['sourceName']?.toString(),
        statusName: data['statusName']?.toString(),
        statusColor: data['statusColor']?.toString(),
        assignedToName: data['assignedToName']?.toString(),
        assignedToRole: data['assignedToRole']?.toString(),
        assignedToInfo: data['assignedToInfo']?.toString(),
      );
    }
    return DialpadLeadSearchResult(alreadyMapped: false);
  }
}
