class FaceImage {
  final String id;
  final String image;
  final DateTime createdAt;

  FaceImage({
    required this.id,
    required this.image,
    required this.createdAt,
  });

  factory FaceImage.fromJson(Map<String, dynamic> json) {
    return FaceImage(
      id: json['id'].toString(),
      image: json['image'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'image': image,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

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
  final List<FaceImage> faceImages;
  final bool hasVoiceSample;

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
    this.faceImages = const [],
    this.hasVoiceSample = false,
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
      faceImages: (json['face_images'] as List?)
          ?.map((faceImage) => FaceImage.fromJson(faceImage))
          .toList() ?? [],
      hasVoiceSample: json['has_voice_sample'] ?? false,
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
      'has_voice_sample': hasVoiceSample,
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
    List<FaceImage>? faceImages,
    bool? hasVoiceSample,
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
      faceImages: faceImages ?? this.faceImages,
      hasVoiceSample: hasVoiceSample ?? this.hasVoiceSample,
    );
  }
}
