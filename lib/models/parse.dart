// the server sends untyped JSON, so every model reads its fields through these
// helpers instead of casting inline: a missing or unexpected field becomes a
// sane default rather than a crash on a payload the client did not expect.

Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();

  return const <String, dynamic>{};
}

Map<String, dynamic>? asMapOrNull(Object? value) {
  if (value == null) return null;

  return asMap(value);
}

List<Map<String, dynamic>> asMapList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];

  return value.map(asMap).toList(growable: false);
}

List<Object?> asList(Object? value) {
  if (value is! List) return const <Object?>[];

  return value;
}

List<int> asIntList(Object? value) =>
    asList(value).map((item) => asInt(item)).toList(growable: false);

int asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;

  return fallback;
}

int? asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);

  return null;
}

String asString(Object? value, {String fallback = ''}) {
  if (value is String) return value;
  if (value == null) return fallback;

  return value.toString();
}

String? asStringOrNull(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  if (value == null) return null;

  return value.toString();
}

bool asBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value == 'true';

  return fallback;
}
