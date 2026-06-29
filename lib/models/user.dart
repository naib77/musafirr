import 'user_role.dart';

/// Registration method for the user account
enum RegistrationMethod { email, phone }

class User {
  const User({
    required this.id,
    required this.name,
    this.email,
    this.avatarUrl,
    required this.role,
    this.phone,
    this.createdAt,
    this.isHost = false,
    this.hostAvailable = true,
    this.hostSince,
    this.bio,
    this.responseRate,
    this.responseTime,
    this.nid,
    this.nidVerified = false,
    this.phoneVerified = false,
    this.registrationMethod,
  });

  final String id;
  final String name;
  final String? email; // Now optional for phone-based registration
  final String? avatarUrl;
  final UserRole role;
  final String? phone;
  final DateTime? createdAt;

  // Host-related fields
  final bool isHost;

  /// Host-wide availability. When false the host is "away" / not accepting new
  /// bookings. Independent of each listing's own visibility.
  final bool hostAvailable;
  final DateTime? hostSince;
  final String? bio;
  final int? responseRate; // percentage
  final String? responseTime; // e.g., "within an hour"

  // Verification fields
  final String? nid; // National ID number
  final bool nidVerified; // NID verification status
  final bool phoneVerified; // Phone verification status
  final RegistrationMethod? registrationMethod; // 'email' or 'phone'

  /// Get the photo URL (alias for avatarUrl)
  String? get photoUrl => avatarUrl;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['full_name'] as String? ?? 'Unknown',
      email: json['email'] as String?,
      avatarUrl: json['avatar_url'] as String? ?? json['photo_url'] as String?,
      role: json['role'] != null
          ? UserRole.values.firstWhere(
              (r) => r.name == json['role'],
              orElse: () => UserRole.guest,
            )
          : UserRole.guest,
      phone: json['phone'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      isHost: json['is_host'] as bool? ?? false,
      hostAvailable: json['is_available'] as bool? ?? true,
      hostSince: json['host_since'] != null
          ? DateTime.parse(json['host_since'] as String)
          : null,
      bio: json['bio'] as String?,
      responseRate: json['response_rate'] as int?,
      responseTime: json['response_time'] as String?,
      nid: json['nid'] as String?,
      nidVerified: json['nid_verified'] as bool? ?? false,
      phoneVerified: json['phone_verified'] as bool? ?? false,
      registrationMethod: json['registration_method'] != null
          ? RegistrationMethod.values.firstWhere(
              (m) => m.name == json['registration_method'],
              orElse: () => RegistrationMethod.email,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'avatar_url': avatarUrl,
      'role': role.name,
      'phone': phone,
      'created_at': createdAt?.toIso8601String(),
      'is_host': isHost,
      'is_available': hostAvailable,
      'host_since': hostSince?.toIso8601String(),
      'bio': bio,
      'response_rate': responseRate,
      'response_time': responseTime,
      'nid': nid,
      'nid_verified': nidVerified,
      'phone_verified': phoneVerified,
      'registration_method': registrationMethod?.name,
    };
  }

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? avatarUrl,
    UserRole? role,
    String? phone,
    DateTime? createdAt,
    bool? isHost,
    bool? hostAvailable,
    DateTime? hostSince,
    String? bio,
    int? responseRate,
    String? responseTime,
    String? nid,
    bool? nidVerified,
    bool? phoneVerified,
    RegistrationMethod? registrationMethod,
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
      hostAvailable: hostAvailable ?? this.hostAvailable,
      hostSince: hostSince ?? this.hostSince,
      bio: bio ?? this.bio,
      responseRate: responseRate ?? this.responseRate,
      responseTime: responseTime ?? this.responseTime,
      nid: nid ?? this.nid,
      nidVerified: nidVerified ?? this.nidVerified,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      registrationMethod: registrationMethod ?? this.registrationMethod,
    );
  }
}
