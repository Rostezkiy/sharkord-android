import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_exception.dart';
import '../../state/session_controller.dart';
import '../../theme/app_theme.dart';

/// the input under the message list. Enter sends on desktop and inserts a line
/// break on a phone, where the send button does the work instead.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.isDesktop,
  });

  final SessionController controller;
  final bool isDesktop;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    _focusNode.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.controller.selectedChannel;
    final channelId = widget.controller.selectedChannelId;

    if (channel == null || channelId == null) return const SizedBox.shrink();

    if (!widget.controller.canSendIn(channelId)) {
      return _noPermission();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: AppRadius.large,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Focus(
                onKeyEvent: _handleKey,
                child: TextField(
                  controller: _text,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 6,
                  onChanged: (_) => widget.controller.notifyTyping(),
                  textInputAction: widget.isDesktop
                      ? TextInputAction.none
                      : TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontSize: 14.5, height: 1.4),
                  decoration: InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    hintText: 'Message ${_label(channel.name, channel.isDm)}',
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: _sending
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      onPressed: _send,
                      tooltip: 'Send',
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.surfaceHigher,
                        padding: const EdgeInsets.all(10),
                      ),
                      icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noPermission() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: AppRadius.large,
          border: Border.all(color: AppColors.border),
        ),
        child: const Text(
          'You do not have permission to send messages here',
          style: TextStyle(fontSize: 13, color: AppColors.textFaint),
        ),
      ),
    );
  }

  String _label(String name, bool isDm) => isDm ? name : '#$name';

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!widget.isDesktop) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey.keyLabel != 'Enter') return KeyEventResult.ignored;

    // shift and enter is the desktop way of asking for a new line
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;

    _send();

    return KeyEventResult.handled;
  }

  void _send() {
    final text = _text.text;
    if (text.trim().isEmpty || _sending) return;

    setState(() => _sending = true);

    widget.controller
        .sendMessage(text)
        .then((_) {
          if (!mounted) return;

          _text.clear();
        })
        .catchError((Object error) {
          if (!mounted) return;

          final message = error is ApiException
              ? error.message
              : 'Could not send the message';

          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        })
        .whenComplete(() {
          if (!mounted) return;

          setState(() => _sending = false);
          _focusNode.requestFocus();
        });
  }
}
