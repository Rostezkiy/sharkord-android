import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/channel.dart';
import '../../state/session_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/channel_sidebar.dart';
import '../widgets/chat_view.dart';
import '../widgets/member_panel.dart';
import '../widgets/user_avatar.dart';

/// the joined server: channels on the left, the conversation in the middle and
/// the member list on the right, collapsing into drawers on a narrow screen.
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  static const double _wideBreakpoint = 760;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _showMembers = true;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @override
  Widget build(BuildContext context) {
    return ServerOrigin(
      baseUrl: widget.controller.serverBaseUrl,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < _wideBreakpoint;

          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: AppColors.background,
            drawer: isCompact ? _drawer() : null,
            endDrawer: isCompact ? _membersDrawer() : null,
            body: isCompact
                ? _compact()
                : Row(
                    children: [
                      ChannelSidebar(
                        controller: widget.controller,
                        onVoiceChannelTapped: _joinVoice,
                      ),
                      Expanded(child: _chat(isCompact: false)),
                      if (_showMembers)
                        MemberPanel(controller: widget.controller),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _compact() {
    return _chat(
      isCompact: true,
      onOpenChannels: () => _scaffoldKey.currentState?.openDrawer(),
      onOpenMembers: () => _scaffoldKey.currentState?.openEndDrawer(),
    );
  }

  Widget _chat({
    required bool isCompact,
    VoidCallback? onOpenChannels,
    VoidCallback? onOpenMembers,
  }) {
    return ChatView(
      controller: widget.controller,
      isCompact: isCompact,
      isDesktop: _isDesktop,
      onOpenChannels: onOpenChannels,
      onOpenMembers:
          onOpenMembers ??
          (isCompact
              ? null
              : () => setState(() => _showMembers = !_showMembers)),
      membersVisible: !isCompact && _showMembers,
    );
  }

  Widget _drawer() {
    return Drawer(
      width: ChannelSidebar.width,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(),
      child: ChannelSidebar(
        controller: widget.controller,
        onChannelSelected: () => Navigator.of(context).pop(),
        onVoiceChannelTapped: _joinVoice,
      ),
    );
  }

  Widget _membersDrawer() {
    return Drawer(
      width: MemberPanel.width,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(),
      child: MemberPanel(controller: widget.controller),
    );
  }

  /// joins a voice channel and reports the reason when it does not work: a
  /// refusal is the one thing the channel list cannot show on its own.
  Future<void> _joinVoice(Channel channel) async {
    final voice = widget.controller.voice;

    if (voice.channelId == channel.id && voice.isInChannel) return;

    await voice.join(channel.id);

    final error = voice.errorMessage;

    if (error == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}
