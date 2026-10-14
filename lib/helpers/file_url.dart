import '../models/server_file.dart';

/// files are served from the same origin as the websocket, under `/public`, and
/// carry an access token pair when the server signs its URLs.
String? fileUrl(String? serverBaseUrl, ServerFile? file) {
  if (serverBaseUrl == null || file == null || file.name.isEmpty) return null;

  final base = '$serverBaseUrl/public/${Uri.encodeComponent(file.name)}';
  final token = file.accessToken;

  if (token == null) return base;

  final expires = file.accessTokenExpiresAt;

  return expires == null
      ? '$base?accessToken=$token'
      : '$base?accessToken=$token&expires=$expires';
}
