import 'package:flutter/material.dart';

import '../../helpers/message_text.dart';
import '../../helpers/time_format.dart';
import '../../models/message.dart';
import '../../models/server_file.dart';
import '../../models/user.dart';
import '../../theme/app_theme.dart';
import 'message_content.dart';
import 'reaction_row.dart';
import 'user_avatar.dart';

/// one message row. grouped messages hide the avatar and the name so a run of
/// messages from the same person reads as one block, the way a chat is expected
/// to look.
class MessageTile extends StatelessWidget {
  const MessageTile({
    super.key,
    required this.message,
    required this.author,
    required this.authorColor,
    required this.baseUrl,
    required this.ownUserId,
    required this.showHeader,
    required this.canReact,
    required this.mentionColor,
    required this.onToggleReaction,
    required this.onOpenFile,
  });

  final Message message;
  final User? author;
  final Color authorColor;
  final String? baseUrl;
  final int ownUserId;
  final bool showHeader;
  final bool canReact;
  final Color? Function(int userId) mentionColor;
  final void Function(Message message, String emoji) onToggleReaction;
  final void Function(ServerFile file) onOpenFile;

  @override
  Widget build(BuildContext context) {
    final text = MessageText.toPlainText(message.content);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: showHeader ? 12 : 2,
        bottom: 1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: showHeader
                ? UserAvatar(user: author, size: 34)
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showHeader) _header(),
                if (message.replyTo != null) _replyPreview(),
                if (text.isNotEmpty)
                  MessageContent(
                    html: message.content,
                    baseUrl: baseUrl,
                    mentionColor: mentionColor,
                  ),
                for (final file in message.files)
                  AttachmentView(file: file, onOpen: onOpenFile),
                ReactionRow(
                  reactions: message.reactions,
                  ownUserId: ownUserId,
                  canReact: canReact,
                  onToggle: (emoji) => onToggleReaction(message, emoji),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              author?.name ?? 'unknown',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: authorColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatMessageTime(message.sentAt),
            style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
          ),
          if (message.editedAt != null) ...[
            const SizedBox(width: 6),
            const Text(
              '(edited)',
              style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
            ),
          ],
        ],
      ),
    );
  }

  Widget _replyPreview() {
    final target = message.replyTo!;
    final snippet = MessageText.toPlainText(target.content);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: AppRadius.small,
        border: Border(left: BorderSide(color: AppColors.accent, width: 2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.reply, size: 12, color: AppColors.textFaint),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              snippet.isEmpty ? 'message' : snippet,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
