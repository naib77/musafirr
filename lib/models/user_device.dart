/// One device an account has signed in from, as `user_devices` holds it.
///
/// See `docs/DEVICE_SESSIONS.md`. The id is an opaque UUID this device
/// generated for itself — never a hardware identifier, because Android 10+
/// refuses IMEI and serial, iOS's IDFV resets on uninstall, and the web has
/// nothing of the kind.
class UserDevice {
  const UserDevice({
    required this.deviceId,
    required this.platform,
    required this.createdAt,
    required this.lastSeenAt,
    this.label,
    this.model,
    this.appVersion,
    this.revokedAt,
  });

  final String deviceId;
  final String platform;
  final DateTime createdAt;
  final DateTime lastSeenAt;

  /// User-given name. Null until they rename it — `label` is the only column
  /// the client may write, by a column-level grant in migration 123.
  final String? label;

  final String? model;
  final String? appVersion;

  /// Set when the device was signed out. The row is KEPT rather than deleted
  /// so the list can say "signed out on 12 Sep": a device that simply vanishes
  /// reads as data loss.
  final DateTime? revokedAt;

  bool get isActive => revokedAt == null;

  /// Counts against `max_devices_per_user`. Web never does — a browser loses
  /// its id whenever site data is cleared, so it would consume the whole
  /// allowance by itself. Mirrors `fn_enforce_device_limit`.
  bool get countsTowardLimit => isActive && platform != 'web';

  /// What to call it when the user has not. Falls back through what is known
  /// rather than showing a UUID, which names nothing to a human.
  String get displayName {
    final named = label?.trim();
    if (named != null && named.isNotEmpty) return named;
    final knownModel = model?.trim();
    if (knownModel != null && knownModel.isNotEmpty) return knownModel;
    return switch (platform) {
      'android' => 'Android phone',
      'ios' => 'iPhone',
      'web' => 'Web browser',
      _ => 'Unknown device',
    };
  }

  static UserDevice fromJson(Map<String, dynamic> json) => UserDevice(
        deviceId: json['device_id'] as String,
        platform: json['platform'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        lastSeenAt: DateTime.parse(json['last_seen_at'] as String).toLocal(),
        label: json['label'] as String?,
        model: json['model'] as String?,
        appVersion: json['app_version'] as String?,
        revokedAt: json['revoked_at'] == null
            ? null
            : DateTime.parse(json['revoked_at'] as String).toLocal(),
      );
}
