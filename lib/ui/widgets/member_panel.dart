import 'package:flutter/material.dart';

import '../../state/session_controller.dart';
import '../../theme/app_theme.dart';
import 'typing_indicator.dart';
import 'user_avatar.dart';

/// the member list: everyone who is online first, then everyone else, both
/// alphabetically.
class MemberPanel extends StatelessWidget {
  const MemberPanel({super.key, required this.controller});

  final SessionController controller;

  /// the drawer on a phone holds the same panel, so the width lives here.
  static const double width = 236;

  @override
  Widget build(BuildContext context) {
    final online = controller.orderedUsers
        .where((user) => user.isOnline)
        .toList(growable: false);
    final offline = controller.orderedUsers
        .where((user) => !user.isOnline)
        .toList(growable: false);

    return Container(
      width: 236,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 10, bottom: 16),
          children: [
            if (online.isNotEmpty) _section('Online', online.length),
            for (final user in online)
              MemberRow(
                controller: controller,
                userId: user.id,
                onTap: (userId) => showMemberSheet(context, controller, userId),
              ),
            if (offline.isNotEmpty) _section('Offline', offline.length),
            for (final user in offline)
              MemberRow(
                controller: controller,
                userId: user.id,
                onTap: (userId) => showMemberSheet(context, controller, userId),
              ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Text(
        '$title — $count',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: AppColors.textFaint,
        ),
      ),
    );
  }
}

/// a member's card: who they are, what they hold, and a way to message them when
/// the server allows direct messages.
Future<void> showMemberSheet(
  BuildContext context,
  SessionController controller,
  int userId,
) {
  final user = controller.userById(userId);
  if (user == null) return Future<void>.value();

  final memberRoles = controller.roles
      .where((role) => user.roleIds.contains(role.id))
      .toList(growable: false);

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final canMessage =
          controller.dmsEnabled &&
          userId != controller.ownUserId &&
          !user.banned;

      return AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.large),
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserAvatar(user: user, size: 52, showStatus: true),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: controller.roleColorFor(user),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.banned
                              ? 'Banned'
                              : (user.isOnline ? 'Online' : 'Offline'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (memberRoles.isNotEmpty) ...[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final role in memberRoles)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHigher,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(20),
                          ),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          role.name,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: role.isTintable
                                ? role.color
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (user.bio != null && user.bio!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  user.bio!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          if (canMessage)
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();

                controller.openDirectMessage(userId).catchError((Object _) {});
              },
              child: const Text('Message'),
            ),
        ],
      );
    },
  );
}
