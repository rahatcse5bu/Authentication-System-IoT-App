class Profile {
  final String id;
  final String name;
  final String email;
  final String bloodGroup;
  final String regNumber;
  final String university;
  final String imageUrl;
  final DateTime registrationDate;
  final bool isActive;

  Profile({
    required this.id,
    required this.name,
    required this.email,
    required this.bloodGroup,
    required this.regNumber,
    required this.university,
    required this.imageUrl,
    required this.registrationDate,
    this.isActive = true,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'].toString(),
      name: json['name'],
      email: json['email'],
      bloodGroup: json['blood_group'],
      regNumber: json['reg_number'],
      university: json['university'],
      imageUrl: json['image'] ?? '',
      registrationDate: DateTime.parse(json['registration_date']),
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'blood_group': bloodGroup,
      'reg_number': regNumber,
      'university': university,
      'image': imageUrl,
      'registration_date': registrationDate.toIso8601String(),
      'is_active': isActive,
    };
  }

  Profile copyWith({
    String? name,
    String? email,
    String? bloodGroup,
    String? regNumber,
    String? university,
    String? imageUrl,
    bool? isActive,
  }) {
    return Profile(
      id: this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      regNumber: regNumber ?? this.regNumber,
      university: university ?? this.university,
      imageUrl: imageUrl ?? this.imageUrl,
      registrationDate: this.registrationDate,
      isActive: isActive ?? this.isActive,
    );
  }
}
