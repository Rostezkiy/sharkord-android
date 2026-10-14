import 'dart:ui';

import 'parse.dart';
import 'server_file.dart';

enum UserStatus {
  online('online'),
  idle('idle'),
  offline('offline');

  const UserStatus(this.wire);

  final String wire;

  static UserStatus fromWire(Object? value) {
    final raw = asString(value);

    return UserStatus.values.firstWhere(
      (status) => status.wire == raw,
      orElse: () => UserStatus.offline,
    );
  }
}

/// a public user, as sent by `others.joinServer` and the user subscriptions.
/// the identity is deliberately not part of this model: the server never sends
/// it to anybody but the user themself, and the client has no use for it.
class User {
  const User({
    required this.id,
    required this.name,
    required this.profileColor,
    required this.status,
    required this.roleIds,
    this.bio,
    this.avatar,
    this.banner,
    this.banned = false,
  });

  final int id;
  final String name;
  final Color profileColor;
  final UserStatus status;
  final List<int> roleIds;
  final String? bio;
  final ServerFile? avatar;
  final ServerFile? banner;
  final bool banned;

  bool get isOnline => status != UserStatus.offline;

  String get initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';

    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();

    final first = parts.first.substring(0, 1).toUpperCase();
    final last = parts.last.substring(0, 1).toUpperCase();

    return '$first$last';
  }

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: asInt(json['id']),
    name: asString(json['name'], fallback: 'unknown'),
    profileColor: parseHexColor(json['profileColor']),
    status: UserStatus.fromWire(json['status']),
    roleIds: asIntList(json['roleIds']),
    bio: asStringOrNull(json['bio']),
    avatar: json['avatar'] == null
        ? null
        : ServerFile.fromJson(asMap(json['avatar'])),
    banner: json['banner'] == null
        ? null
        : ServerFile.fromJson(asMap(json['banner'])),
    banned: asBool(json['banned']),
  );

  User copyWith({UserStatus? status, String? name, String? bio}) => User(
    id: id,
    name: name ?? this.name,
    profileColor: profileColor,
    status: status ?? this.status,
    roleIds: roleIds,
    bio: bio ?? this.bio,
    avatar: avatar,
    banner: banner,
    banned: banned,
  );
}

const Color fallbackProfileColor = Color(0xFF4B5163);

Color parseHexColor(Object? value) {
  final raw = asStringOrNull(value);
  if (raw == null) return fallbackProfileColor;

  var hex = raw.replaceFirst('#', '').trim();
  if (hex.length == 3) {
    hex = hex.split('').map((char) => '$char$char').join();
  }

  if (hex.length != 6) return fallbackProfileColor;

  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return fallbackProfileColor;

  return Color(0xFF000000 | parsed);
}
