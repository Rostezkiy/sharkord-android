import 'package:flutter/material.dart';

import '../../state/session_controller.dart';
import '../../state/voice_controller.dart';
import '../../theme/app_theme.dart';

/// the strip at the bottom of the channel column, above the account row: which
/// voice channel the call is in, what the session is doing, and the microphone,
/// deafen and disconnect buttons. Nothing is drawn while not in a call.
class VoicePanel extends StatelessWidget {
  const VoicePanel({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.voice,
      builder: (context, _) => _panel(context),
    );
  }

  Widget _panel(BuildContext context) {
    final voice = controller.voice;

    if (!voice.isActive) return const SizedBox.shrink();

    final channelId = voice.channelId;
    final channel = channelId == null
        ? null
        : controller.channelById(channelId);
    final isFailed = voice.status == VoiceStatus.failed;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: const BoxDecoration(
        color: AppColors.surfaceHigh,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _statusDot(voice),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  channel?.name ?? 'Voice',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (!isFailed) ...[
                _VoiceButton(
                  icon: voice.micMuted
                      ? Icons.mic_off_rounded
                      : Icons.mic_rounded,
                  tooltip: voice.micMuted ? 'Unmute' : 'Mute',
                  active: !voice.micMuted,
                  onPressed: voice.toggleMic,
                ),
                _VoiceButton(
                  icon: voice.soundMuted
                      ? Icons.headset_off_rounded
                      : Icons.headset_rounded,
                  tooltip: voice.soundMuted ? 'Undeafen' : 'Deafen',
                  active: !voice.soundMuted,
                  onPressed: voice.toggleSound,
                ),
              ],
              _VoiceButton(
                icon: isFailed ? Icons.close_rounded : Icons.call_end_rounded,
                tooltip: isFailed ? 'Dismiss' : 'Disconnect',
                active: false,
                danger: true,
                onPressed: isFailed ? voice.dismissError : voice.leave,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 6, top: 4),
            child: Text(
              _subtitle(voice),
              style: TextStyle(fontSize: 11.5, color: _subtitleColor(voice)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusDot(VoiceController voice) {
    final color = switch (voice.status) {
      VoiceStatus.connected => AppColors.online,
      VoiceStatus.connecting => AppColors.warning,
      VoiceStatus.failed => AppColors.danger,
      VoiceStatus.idle => AppColors.textFaint,
    };

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  String _subtitle(VoiceController voice) {
    if (voice.status == VoiceStatus.failed) {
      return voice.errorMessage ?? 'The call could not be started';
    }

    if (voice.isBusy) {
      final detail = voice.detail;

      return detail == null ? 'Connecting' : 'Connecting: $detail';
    }

    final micError = voice.micError;
    if (micError != null) return micError;

    final channelId = voice.channelId;
    final inCall = channelId == null
        ? 0
        : controller.voiceMap.countIn(channelId);
    final others = inCall > 0 ? inCall - 1 : 0;
    final streams = voice.remoteStreamCount;
    final suffix = streams == 1 ? 'stream' : 'streams';

    return 'Connected · $others others · $streams $suffix';
  }

  Color _subtitleColor(VoiceController voice) {
    if (voice.status == VoiceStatus.failed) return AppColors.danger;
    if (voice.micError != null) return AppColors.warning;
    if (voice.isBusy) return AppColors.textMuted;

    return AppColors.textFaint;
  }
}

class _VoiceButton extends StatelessWidget {
  const _VoiceButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? AppColors.danger
        : (active ? AppColors.text : AppColors.textMuted);

    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: 17,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: color),
    );
  }
}
