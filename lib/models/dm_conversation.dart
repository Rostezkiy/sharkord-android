import 'parse.dart';

class DirectMessageConversation {
  const DirectMessageConversation({
    required this.channelId,
    required this.userId,
    required this.unreadCount,
    required this.lastMessageAt,
  });

  final int channelId;
  final int userId;
  final int unreadCount;
  final int lastMessageAt;

  factory DirectMessageConversation.fromJson(Map<String, dynamic> json) =>
      DirectMessageConversation(
        channelId: asInt(json['channelId']),
        userId: asInt(json['userId']),
        unreadCount: asInt(json['unreadCount']),
        lastMessageAt: asInt(json['lastMessageAt']),
      );

  DirectMessageConversation copyWith({int? unreadCount, int? lastMessageAt}) =>
      DirectMessageConversation(
        channelId: channelId,
        userId: userId,
        unreadCount: unreadCount ?? this.unreadCount,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      );
}
