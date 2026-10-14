import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../helpers/file_url.dart';
import '../../helpers/time_format.dart';
import '../../models/message.dart';
import '../../models/server_file.dart';
import '../../models/user.dart';
import '../../state/session_controller.dart';
import '../../theme/app_theme.dart';
import 'message_tile.dart';

/// the message history of the selected channel: newest at the bottom, older
/// pages loading as the user scrolls up towards the start of the channel.
class MessageList extends StatefulWidget {
  const MessageList({super.key, required this.controller});

  final SessionController controller;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  static const Duration _groupWindow = Duration(minutes: 5);

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);

    // switching channels starts at the newest message, which on a reversed list
    // is offset zero
    if (oldWidget.controller.selectedChannelId !=
        widget.controller.selectedChannelId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) _scrollController.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();

    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    if (widget.controller.selectedChannelId == null) return;

    final position = _scrollController.position;

    // the list is reversed, so the oldest loaded message sits at the far end
    if (position.pixels < position.maxScrollExtent - 320) return;

    widget.controller.loadOlder(widget.controller.selectedChannelId!);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final channelId = controller.selectedChannelId;

    if (channelId == null) {
      return const _EmptyState(
        icon: Icons.forum_outlined,
        title: 'No channel selected',
        subtitle: 'Pick a channel on the left to start reading.',
      );
    }

    final channel = controller.messages.of(channelId);

    if (channel.isLoadingInitial && channel.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (channel.isEmpty && channel.error != null) {
      return _EmptyState(
        icon: Icons.error_outline,
        title: 'Could not load messages',
        subtitle: channel.error!,
      );
    }

    if (channel.isEmpty) {
      return const _EmptyState(
        icon: Icons.chat_bubble_outline,
        title: 'No messages yet',
        subtitle: 'This is the beginning of the channel. Say hello.',
      );
    }

    final rows = _buildRows(controller, channel.messages);

    return SelectionArea(
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        itemCount: rows.length + (channel.isLoadingOlder ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == rows.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final row = rows[rows.length - 1 - index];

          return switch (row) {
            _DividerRow(:final label) => _dayDivider(label),
            _MessageRow(:final message, :final author, :final showHeader) =>
              _tile(controller, message, author, showHeader),
          };
        },
      ),
    );
  }

  Widget _tile(
    SessionController controller,
    Message message,
    User? author,
    bool showHeader,
  ) {
    return MessageTile(
      message: message,
      author: author,
      authorColor: author == null
          ? AppColors.text
          : controller.roleColorFor(author),
      baseUrl: controller.serverBaseUrl,
      ownUserId: controller.ownUserId,
      showHeader: showHeader,
      canReact: controller.canReactIn(message.channelId),
      mentionColor: _mentionColorFor(controller),
      onToggleReaction: controller.toggleReaction,
      onOpenFile: _openFile,
    );
  }

  /// a mention is written in the mentioned member's role colour, the same one
  /// their name carries above the message.
  Color? Function(int userId) _mentionColorFor(SessionController controller) {
    return (userId) {
      final mentioned = controller.userById(userId);

      return mentioned == null ? null : controller.roleColorFor(mentioned);
    };
  }

  void _openFile(ServerFile file) {
    final url = fileUrl(widget.controller.serverBaseUrl, file);
    if (url == null) return;

    unawaited(launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication));
  }

  /// flattens the history into day dividers and message rows, deciding for each
  /// message whether it continues the block above it.
  List<_Row> _buildRows(SessionController controller, List<Message> messages) {
    final rows = <_Row>[];

    for (var index = 0; index < messages.length; index++) {
      final message = messages[index];
      final older = index == 0 ? null : messages[index - 1];
      final sameDay = older != null && _isSameDay(older.sentAt, message.sentAt);

      if (!sameDay) rows.add(_DividerRow(formatDayDivider(message.sentAt)));

      final grouped =
          older != null &&
          sameDay &&
          older.userId == message.userId &&
          message.replyTo == null &&
          message.sentAt.difference(older.sentAt) < _groupWindow;

      rows.add(
        _MessageRow(
          message: message,
          author: controller.userById(message.userId),
          showHeader: !grouped,
        ),
      );
    }

    return rows;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _dayDivider(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppColors.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textFaint,
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppColors.border)),
        ],
      ),
    );
  }
}

sealed class _Row {
  const _Row();
}

class _DividerRow extends _Row {
  const _DividerRow(this.label);

  final String label;
}

class _MessageRow extends _Row {
  const _MessageRow({
    required this.message,
    required this.author,
    required this.showHeader,
  });

  final Message message;
  final User? author;
  final bool showHeader;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: AppColors.textFaint),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
