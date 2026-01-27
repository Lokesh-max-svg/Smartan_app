class LoginResponse {
  final String access;
  final String refresh;
  final String userId;
  final String email;
  final String username;

  LoginResponse({
    required this.access,
    required this.refresh,
    required this.userId,
    required this.email,
    required this.username,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      access: json['access'],
      refresh: json['refresh'],
      userId: json['user']['id'].toString(),
      email: json['user']['email'],
      username: json['user']['username'],
    );
  }
}
