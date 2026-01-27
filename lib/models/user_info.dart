class UserInfo {
  final String userId;
  final double heightInCm;
  final double weightInKg;
  final String gymExpertise; // Novice, Intermediate, Strong
  final bool hasHealthIssues;
  final String? healthIssuesDescription;
  final DateTime createdAt;

  UserInfo({
    required this.userId,
    required this.heightInCm,
    required this.weightInKg,
    required this.gymExpertise,
    required this.hasHealthIssues,
    this.healthIssuesDescription,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'heightInCm': heightInCm,
      'weightInKg': weightInKg,
      'gymExpertise': gymExpertise,
      'hasHealthIssues': hasHealthIssues,
      'healthIssuesDescription': healthIssuesDescription,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      userId: json['userId'],
      heightInCm: json['heightInCm'].toDouble(),
      weightInKg: json['weightInKg'].toDouble(),
      gymExpertise: json['gymExpertise'],
      hasHealthIssues: json['hasHealthIssues'],
      healthIssuesDescription: json['healthIssuesDescription'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}
