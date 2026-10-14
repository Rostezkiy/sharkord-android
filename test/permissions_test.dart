import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:sharkord_flutter/models/channel.dart';
import 'package:sharkord_flutter/models/role.dart';
import 'package:sharkord_flutter/models/user.dart';
import 'package:sharkord_flutter/state/session_controller.dart';

/// the permission names the server uses, spelled once here so a test that fails
/// because of a typo is a test that fails loudly.
const String sendMessages = 'SEND_MESSAGES';
const String reactToMessages = 'REACT_TO_MESSAGES';

const int ownerRoleId = 1;
const int memberRoleId = 2;

Channel buildChannel({
  required int id,
  bool isDm = false,
  bool isPrivate = false,
}) => Channel(
  id: id,
  type: ChannelType.text,
  name: 'general',
  isDm: isDm,
  position: 0,
  private: isPrivate,
);

User buildUser({required List<int> roleIds}) => User(
  id: 1,
  name: 'me',
  profileColor: const Color(0xFF4B5163),
  status: UserStatus.online,
  roleIds: roleIds,
);

Role buildRole({required int id, required List<String> permissions}) => Role(
  id: id,
  name: 'role $id',
  hexColor: '#FFFFFF',
  isDefault: false,
  permissions: permissions,
);

void main() {
  late SessionController controller;

  setUp(() {
    controller = SessionController()
      ..ownUserId = 1
      ..channels = <Channel>[
        buildChannel(id: 10),
        buildChannel(id: 11, isPrivate: true),
        buildChannel(id: 12, isDm: true, isPrivate: true),
      ]
      ..roles = <Role>[
        buildRole(id: memberRoleId, permissions: <String>[sendMessages]),
      ]
      ..users = <int, User>{
        1: buildUser(roleIds: <int>[memberRoleId]),
      };
  });

  tearDown(() => controller.dispose());

  group('canSendIn', () {
    test('a public channel is writable although the override map lists nothing', () {
      // the join payload only carries explicit overrides and defaults to false,
      // which is exactly what used to lock every public channel
      controller.channelPermissions = <int, Map<String, bool>>{
        10: <String, bool>{sendMessages: false},
      };

      expect(controller.canSendIn(10), isTrue);
    });

    test('a direct message is writable by membership alone', () {
      controller.channelPermissions = <int, Map<String, bool>>{
        12: <String, bool>{sendMessages: false},
      };

      expect(controller.canSendIn(12), isTrue);
    });

    test('a private channel follows the override map', () {
      controller.channelPermissions = <int, Map<String, bool>>{
        11: <String, bool>{sendMessages: false},
      };

      expect(controller.canSendIn(11), isFalse);

      controller.channelPermissions = <int, Map<String, bool>>{
        11: <String, bool>{sendMessages: true},
      };

      expect(controller.canSendIn(11), isTrue);
    });

    test('the owner bypasses the override table', () {
      controller.users = <int, User>{
        1: buildUser(roleIds: <int>[ownerRoleId]),
      };
      controller.channelPermissions = <int, Map<String, bool>>{
        11: <String, bool>{sendMessages: false},
      };

      expect(controller.canSendIn(11), isTrue);
    });

    test('a role without the global permission cannot write anywhere', () {
      controller.roles = <Role>[
        buildRole(id: memberRoleId, permissions: <String>[reactToMessages]),
      ];

      expect(controller.canSendIn(10), isFalse);
      expect(controller.canSendIn(11), isFalse);
    });

    test('a channel that is not loaded is not writable', () {
      expect(controller.canSendIn(99), isFalse);
    });
  });

  group('canReactIn', () {
    test('needs the global reaction permission', () {
      expect(controller.canReactIn(10), isFalse);
    });

    test('a role holding it may react in a visible channel', () {
      controller.roles = <Role>[
        buildRole(id: memberRoleId, permissions: <String>[reactToMessages]),
      ];

      expect(controller.canReactIn(10), isTrue);
    });
  });

  group('parseChannelPermissions', () {
    test('reads the shape the join payload and the update push share', () {
      final parsed = parseChannelPermissions(<String, dynamic>{
        '10': <String, dynamic>{
          'channelId': 10,
          'permissions': <String, dynamic>{
            'SEND_MESSAGES': true,
            'VIEW_CHANNEL': false,
          },
        },
      });

      expect(parsed[10], <String, bool>{
        'SEND_MESSAGES': true,
        'VIEW_CHANNEL': false,
      });
    });

    test('an absent payload is an empty map rather than a crash', () {
      expect(parseChannelPermissions(null), isEmpty);
    });
  });
}
