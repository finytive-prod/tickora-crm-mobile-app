class CalendarEventModel {
  final String id;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime? endTime;
  final String category;
  final String? location;

  CalendarEventModel({
    required this.id,
    required this.title,
    this.description,
    required this.startTime,
    this.endTime,
    required this.category,
    this.location,
  });

  factory CalendarEventModel.fromJson(Map<String, dynamic> json) {
    return CalendarEventModel(
      id: json['id'] ?? '',
      title: json['title'] ?? 'No Title',
      description: json['description'],
      startTime: DateTime.parse(json['startTime']),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      category: json['category'] ?? 'EVENT',
      location: json['location'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'category': category,
      'location': location,
    };
  }
}
