import 'package:flutter/material.dart';

import '../../models/channel.dart';
import '../../state/session_controller.dart';
import '../../theme/app_theme.dart';
import 'user_avatar.dart';

import 'voice_panel.dart';

/// the channel column: the server header, every channel the account may read,
/// grouped by category, and the account's own row at the bottom.
class ChannelSidebar extends StatelessWidget {
  const ChannelSidebar({
    super.key,
    required this.controller,
    this.onChannelSelected,
    this.onVoiceChannelTapped,
  });

  static const double width = 264;

  final SessionController controller;
  final VoidCallback? onChannelSelected;
  final void Function(Channel channel)? onVoiceChannelTapped;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(child: _channelList(context)),
            VoicePanel(controller: controller),
            _ownUserPanel(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              controller.serverName ?? controller.endpoint?.host ?? 'Sharkord',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ),
          _overflowMenu(context),
        ],
      ),
    );
  }

  Widget _overflowMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz_rounded, size: 18),
      color: AppColors.surfaceHigher,
      tooltip: 'Server',
      onSelected: (value) {
        switch (value) {
          case 'change':
            controller.signOut();
          case 'signout':
            controller.signOut(forget: true);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'change',
          child: _menuItem(
            Icons.swap_horiz_rounded,
            'Change server',
            controller.endpoint?.host ?? '',
          ),
        ),
        PopupMenuItem<String>(
          value: 'signout',
          child: _menuItem(
            Icons.logout_rounded,
            'Sign out',
            'Forget this address',
          ),
        ),
      ],
    );
  }

  Widget _menuItem(IconData icon, String label, String hint) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            if (hint.isNotEmpty)
              Text(
                hint,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textFaint,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _channelList(BuildContext context) {
    final textChannels = controller.textChannels;
    final voiceChannels = controller.voiceChannels;
    final categories = controller.orderedCategories;
    final uncategorised = textChannels
        .where((channel) => channel.categoryId == null)
        .toList(growable: false);
    final uncategorisedVoice = voiceChannels
        .where((channel) => channel.categoryId == null)
        .toList(growable: false);

    final children = <Widget>[
      if (uncategorised.isEmpty &&
          uncategorisedVoice.isEmpty &&
          categories.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'This account cannot see any channel yet.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textFaint),
          ),
        ),
      for (final channel in uncategorised) _channelRow(context, channel),
      for (final channel in uncategorisedVoice) ...[
        _channelRow(context, channel),
        ..._voiceMembers(channel),
      ],
      for (final category in categories) ...[
        _categoryLabel(category.name),
        for (final channel in controller.textChannelsIn(category.id))
          _channelRow(context, channel),
        for (final channel in controller.voiceChannelsIn(category.id)) ...[
          _channelRow(context, channel),
          ..._voiceMembers(channel),
        ],
      ],
      if (controller.dmsEnabled &&
          controller.directMessageChannels.isNotEmpty) ...[
        _categoryLabel('Direct messages'),
        for (final channel in controller.directMessageChannels)
          _dmRow(context, channel),
      ],
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 10),
      children: children,
    );
  }

  Widget _categoryLabel(String name) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        name.toUpperCase(),
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.textFaint,
        ),
      ),
    );
  }

  Widget _channelRow(BuildContext context, Channel channel) {
    final isSelected = controller.selectedChannelId == channel.id;
    final unread = controller.unreadFor(channel.id);
    final isVoice = channel.type == ChannelType.voice;

    final isConnectedVoice =
        isVoice && controller.voice.channelId == channel.id;

    return _SidebarRow(
      selected: isSelected,
      trailing: unread > 0
          ? _UnreadBadge(count: unread)
          : (isVoice && controller.voiceMap.countIn(channel.id) > 0
                ? Text(
                    '${controller.voiceMap.countIn(channel.id)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  )
                : null),
      leading: Icon(
        isVoice ? Icons.volume_up_rounded : Icons.tag_rounded,
        size: 17,
        color: isConnectedVoice
            ? AppColors.online
            : (isSelected
                  ? AppColors.text
                  : (unread > 0 ? AppColors.textMuted : AppColors.textFaint)),
      ),
      label: channel.name,
      emphasised: isSelected || unread > 0,
      muted: unread == 0 && !isSelected,
      onTap: () {
        if (isVoice) {
          onVoiceChannelTapped?.call(channel);

          return;
        }

        controller.selectChannel(channel.id);
        onChannelSelected?.call();
      },
    );
  }

  /// the members sitting in a voice channel, indented under it, each with the
  /// microphone and deafen state they are publishing.
  List<Widget> _voiceMembers(Channel channel) {
    final users = controller.voiceMap.usersIn(channel.id);

    return [
      for (final entry in users.entries)
        Padding(
          padding: const EdgeInsets.only(
            left: 44,
            right: 12,
            bottom: 4,
            top: 1,
          ),
          child: Row(
            children: [
              UserAvatar(user: controller.userById(entry.key), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  controller.userById(entry.key)?.name ?? 'unknown',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              if (entry.value.micMuted)
                const Icon(
                  Icons.mic_off_rounded,
                  size: 13,
                  color: AppColors.textFaint,
                ),
              if (entry.value.soundMuted) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.headset_off_rounded,
                  size: 13,
                  color: AppColors.textFaint,
                ),
              ],
            ],
          ),
        ),
    ];
  }

  Widget _dmRow(BuildContext context, Channel channel) {
    final partner = controller.dmPartnerOf(channel);
    final isSelected = controller.selectedChannelId == channel.id;
    final unread = controller.unreadFor(channel.id);

    return _SidebarRow(
      selected: isSelected,
      leading: UserAvatar(user: partner, size: 22, showStatus: true),
      label: partner?.name ?? 'Direct message',
      trailing: unread > 0 ? _UnreadBadge(count: unread) : null,
      emphasised: isSelected || unread > 0,
      muted: unread == 0 && !isSelected,
      onTap: () {
        controller.selectChannel(channel.id);
        onChannelSelected?.call();
      },
    );
  }

  Widget _ownUserPanel(BuildContext context) {
    final ownUser = controller.ownUser;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surfaceHigh,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          UserAvatar(user: ownUser, size: 32, showStatus: true),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ownUser?.name ?? 'Connecting',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                Text(
                  controller.connectionLost ? 'Reconnecting' : 'Online',
                  style: TextStyle(
                    fontSize: 11,
                    color: controller.connectionLost
                        ? AppColors.warning
                        : AppColors.textFaint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarRow extends StatefulWidget {
  const _SidebarRow({
    required this.leading,
    required this.label,
    required this.onTap,
    this.trailing,
    this.selected = false,
    this.emphasised = false,
    this.muted = false,
  });

  final Widget leading;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool selected;
  final bool emphasised;
  final bool muted;

  @override
  State<_SidebarRow> createState() => _SidebarRowState();
}

class _SidebarRowState extends State<_SidebarRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.selected
        ? AppColors.accentSoft
        : (_hovered ? AppColors.surfaceHigher : Colors.transparent);

    final textColor = widget.selected
        ? AppColors.text
        : (widget.muted ? AppColors.textMuted : AppColors.text);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: AppRadius.small,
            ),
            child: Row(
              children: [
                widget.leading,
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: widget.emphasised
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: 6),
                  widget.trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: const BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.all(Radius.circular(9)),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
