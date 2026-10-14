import 'parse.dart';
import 'server_file.dart';

/// the pre-auth payload of `GET /info`, used to show a server name on the
/// connect screen before anybody signs in.
class ServerInfo {
  const ServerInfo({
    required this.serverId,
    required this.name,
    required this.allowNewUsers,
    this.description,
    this.logo,
    this.version,
    this.oidcEnabled = false,
    this.oidcDisableLocalLogin = false,
  });

  final String serverId;
  final String name;
  final bool allowNewUsers;
  final String? description;
  final ServerFile? logo;
  final String? version;
  final bool oidcEnabled;
  final bool oidcDisableLocalLogin;

  factory ServerInfo.fromJson(Map<String, dynamic> json) => ServerInfo(
    serverId: asString(json['serverId']),
    name: asString(json['name'], fallback: 'Sharkord'),
    allowNewUsers: asBool(json['allowNewUsers'], fallback: true),
    description: asStringOrNull(json['description']),
    logo: json['logo'] == null
        ? null
        : ServerFile.fromJson(asMap(json['logo'])),
    version: asStringOrNull(json['version']),
    oidcEnabled: asBool(json['oidcEnabled']),
    oidcDisableLocalLogin: asBool(json['oidcDisableLocalLogin']),
  );
}
