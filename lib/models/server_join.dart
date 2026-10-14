import '../models/channel.dart';
import '../models/dm_conversation.dart';
import '../models/parse.dart';
import '../models/role.dart';
import '../models/server_settings.dart';
import '../models/user.dart';
import '../models/voice.dart';

/// everything `others.joinServer` hands over at login: the whole server state the
/// client renders until the subscriptions start pushing changes into it.
class ServerJoin {
  const ServerJoin({
    required this.ownUserId,
    required this.categories,
    required this.channels,
    required this.users,
    required this.readStates,
    required this.voiceMap,
    required this.settings,
    required this.roles,
    required this.channelPermissions,
    this.ownUserPasswordSet = false,
  });

  final int ownUserId;
  final List<Category> categories;
  final List<Channel> channels;
  final List<User> users;
  final Map<int, int> readStates;
  final VoiceMap voiceMap;
  final ServerSettings settings;
  final List<Role> roles;

  /// channel id to that channel's resolved permission map for this user, which
  /// is what decides whether the composer is offered at all.
  final Map<int, Map<String, bool>> channelPermissions;
  final bool ownUserPasswordSet;

  factory ServerJoin.fromJson(Map<String, dynamic> json) {
    final readStates = <int, int>{};

    for (final entry in asMap(json['readStates']).entries) {
      final channelId = int.tryParse(entry.key);
      if (channelId == null) continue;

      readStates[channelId] = asInt(entry.value);
    }

    return ServerJoin(
      ownUserId: asInt(json['ownUserId']),
      categories: asMapList(json['categories'])
          .map(Category.fromJson)
          .toList(growable: false),
      channels: asMapList(json['channels'])
          .map(Channel.fromJson)
          .toList(growable: false),
      users: asMapList(json['users'])
          .map(User.fromJson)
          .toList(growable: false),
      readStates: readStates,
      voiceMap: VoiceMap.fromJson(json['voiceMap']),
      settings: ServerSettings.fromJson(asMap(json['publicSettings'])),
      roles: asMapList(json['roles'])
          .map(Role.fromJson)
          .toList(growable: false),
      channelPermissions: parseChannelPermissions(json['channelPermissions']),
      ownUserPasswordSet: asBool(json['ownUserPasswordSet']),
    );
  }
}

/// kept here so the DM list can be rebuilt from a join payload without a second
/// model file: `dms.get` returns the same rows the join payload implies.
typedef DmConversations = List<DirectMessageConversation>;
