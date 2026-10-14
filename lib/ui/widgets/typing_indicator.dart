import 'package:flutter/material.dart';

import '../../state/session_controller.dart';
import '../../theme/app_theme.dart';
import 'user_avatar.dart';

/// "Alice and Bob are typing", shown just above the composer. the dots animate
/// because a static line that never changes looks like a stuck indicator.
class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final channelId = controller.selectedChannelId;
    if (channelId == null) return const SizedBox.shrink();

    final userIds = controller.messages.typingUserIds(channelId);
    if (userIds.isEmpty) return const SizedBox.shrink();

    final names = userIds
        .map((userId) => controller.userById(userId)?.name)
        .whereType<String>()
        .toList(growable: false);

    if (names.isEmpty) return const SizedBox.shrink();

    final label = switch (names.length) {
      1 => '${names.first} is typing',
      2 => '${names.first} and ${names.last} are typing',
      _ => '${names.length} people are typing',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Row(
        children: [
          const _Dots(),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatefulWidget {
  const _Dots();

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _animation.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < 3; index++)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Opacity(
                opacity: _opacityFor(index),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: AppColors.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _opacityFor(int index) {
    final phase = (_animation.value * 3 - index).abs();

    return (1 - phase.clamp(0, 1)) * 0.7 + 0.3;
  }
}

/// the small header above the member list, reused by the sheet a member row
/// opens when tapped.
class MemberRow extends StatelessWidget {
  const MemberRow({
    super.key,
    required this.controller,
    required this.userId,
    this.onTap,
  });

  final SessionController controller;
  final int userId;
  final void Function(int userId)? onTap;

  @override
  Widget build(BuildContext context) {
    final user = controller.userById(userId);
    if (user == null) return const SizedBox.shrink();

    final color = controller.roleColorFor(user);

    return InkWell(
      onTap: onTap == null ? null : () => onTap!(userId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            UserAvatar(user: user, size: 30, showStatus: true),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: user.isOnline ? color : AppColors.textFaint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
