import 'parse.dart';

/// a row of the server's `files` table, as handed to the client with an
/// optional access token when the server uses signed URLs.
class ServerFile {
  const ServerFile({
    required this.id,
    required this.name,
    required this.originalName,
    required this.mimeType,
    required this.size,
    this.accessToken,
    this.accessTokenExpiresAt,
  });

  final int id;
  final String name;
  final String originalName;
  final String mimeType;
  final int size;
  final String? accessToken;
  final int? accessTokenExpiresAt;

  bool get isImage => mimeType.startsWith('image/');

  factory ServerFile.fromJson(Map<String, dynamic> json) => ServerFile(
    id: asInt(json['id']),
    name: asString(json['name']),
    originalName: asString(json['originalName'], fallback: 'file'),
    mimeType: asString(json['mimeType'], fallback: 'application/octet-stream'),
    size: asInt(json['size']),
    accessToken: asStringOrNull(json['_accessToken']),
    accessTokenExpiresAt: asIntOrNull(json['_accessTokenExpiresAt']),
  );
}
