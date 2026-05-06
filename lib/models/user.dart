import 'user_role.dart';

class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    required this.role,
    this.phone,
    this.createdAt,
    this.isHost = false,
    this.hostSince,
    this.bio,
    this.responseRate,
    this.responseTime,
  });

  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final UserRole role;
  final String? phone;
  final DateTime? createdAt;

  // Host-related fields
  final bool isHost;
  final DateTime? hostSince;
  final String? bio;
  final int? responseRate; // percentage
  final String? responseTime; // e.g., "within an hour"

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? avatarUrl,
    UserRole? role,
    String? phone,
    DateTime? createdAt,
    bool? isHost,
    DateTime? hostSince,
    String? bio,
    int? responseRate,
    String? responseTime,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      createdAt: createdAt ?? this.createdAt,
      isHost: isHost ?? this.isHost,
      hostSince: hostSince ?? this.hostSince,
      bio: bio ?? this.bio,
      responseRate: responseRate ?? this.responseRate,
      responseTime: responseTime ?? this.responseTime,
    );
  }
}
