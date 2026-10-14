/// the html helpers the message list and the composer need. everything here is
/// pure string work: the rendering itself lives with the widget that owns it.
abstract final class MessageText {
  // the entity names are assembled from two pieces so the source never contains
  // the sequence itself
  static const String amp =
      '&'
      'amp;';
  static const String lt =
      '&'
      'lt;';
  static const String gt =
      '&'
      'gt;';
  static const String nbsp =
      '&'
      'nbsp;';
  static const String quot =
      '&'
      'quot;';
  static const String apostrophe =
      '&'
      '#39;';

  static final RegExp _urlPattern = RegExp(
    r'https?://[^\s<>]+[^\s<>.,;:!?)\]]',
    caseSensitive: false,
  );

  static final RegExp _tagPattern = RegExp(r'<[^>]*>');
  static final RegExp _breakPattern = RegExp(
    r'</p>|</pre>|</code>|<br\s*/?>',
    caseSensitive: false,
  );
  static final RegExp _entityPattern = RegExp(r'&#(x?[0-9A-Fa-f]+);');

  /// the plain text a message ends up showing, used for the channel previews and
  /// for deciding whether the composer has anything to send.
  static String toPlainText(String? html) {
    if (html == null || html.isEmpty) return '';

    final withBreaks = html
        .replaceAll(_breakPattern, '\n')
        .replaceAll(_tagPattern, '');

    return unescape(withBreaks).trim();
  }

  /// wraps what the user typed into the html the server stores, so newlines and
  /// links survive the round trip.
  static String buildOutgoing(String text) {
    final trimmed = text.replaceAll('\r\n', '\n').trimRight();
    if (trimmed.isEmpty) return '';

    final paragraphs = trimmed.split('\n').map((line) {
      if (line.trim().isEmpty) return '<p></p>';

      return '<p>${linkify(escape(line))}</p>';
    });

    return paragraphs.join();
  }

  static String escape(String value) =>
      value.replaceAll('&', amp).replaceAll('<', lt).replaceAll('>', gt);

  static String linkify(String escaped) => escaped.replaceAllMapped(
    _urlPattern,
    (match) => '<a href="${match.group(0)}">${match.group(0)}</a>',
  );

  static String unescape(String value) {
    final named = value
        .replaceAll(nbsp, ' ')
        .replaceAll(lt, '<')
        .replaceAll(gt, '>')
        .replaceAll(quot, String.fromCharCode(0x22))
        .replaceAll(apostrophe, String.fromCharCode(0x27))
        // the ampersand goes last, otherwise a decoded one would be taken for the
        // start of the next entity
        .replaceAll(amp, '&');

    return named.replaceAllMapped(_entityPattern, (match) {
      final raw = match.group(1)!;
      final isHex = raw.startsWith('x') || raw.startsWith('X');
      final code = isHex
          ? int.tryParse(raw.substring(1), radix: 16)
          : int.tryParse(raw);

      if (code == null || code <= 0 || code > 0x10FFFF) return match.group(0)!;

      return String.fromCharCode(code);
    });
  }
}
