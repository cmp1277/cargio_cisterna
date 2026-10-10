/// Authenticated session with the same absolute 30-minute lifetime as the API client.
class Session {
  const Session({
    required this.token,
    required this.username,
    required this.role,
    required this.expiresAt,
  });

  final String token;
  final String username;
  final String role;
  final DateTime expiresAt;

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  Map<String, dynamic> toJson() => {
    'token': token,
    'username': username,
    'role': role,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  factory Session.fromJson(Map<String, dynamic> json) {
    final token = json['token'];
    final username = json['username'];
    final role = json['role'];
    final expiry = json['expiresAt'];
    if (token is! String ||
        token.trim().isEmpty ||
        username is! String ||
        username.trim().isEmpty ||
        role is! String ||
        role.trim().isEmpty ||
        expiry is! String) {
      throw const FormatException('Datos de sesión inválidos.');
    }
    final expiresAt = DateTime.tryParse(expiry);
    if (expiresAt == null) {
      throw const FormatException('Fecha de sesión inválida.');
    }
    return Session(
      token: token,
      username: username,
      role: role,
      expiresAt: expiresAt,
    );
  }
}
