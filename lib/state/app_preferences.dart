import 'package:shared_preferences/shared_preferences.dart';

/// the little that has to survive an app restart: where the server is, who was
/// signed in, and (for auto login) the session token the server issued.
class AppPreferences {
  static const String _serverKey = 'server_url';
  static const String _identityKey = 'identity';
  static const String _tokenKey = 'session_token';
  static const String _serverPasswordKey = 'server_passwords';

  String? serverUrl;
  String? identity;
  String? token;

  /// a server may gate joining behind its own password, which is per server and
  /// therefore stored keyed by the address it belongs to.
  final Map<String, String> passwords = <String, String>{};

  Future<void> load() async {
    final store = await SharedPreferences.getInstance();

    serverUrl = store.getString(_serverKey);
    identity = store.getString(_identityKey);
    token = store.getString(_tokenKey);

    passwords.clear();

    for (final entry in store.getKeys()) {
      if (!entry.startsWith('$_serverPasswordKey:')) continue;

      final value = store.getString(entry);
      if (value == null) continue;

      passwords[entry.substring(_serverPasswordKey.length + 1)] = value;
    }
  }

  Future<void> saveSession({
    required String serverUrl,
    required String identity,
    required String token,
  }) async {
    this.serverUrl = serverUrl;
    this.identity = identity;
    this.token = token;

    final store = await SharedPreferences.getInstance();

    await store.setString(_serverKey, serverUrl);
    await store.setString(_identityKey, identity);
    await store.setString(_tokenKey, token);
  }

  Future<void> saveServerUrl(String serverUrl) async {
    this.serverUrl = serverUrl;

    final store = await SharedPreferences.getInstance();

    await store.setString(_serverKey, serverUrl);
  }

  Future<void> saveIdentity(String identity) async {
    this.identity = identity;

    final store = await SharedPreferences.getInstance();

    await store.setString(_identityKey, identity);
  }

  Future<void> saveServerPassword(String serverUrl, String password) async {
    passwords[serverUrl] = password;

    final store = await SharedPreferences.getInstance();

    await store.setString('$_serverPasswordKey:$serverUrl', password);
  }

  /// called when the token is rejected or the user signs out, so a stale token
  /// can never bounce the app back into a failing auto login.
  Future<void> clearToken() async {
    token = null;

    final store = await SharedPreferences.getInstance();

    await store.remove(_tokenKey);
  }
}
