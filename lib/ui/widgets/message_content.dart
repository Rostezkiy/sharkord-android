import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../helpers/message_text.dart';
import '../../theme/app_theme.dart';

/// renders the small html subset the server allows into a message: paragraphs,
/// line breaks, bold, italic, code, links, mentions and inline emoji.
///
/// stateful only because link spans need a gesture recognizer that gets
/// disposed, which a stateless widget cannot own.
class MessageContent extends StatefulWidget {
  const MessageContent({
    super.key,
    required this.html,
    this.baseUrl,
    this.mentionColor,
  });

  final String? html;
  final String? baseUrl;
  final Color? Function(int userId)? mentionColor;

  @override
  State<MessageContent> createState() => _MessageContentState();
}

class _MessageContentState extends State<MessageContent> {
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();

    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }

    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final parser = _MessageHtmlParser(
      baseUrl: widget.baseUrl,
      mentionColor: widget.mentionColor,
      onLink: _openLink,
      recognizers: _recognizers,
    );

    return Text.rich(
      TextSpan(children: parser.parse(widget.html ?? ''), style: _base),
      softWrap: true,
    );
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

const TextStyle _base = TextStyle(
  fontSize: 14.5,
  height: 1.45,
  color: AppColors.text,
);

const TextStyle _bold = TextStyle(fontWeight: FontWeight.w700);
const TextStyle _italic = TextStyle(fontStyle: FontStyle.italic);
const TextStyle _code = TextStyle(
  fontFamily: 'monospace',
  fontSize: 13.5,
  backgroundColor: AppColors.surfaceHigher,
);
const TextStyle _link = TextStyle(
  color: AppColors.accentText,
  decoration: TextDecoration.underline,
  decorationColor: AppColors.accentText,
);
const TextStyle _mention = TextStyle(
  color: AppColors.accentText,
  fontWeight: FontWeight.w600,
  backgroundColor: AppColors.accentSoft,
);

class _Frame {
  const _Frame({this.style = const TextStyle(), this.href});

  final TextStyle style;

  /// set for <a>, so the text inside becomes tappable
  final String? href;

  TextStyle applyTo(TextStyle base) => base.merge(style);
}

class _MessageHtmlParser {
  _MessageHtmlParser({
    required this.baseUrl,
    required this.mentionColor,
    required this.onLink,
    required this.recognizers,
  });

  final String? baseUrl;
  final Color? Function(int userId)? mentionColor;
  final Future<void> Function(String url) onLink;
  final List<TapGestureRecognizer> recognizers;

  static final RegExp _tagPattern = RegExp(r'<[^>]*>');
  static final RegExp _attributePattern = RegExp(r'([\w-]+)\s*=\s*"([^"]*)"');

  final List<InlineSpan> _spans = <InlineSpan>[];
  final List<_Frame> _frames = <_Frame>[];

  List<InlineSpan> parse(String html) {
    _spans.clear();
    _frames.clear();
    _frames.add(const _Frame());

    var index = 0;

    for (final match in _tagPattern.allMatches(html)) {
      if (match.start > index) _text(html.substring(index, match.start));

      _tag(match.group(0)!);
      index = match.end;
    }

    if (index < html.length) _text(html.substring(index));

    return List<InlineSpan>.of(_spans);
  }

  TextStyle get _style {
    var style = _base;

    for (final frame in _frames) {
      style = frame.applyTo(style);
    }

    return style;
  }

  String? get _href {
    for (final frame in _frames.reversed) {
      if (frame.href != null) return frame.href;
    }

    return null;
  }

  bool get _endsWithBreak {
    if (_spans.isEmpty) return true;

    final last = _spans.last;
    if (last is! TextSpan) return false;

    final text = last.text;

    return text != null && text.endsWith('\n');
  }

  void _break() {
    if (_endsWithBreak) return;

    _spans.add(const TextSpan(text: '\n'));
  }

  void _text(String raw) {
    if (raw.isEmpty) return;

    final decoded = MessageText.unescape(raw);
    if (decoded.isEmpty) return;

    final href = _href;

    if (href == null) {
      _spans.add(TextSpan(text: decoded, style: _style));

      return;
    }

    _spans.add(
      TextSpan(text: decoded, style: _style, recognizer: _recognizer(href)),
    );
  }

  TapGestureRecognizer _recognizer(String url) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () {
        onLink(url);
      };

    recognizers.add(recognizer);

    return recognizer;
  }

  void _tag(String tag) {
    final lower = tag.toLowerCase();

    if (lower.startsWith('</')) {
      _pop(lower.substring(2).replaceAll('>', '').trim());

      return;
    }

    final name = RegExp(r'^<([a-zA-Z0-9]+)')
        .firstMatch(tag)
        ?.group(1)
        ?.toLowerCase();
    if (name == null) return;

    final attributes = _attributes(tag);

    switch (name) {
      case 'p':
        _break();
      case 'br':
        _spans.add(const TextSpan(text: '\n'));
      case 'strong':
      case 'b':
        _frames.add(const _Frame(style: _bold));
      case 'em':
      case 'i':
        _frames.add(const _Frame(style: _italic));
      case 'code':
      case 'pre':
        if (name == 'pre') _break();
        _frames.add(const _Frame(style: _code));
      case 'a':
        final href = attributes['href'];
        _frames.add(_Frame(style: _link, href: href));
      case 'span':
        _frames.add(_frameForSpan(attributes));
      case 'img':
        _image(attributes);
    }
  }

  _Frame _frameForSpan(Map<String, String> attributes) {
    final type = attributes['data-type'] ?? attributes['class'] ?? '';

    if (type.contains('mention')) {
      final userId = int.tryParse(attributes['data-user-id'] ?? '');
      final color = userId == null ? null : mentionColor?.call(userId);

      return _Frame(
        style: color == null ? _mention : _mention.copyWith(color: color),
      );
    }

    if (type.contains('channel-reference')) {
      return _Frame(style: _mention);
    }

    if (type.contains('hard-break')) {
      _spans.add(const TextSpan(text: '\n'));
    }

    return const _Frame();
  }

  void _image(Map<String, String> attributes) {
    final src = attributes['src'];
    final alt = attributes['alt'] ?? '';

    if (src == null || src.isEmpty) {
      if (alt.isNotEmpty) _spans.add(TextSpan(text: alt, style: _style));

      return;
    }

    var url = src;
    if (url.startsWith('/')) {
      final base = baseUrl;
      if (base == null) return;

      url = '$base$url';
    }

    _spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Image.network(
            url,
            width: 19,
            height: 19,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  void _pop(String name) {
    // only pop a frame that belongs to this tag: an unclosed <p> must not strip
    // a style frame the text inside it still needs
    if (name.isEmpty || _frames.length <= 1) return;

    switch (name) {
      case 'strong':
      case 'b':
      case 'em':
      case 'i':
      case 'code':
      case 'pre':
      case 'a':
      case 'span':
        _frames.removeLast();
      case 'p':
        _break();
    }
  }

  Map<String, String> _attributes(String tag) {
    final result = <String, String>{};

    for (final match in _attributePattern.allMatches(tag)) {
      result[match.group(1)!] = match.group(2)!;
    }

    return result;
  }
}
