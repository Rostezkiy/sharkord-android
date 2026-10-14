import 'parse.dart';

enum ChannelType {
  text('TEXT'),
  voice('VOICE');

  const ChannelType(this.wire);

  final String wire;

  static ChannelType fromWire(Object? value) {
    final raw = asString(value);

    return ChannelType.values.firstWhere(
      (type) => type.wire == raw,
      orElse: () => ChannelType.text,
    );
  }
}

class Channel {
  const Channel({
    required this.id,
    required this.type,
    required this.name,
    required this.isDm,
    required this.position,
    this.topic,
    this.categoryId,
    this.private = false,
  });

  final int id;
  final ChannelType type;
  final String name;
  final bool isDm;
  final int position;
  final String? topic;
  final int? categoryId;
  final bool private;

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
    id: asInt(json['id']),
    type: ChannelType.fromWire(json['type']),
    name: asString(json['name']),
    isDm: asBool(json['isDm']),
    position: asInt(json['position']),
    topic: asStringOrNull(json['topic']),
    categoryId: asIntOrNull(json['categoryId']),
    private: asBool(json['private']),
  );

  Channel copyWith({
    String? name,
    String? topic,
    int? position,
    int? categoryId,
  }) => Channel(
    id: id,
    type: type,
    name: name ?? this.name,
    isDm: isDm,
    position: position ?? this.position,
    topic: topic ?? this.topic,
    categoryId: categoryId ?? this.categoryId,
    private: private,
  );
}

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.position,
  });

  final int id;
  final String name;
  final int position;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: asInt(json['id']),
    name: asString(json['name']),
    position: asInt(json['position']),
  );
}

/// both the join payload and the permissions update push carry the resolved
/// channel permission map of one user: channel id to that channel's permissions.
/// it holds the explicit overrides only, so a missing key means nothing was
/// granted, which is why it can never be read on its own.
Map<int, Map<String, bool>> parseChannelPermissions(Object? value) {
  final result = <int, Map<String, bool>>{};

  for (final entry in asMap(value).entries) {
    final channelId = int.tryParse(entry.key);
    if (channelId == null) continue;

    final permissions = asMap(asMap(entry.value)['permissions']);

    result[channelId] = <String, bool>{
      for (final permission in permissions.entries)
        permission.key: asBool(permission.value),
    };
  }

  return result;
}
