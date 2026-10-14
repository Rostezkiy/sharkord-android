import 'api_exception.dart';

/// a server address typed by the user, kept as one object so the http and
/// websocket URLs can never drift apart.
class ServerEndpoint {
  const ServerEndpoint._(this.httpBase, this.websocketBase, this.host);

  final String httpBase;
  final String websocketBase;
  final String host;

  static ServerEndpoint parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const ApiException('Enter the address of your Sharkord server');
    }

    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';

    final Uri uri;
    try {
      uri = Uri.parse(withScheme);
    } on FormatException {
      throw const ApiException('That does not look like a valid address');
    }

    if (uri.host.isEmpty) {
      throw const ApiException('That does not look like a valid address');
    }

    final isSecure = uri.scheme == 'https' || uri.scheme == 'wss';
    final httpScheme = isSecure ? 'https' : 'http';
    final wsScheme = isSecure ? 'wss' : 'ws';

    // the client only ever talks to the root of the server, so anything after the
    // host is dropped rather than silently producing a 404
    final authority = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;

    return ServerEndpoint._(
      '$httpScheme://$authority',
      '$wsScheme://$authority',
      authority,
    );
  }

  /// the trpc websocket asks for `connectionParams=1` so the server waits for the
  /// token message before it builds a context.
  Uri get websocketUri => Uri.parse(
    '$websocketBase/',
  ).replace(queryParameters: const <String, String>{'connectionParams': '1'});

  Uri resolve(String path) => Uri.parse('$httpBase$path');

  @override
  String toString() => host;
}
