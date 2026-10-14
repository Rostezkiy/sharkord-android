import 'package:flutter/material.dart';

import '../../models/channel.dart';
import '../../state/session_controller.dart';
import '../../state/voice_controller.dart';
import '../../theme/app_theme.dart';
import 'composer.dart';
import 'message_list.dart';
import 'typing_indicator.dart';
import 'user_avatar.dart';

/// the right hand side of the app: the channel header, the messages, and the
/// composer, plus the banner shown while the realtime connection is down.
class ChatView extends StatelessWidget {
  const ChatView({
    super.key,
    required this.controller,
    required this.isCompact,
    required this.isDesktop,
    this.onOpenMembers,
    this.onOpenChannels,
    this.membersVisible = true,
  });

  final SessionController controller;
  final bool isCompact;
  final bool isDesktop;
  final VoidCallback? onOpenMembers;
  final VoidCallback? onOpenChannels;
  final bool membersVisible;

  @override
  Widget build(BuildContext context) {
    final channel = controller.selectedChannel;

    if (channel == null) {
      return const _NoChannel();
    }

    return SafeArea(
      child: Column(
        children: [
          _header(context, channel),
          if (controller.connectionLost) _reconnectBanner(context),
          Expanded(child: MessageList(controller: controller)),
          TypingIndicator(controller: controller),
          Composer(controller: controller, isDesktop: isDesktop),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, Channel channel) {
    final partner = channel.isDm ? controller.dmPartnerOf(channel) : null;

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (onOpenChannels != null) ...[
            IconButton(
              onPressed: onOpenChannels,
              tooltip: 'Channels',
              icon: const Icon(Icons.menu_rounded, size: 20),
            ),
            const SizedBox(width: 2),
          ],
          if (partner != null)
            UserAvatar(user: partner, size: 26, showStatus: true)
          else
            Icon(
              channel.type == ChannelType.voice
                  ? Icons.volume_up_rounded
                  : Icons.tag_rounded,
              size: 19,
              color: AppColors.textFaint,
            ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              channel.isDm ? (partner?.name ?? 'Direct message') : channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
          if (channel.topic != null && channel.topic!.isNotEmpty) ...[
            const SizedBox(width: 12),
            const SizedBox(
              height: 18,
              child: VerticalDivider(color: AppColors.border),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                channel.topic!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ] else
            const Spacer(),
          ListenableBuilder(
            listenable: controller.voice,
            builder: (context, _) => _voiceIndicator(),
          ),
          if (onOpenMembers != null)
            IconButton(
              onPressed: onOpenMembers,
              tooltip: membersVisible ? 'Hide members' : 'Show members',
              icon: Icon(
                membersVisible
                    ? Icons.people_alt_rounded
                    : Icons.people_alt_outlined,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }

  Widget _reconnectBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.warning.withValues(alpha: 0.12),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 15,
            color: AppColors.warning,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Connection lost. Trying to reconnect.',
              style: TextStyle(fontSize: 12.5, color: AppColors.warning),
            ),
          ),
          TextButton(
            onPressed: controller.reconnect,
            child: const Text('Retry now'),
          ),
        ],
      ),
    );
  }

  /// a compact reminder that a call is running while a text channel is on
  /// screen: on a phone the voice strip itself lives behind the channel drawer.
  Widget _voiceIndicator() {
    final voice = controller.voice;

    if (!voice.isActive) return const SizedBox.shrink();

    final channelId = voice.channelId;
    final name = channelId == null
        ? 'Voice'
        : (controller.channelById(channelId)?.name ?? 'Voice');
    final isFailed = voice.status == VoiceStatus.failed;
    final isConnecting = voice.isBusy;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFailed ? Icons.error_outline_rounded : Icons.graphic_eq_rounded,
            size: 14,
            color: isFailed
                ? AppColors.danger
                : (isConnecting ? AppColors.warning : AppColors.online),
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          if (voice.micMuted && !isFailed) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.mic_off_rounded,
              size: 13,
              color: AppColors.textFaint,
            ),
          ],
        ],
      ),
    );
  }
}

class _NoChannel extends StatelessWidget {
  const _NoChannel();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.waving_hand_outlined,
              size: 34,
              color: AppColors.textFaint,
            ),
            SizedBox(height: 14),
            Text(
              'Nothing to show yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'No channel of this account is readable. Ask an administrator for access to a text channel.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
