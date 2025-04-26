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
      id: json['_id'],
      name: json['name'],
      email: json['email'],
      bloodGroup: json['bloodGroup'],
      regNumber: json['regNumber'],
      university: json['university'],
      imageUrl: json['imageUrl'],
      registrationDate: DateTime.parse(json['registrationDate']),
      isActive: json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'bloodGroup': bloodGroup,
      'regNumber': regNumber,
      'university': university,
      'imageUrl': imageUrl,
      'registrationDate': registrationDate.toIso8601String(),
      'isActive': isActive,
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
