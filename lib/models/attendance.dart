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
      id: json['id'].toString(),
      profileId: json['profile'].toString(),
      profileName: json['profile_name'],
      date: DateTime.parse(json['date']),
      timeIn: DateTime.parse(json['time_in']),
      timeOut: json['time_out'] != null ? DateTime.parse(json['time_out']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    final data = {
      'profile': profileId,
      'profile_name': profileName,
      'date': date.toIso8601String(),
      'time_in': timeIn.toIso8601String(),
    };
    
    if (timeOut != null) {
      data['time_out'] = timeOut!.toIso8601String();
    }
    
    return data;
  }
}