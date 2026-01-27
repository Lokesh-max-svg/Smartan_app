class Gym {
  final String address;
  final int capacity;
  final String createdAt;
  final String createdBy;
  final String email;
  final String gymId;
  final String manager;
  final int members;
  final double monthlyRevenue;
  final String name;
  final String organizationId;
  final String organizationName;
  final String phone;
  final String updatedAt;

  Gym({
    required this.address,
    required this.capacity,
    required this.createdAt,
    required this.createdBy,
    required this.email,
    required this.gymId,
    required this.manager,
    required this.members,
    required this.monthlyRevenue,
    required this.name,
    required this.organizationId,
    required this.organizationName,
    required this.phone,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'address': address,
      'capacity': capacity,
      'createdAt': createdAt,
      'createdBy': createdBy,
      'email': email,
      'gymId': gymId,
      'manager': manager,
      'members': members,
      'monthlyRevenue': monthlyRevenue,
      'name': name,
      'organizationId': organizationId,
      'organizationName': organizationName,
      'phone': phone,
      'updatedAt': updatedAt,
    };
  }

  factory Gym.fromJson(Map<String, dynamic> json) {
    return Gym(
      address: json['address'] ?? '',
      capacity: json['capacity'] ?? 0,
      createdAt: json['createdAt'] ?? '',
      createdBy: json['createdBy'] ?? '',
      email: json['email'] ?? '',
      gymId: json['gymId'] ?? '',
      manager: json['manager'] ?? '',
      members: json['members'] ?? 0,
      monthlyRevenue: (json['monthlyRevenue'] ?? 0).toDouble(),
      name: json['name'] ?? '',
      organizationId: json['organizationId'] ?? '',
      organizationName: json['organizationName'] ?? '',
      phone: json['phone'] ?? '',
      updatedAt: json['updatedAt'] ?? '',
    );
  }
}
