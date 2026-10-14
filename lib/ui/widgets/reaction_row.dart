import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../theme/app_theme.dart';

/// the reaction chips under a message: one per emoji, with the count and the
/// caller's own reaction highlighted. tapping a chip toggles it, which is the
/// only way to react in this build.
class ReactionRow extends StatelessWidget {
  const ReactionRow({
    super.key,
    required this.reactions,
    required this.ownUserId,
    required this.canReact,
    required this.onToggle,
  });

  final List<MessageReaction> reactions;
  final int ownUserId;
  final bool canReact;
  final void Function(String emoji) onToggle;

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    final grouped = <String, List<MessageReaction>>{};

    for (final reaction in reactions) {
      grouped
          .putIfAbsent(reaction.emoji, () => <MessageReaction>[])
          .add(reaction);
    }

    // shortcode reactions are shown as :name:, unicode ones as themselves
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final entry in grouped.entries)
            _chip(context, entry.key, entry.value),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String emoji,
    List<MessageReaction> users,
  ) {
    final mine = users.any((reaction) => reaction.userId == ownUserId);

    return InkWell(
      onTap: canReact ? () => onToggle(emoji) : null,
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: mine ? AppColors.accentSoft : AppColors.surfaceHigh,
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          border: Border.all(color: mine ? AppColors.accent : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReactionLabel(emoji: emoji),
            const SizedBox(width: 6),
            Text(
              '${users.length}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: mine ? AppColors.accentText : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// reactions are stored as github shortcodes ('fox') or as the character itself
/// for unicode emoji; a shortcode is shown with colons so it reads as a name.
class ReactionLabel extends StatelessWidget {
  const ReactionLabel({super.key, required this.emoji});

  final String emoji;

  static final RegExp _shortcode = RegExp(r'^[a-z0-9_+-]+$');

  @override
  Widget build(BuildContext context) {
    final isShortcode = _shortcode.hasMatch(emoji);

    return Text(
      isShortcode ? ':$emoji:' : emoji,
      style: TextStyle(fontSize: isShortcode ? 12 : 13, color: AppColors.text),
    );
  }
}
