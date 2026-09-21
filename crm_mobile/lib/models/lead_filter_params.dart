import 'package:equatable/equatable.dart';

class LeadFilterParams extends Equatable {
  final List<String> sourceIds;
  final List<String> statusIds;
  final List<String> priorities; // 'LOW', 'MEDIUM', 'HIGH'
  final List<String> createdByIds;
  final List<String> assignedToIds;
  final String? startDate; // YYYY-MM-DD
  final String? endDate;   // YYYY-MM-DD
  final String? search;

  const LeadFilterParams({
    this.sourceIds = const [],
    this.statusIds = const [],
    this.priorities = const [],
    this.createdByIds = const [],
    this.assignedToIds = const [],
    this.startDate,
    this.endDate,
    this.search,
  });

  bool get hasActiveFilters =>
      sourceIds.isNotEmpty ||
      statusIds.isNotEmpty ||
      priorities.isNotEmpty ||
      createdByIds.isNotEmpty ||
      assignedToIds.isNotEmpty ||
      (startDate != null && startDate!.isNotEmpty) ||
      (endDate != null && endDate!.isNotEmpty);

  int get activeFilterCount {
    int count = 0;
    if (sourceIds.isNotEmpty) count += sourceIds.length;
    if (statusIds.isNotEmpty) count += statusIds.length;
    if (priorities.isNotEmpty) count += priorities.length;
    if (createdByIds.isNotEmpty) count += createdByIds.length;
    if (assignedToIds.isNotEmpty) count += assignedToIds.length;
    if (startDate != null && startDate!.isNotEmpty) count++;
    if (endDate != null && endDate!.isNotEmpty) count++;
    return count;
  }

  Map<String, dynamic> toJson() {
    return {
      if (sourceIds.isNotEmpty) "sourceIds": sourceIds,
      if (statusIds.isNotEmpty) "statusIds": statusIds,
      if (priorities.isNotEmpty) "priorities": priorities,
      if (createdByIds.isNotEmpty) "createdByIds": createdByIds,
      if (assignedToIds.isNotEmpty) "assignedToIds": assignedToIds,
      if (startDate != null && startDate!.isNotEmpty) "startDate": startDate,
      if (endDate != null && endDate!.isNotEmpty) "endDate": endDate,
      if (search != null && search!.trim().isNotEmpty) "search": search!.trim(),
    };
  }

  LeadFilterParams copyWith({
    List<String>? sourceIds,
    List<String>? statusIds,
    List<String>? priorities,
    List<String>? createdByIds,
    List<String>? assignedToIds,
    String? startDate,
    bool clearStartDate = false,
    String? endDate,
    bool clearEndDate = false,
    String? search,
    bool clearSearch = false,
  }) {
    return LeadFilterParams(
      sourceIds: sourceIds ?? this.sourceIds,
      statusIds: statusIds ?? this.statusIds,
      priorities: priorities ?? this.priorities,
      createdByIds: createdByIds ?? this.createdByIds,
      assignedToIds: assignedToIds ?? this.assignedToIds,
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      search: clearSearch ? null : (search ?? this.search),
    );
  }

  @override
  List<Object?> get props => [
        sourceIds,
        statusIds,
        priorities,
        createdByIds,
        assignedToIds,
        startDate,
        endDate,
        search,
      ];
}
