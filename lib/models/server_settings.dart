import 'parse.dart';

/// the public slice of the server settings, delivered with `others.joinServer`.
class ServerSettings {
  const ServerSettings({
    required this.name,
    required this.directMessagesEnabled,
    required this.enableSearch,
    required this.enablePlugins,
    this.description,
  });

  final String name;
  final bool directMessagesEnabled;
  final bool enableSearch;
  final bool enablePlugins;
  final String? description;

  factory ServerSettings.fromJson(Map<String, dynamic> json) => ServerSettings(
    name: asString(json['name'], fallback: 'Sharkord'),
    directMessagesEnabled: asBool(json['directMessagesEnabled']),
    enableSearch: asBool(json['enableSearch']),
    enablePlugins: asBool(json['enablePlugins']),
    description: asStringOrNull(json['description']),
  );
}
