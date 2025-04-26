class Attendance {
  final String id;
  final String profileId;
  final String profileName;
  final DateTime date;
  final DateTime timeIn;
  DateTime? timeOut;

  Attendance({
    required this.id,
    required this.profileId,
    required this.profileName,
    required this.date,
    required this.timeIn,
    this.timeOut,
  });

  factory Attendance.fromJson(Map<String, dynamic> json) {
    return Attendance(
      id: json['_id'],
      profileId: json['profileId'],
      profileName: json['profileName'],
      date: DateTime.parse(json['date']),
      timeIn: DateTime.parse(json['timeIn']),
      timeOut: json['timeOut'] != null ? DateTime.parse(json['timeOut']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    final data = {
      'profileId': profileId,
      'profileName': profileName,
      'date': date.toIso8601String(),
      'timeIn': timeIn.toIso8601String(),
    };
    
    if (timeOut != null) {
      data['timeOut'] = timeOut!.toIso8601String();
    }
    
    return data;
  }
}