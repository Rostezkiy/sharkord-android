import 'dart:ui';

import 'parse.dart';
import 'user.dart';

/// a role with its permission set. the client only needs it to colour names and
/// to hide actions the server would refuse anyway.
class Role {
  const Role({
    required this.id,
    required this.name,
    required this.hexColor,
    required this.isDefault,
    required this.permissions,
  });

  final int id;
  final String name;

  /// kept as the raw hex because an all-white role is the default one and should
  /// not tint anybody's name
  final String hexColor;
  final bool isDefault;
  final List<String> permissions;

  static const String defaultHexColor = '#FFFFFF';

  Color get color => parseHexColor(hexColor);

  bool get isTintable =>
      !isDefault && hexColor.toUpperCase() != defaultHexColor;

  bool can(String permission) => permissions.contains(permission);

  factory Role.fromJson(Map<String, dynamic> json) => Role(
    id: asInt(json['id']),
    name: asString(json['name']),
    hexColor: asString(json['color'], fallback: defaultHexColor),
    isDefault: asBool(json['isDefault']),
    permissions: asList(json['permissions'])
        .whereType<String>()
        .toList(growable: false),
  );
}
