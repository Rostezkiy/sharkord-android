import 'parse.dart';
import 'server_file.dart';

class MessageReaction {
  const MessageReaction({
    required this.emoji,
    this.userId,
    this.pluginId,
    this.file,
  });

  final String emoji;
  final int? userId;
  final String? pluginId;
  final ServerFile? file;

  factory MessageReaction.fromJson(Map<String, dynamic> json) =>
      MessageReaction(
        emoji: asString(json['emoji']),
        userId: asIntOrNull(json['userId']),
        pluginId: asStringOrNull(json['pluginId']),
        file: json['file'] == null
            ? null
            : ServerFile.fromJson(asMap(json['file'])),
      );
}

class MessageReplyPreview {
  const MessageReplyPreview({
    required this.id,
    required this.userId,
    this.content,
  });

  final int id;
  final int? userId;
  final String? content;

  factory MessageReplyPreview.fromJson(Map<String, dynamic> json) =>
      MessageReplyPreview(
        id: asInt(json['id']),
        userId: asIntOrNull(json['userId']),
        content: asStringOrNull(json['content']),
      );
}

class Message {
  const Message({
    required this.id,
    required this.channelId,
    required this.createdAt,
    required this.files,
    required this.reactions,
    this.content,
    this.userId,
    this.pluginId,
    this.parentMessageId,
    this.replyToMessageId,
    this.replyTo,
    this.editable = true,
    this.pinned = false,
    this.editedAt,
    this.replyCount = 0,
  });

  final int id;
  final int channelId;
  final int createdAt;
  final List<ServerFile> files;
  final List<MessageReaction> reactions;
  final String? content;
  final int? userId;
  final String? pluginId;
  final int? parentMessageId;
  final int? replyToMessageId;
  final MessageReplyPreview? replyTo;
  final bool editable;
  final bool pinned;
  final int? editedAt;
  final int replyCount;

  DateTime get sentAt => DateTime.fromMillisecondsSinceEpoch(createdAt);

  factory Message.fromJson(Map<String, dynamic> json) {
    final replyTo = json['replyTo'];

    return Message(
      id: asInt(json['id']),
      channelId: asInt(json['channelId']),
      createdAt: asInt(json['createdAt']),
      files: asMapList(json['files'])
          .map(ServerFile.fromJson)
          .toList(growable: false),
      reactions: asMapList(json['reactions'])
          .map(MessageReaction.fromJson)
          .toList(growable: false),
      content: asStringOrNull(json['content']),
      userId: asIntOrNull(json['userId']),
      pluginId: asStringOrNull(json['pluginId']),
      parentMessageId: asIntOrNull(json['parentMessageId']),
      replyToMessageId: asIntOrNull(json['replyToMessageId']),
      replyTo: replyTo == null
          ? null
          : MessageReplyPreview.fromJson(asMap(replyTo)),
      editable: asBool(json['editable'], fallback: true),
      pinned: asBool(json['pinned']),
      editedAt: asIntOrNull(json['editedAt']),
      replyCount: asInt(json['replyCount']),
    );
  }
}

class MessagesCursor {
  const MessagesCursor({required this.createdAt, required this.id});

  final int createdAt;
  final int id;

  factory MessagesCursor.fromJson(Map<String, dynamic> json) => MessagesCursor(
    createdAt: asInt(json['createdAt']),
    id: asInt(json['id']),
  );

  Map<String, Object> toJson() => <String, Object>{
    'createdAt': createdAt,
    'id': id,
  };
}

class MessagesPage {
  const MessagesPage({required this.messages, this.nextCursor});

  final List<Message> messages;
  final MessagesCursor? nextCursor;

  bool get hasMore => nextCursor != null;

  factory MessagesPage.fromJson(Map<String, dynamic> json) {
    final cursor = json['nextCursor'];

    return MessagesPage(
      messages: asMapList(json['messages'])
          .map(Message.fromJson)
          .toList(growable: false),
      nextCursor: cursor == null
          ? null
          : MessagesCursor.fromJson(asMap(cursor)),
    );
  }
}
