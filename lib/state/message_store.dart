import '../models/message.dart';

/// the message history of one channel, kept in ascending order because that is
/// how it is laid out on screen, with the pagination cursor pointing at the
/// oldest row loaded so far.
class ChannelMessages {
  final List<Message> messages = <Message>[];

  MessagesCursor? cursor;
  bool reachedStart = false;
  bool isLoadingInitial = false;
  bool isLoadingOlder = false;
  String? error;

  bool get isEmpty => messages.isEmpty;

  bool contains(int messageId) =>
      messages.any((message) => message.id == messageId);

  int indexOf(int messageId) =>
      messages.indexWhere((message) => message.id == messageId);
}

class MessageStore {
  final Map<int, ChannelMessages> _channels = <int, ChannelMessages>{};
  final Map<int, Map<int, DateTime>> _typing = <int, Map<int, DateTime>>{};

  static const Duration typingTtl = Duration(seconds: 6);

  ChannelMessages of(int channelId) =>
      _channels.putIfAbsent(channelId, ChannelMessages.new);

  bool isLoaded(int channelId) => _channels.containsKey(channelId);

  void beginLoad(int channelId) {
    final channel = of(channelId);

    channel.isLoadingInitial = true;
    channel.error = null;
  }

  void failLoad(int channelId, String message) {
    final channel = of(channelId);

    channel.isLoadingInitial = false;
    channel.isLoadingOlder = false;
    channel.error = message;
  }

  /// merges a page into what is already there: pages overlap when a message
  /// arrives between two requests, so everything is de-duplicated by id.
  void applyPage(int channelId, MessagesPage page) {
    final channel = of(channelId);

    for (final message in page.messages) {
      _upsert(channel, message);
    }

    channel.cursor = page.nextCursor;
    channel.reachedStart = page.nextCursor == null;
    channel.isLoadingInitial = false;
    channel.isLoadingOlder = false;
    channel.error = null;
  }

  void applyNewMessage(Message message) {
    _upsert(of(message.channelId), message);
  }

  void applyMessageUpdate(Message message) {
    _upsert(of(message.channelId), message);
  }

  void removeMessage(int channelId, int messageId) {
    final channel = _channels[channelId];
    if (channel == null) return;

    final index = channel.indexOf(messageId);
    if (index == -1) return;

    channel.messages.removeAt(index);
  }

  void noteTyping(int channelId, int userId, DateTime at) {
    _typing.putIfAbsent(channelId, () => <int, DateTime>{})[userId] = at;
  }

  List<int> typingUserIds(int channelId) {
    final users = _typing[channelId];
    if (users == null || users.isEmpty) return const <int>[];

    final now = DateTime.now();

    users.removeWhere((_, at) => now.difference(at) > typingTtl);

    return users.keys.toList(growable: false);
  }

  void clearTyping(int channelId, int userId) {
    _typing[channelId]?.remove(userId);
  }

  void clearChannel(int channelId) {
    _channels.remove(channelId);
    _typing.remove(channelId);
  }

  void clear() {
    _channels.clear();
    _typing.clear();
  }

  void _upsert(ChannelMessages channel, Message message) {
    final index = channel.indexOf(message.id);

    if (index != -1) {
      channel.messages[index] = message;

      return;
    }

    // history arrives newest-first and live messages arrive in order, so the
    // common case is an append and the scan is only paid for a jump
    final last = channel.messages.isEmpty ? null : channel.messages.last;

    if (last == null || _isAfter(message, last)) {
      channel.messages.add(message);

      return;
    }

    final first = channel.messages.first;
    if (_isAfter(first, message)) {
      channel.messages.insert(0, message);

      return;
    }

    for (
      var position = channel.messages.length - 1;
      position >= 0;
      position--
    ) {
      if (!_isAfter(channel.messages[position], message)) {
        channel.messages.insert(position + 1, message);

        return;
      }
    }

    channel.messages.insert(0, message);
  }

  bool _isAfter(Message candidate, Message other) =>
      candidate.createdAt > other.createdAt ||
      (candidate.createdAt == other.createdAt && candidate.id > other.id);
}
