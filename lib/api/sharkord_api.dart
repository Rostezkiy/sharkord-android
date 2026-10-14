import 'dart:async';

import '../models/channel.dart';
import '../models/dm_conversation.dart';
import '../models/message.dart';
import '../models/parse.dart';
import '../models/server_join.dart';
import '../models/user.dart';
import '../models/voice.dart';
import 'trpc_socket.dart';

/// the typed surface of the server's tRPC router: one method per procedure the
/// client uses, so no route path is spelled out anywhere else.
class SharkordApi {
  SharkordApi(this.socket);

  final TrpcSocket socket;

  /// the handshake hash belongs to the connection: the server keeps it on the
  /// socket's context and `joinServer` refuses a hash that did not come from it.
  Future<HandshakeResult> handshake() async {
    final data = asMap(await socket.query('others.handshake'));

    return HandshakeResult(
      hash: asString(data['handshakeHash']),
      hasPassword: asBool(data['hasPassword']),
    );
  }

  Future<ServerJoin> joinServer({
    required String handshakeHash,
    String? password,
  }) async {
    final data = asMap(
      await socket.query('others.joinServer', <String, Object?>{
        'handshakeHash': handshakeHash,
        if (password != null && password.isNotEmpty) 'password': password,
      }),
    );

    return ServerJoin.fromJson(data);
  }

  Future<MessagesPage> getMessages({
    required int channelId,
    MessagesCursor? cursor,
    int limit = 40,
  }) async {
    final data = await socket.query('messages.get', <String, Object?>{
      'channelId': channelId,
      'cursor': ?cursor?.toJson(),
      'limit': limit,
    });

    return MessagesPage.fromJson(asMap(data));
  }

  Future<int> sendMessage({
    required int channelId,
    required String content,
    int? replyToMessageId,
  }) async {
    final result = await socket.mutate('messages.send', <String, Object?>{
      'content': content,
      'channelId': channelId,
      'replyToMessageId': ?replyToMessageId,
    });

    return asInt(result);
  }

  Future<void> signalTyping(int channelId) => socket.mutate(
    'messages.signalTyping',
    <String, Object?>{'channelId': channelId},
  );

  Future<void> markAsRead(int channelId) => socket.mutate(
    'channels.markAsRead',
    <String, Object?>{'channelId': channelId},
  );

  Future<void> toggleReaction({
    required int messageId,
    required String emoji,
  }) => socket.mutate('messages.toggleReaction', <String, Object?>{
    'messageId': messageId,
    'emoji': emoji,
  });

  Future<List<DirectMessageConversation>> getDirectMessages() async {
    final data = await socket.query('dms.get');

    return asMapList(data)
        .map(DirectMessageConversation.fromJson)
        .toList(growable: false);
  }

  Future<int> openDirectMessage(int userId) async {
    final data = asMap(
      await socket.mutate('dms.open', <String, Object?>{'userId': userId}),
    );

    return asInt(data['channelId']);
  }

  Stream<Message> onNewMessage() => _messages('messages.onNew');

  Stream<Message> onMessageUpdate() => _messages('messages.onUpdate');

  Stream<MessageDeletedEvent> onMessageDelete() => socket
      .subscribe('messages.onDelete')
      .where((event) => event is Map)
      .map((event) => MessageDeletedEvent.fromJson(asMap(event)));

  Stream<TypingEvent> onTyping() => socket
      .subscribe('messages.onTyping')
      .where((event) => event is Map)
      .map((event) => TypingEvent.fromJson(asMap(event)));

  Stream<User> onUserJoin() => _user('users.onJoin');

  Stream<User> onUserUpdate() => _user('users.onUpdate');

  Stream<int> onUserLeave() =>
      socket.subscribe('users.onLeave').map((event) => asInt(event));

  Stream<Channel> onChannelCreate() => _channel('channels.onCreate');

  Stream<Channel> onChannelUpdate() => _channel('channels.onUpdate');

  Stream<int> onChannelDelete() =>
      socket.subscribe('channels.onDelete').map((event) => asInt(event));

  /// the whole permission map for this user again, not a delta: the server
  /// recomputes it whenever a role or an override changes
  Stream<Map<int, Map<String, bool>>> onChannelPermissionsUpdate() => socket
      .subscribe('channels.onPermissionsUpdate')
      .map(parseChannelPermissions);

  Stream<ChannelReadStateEvent> onReadStateUpdate() => socket
      .subscribe('channels.onReadStateUpdate')
      .where((event) => event is Map)
      .map((event) => ChannelReadStateEvent.fromJson(asMap(event)));

  Stream<ChannelReadStateDeltaEvent> onReadStateDelta() => socket
      .subscribe('channels.onReadStateDelta')
      .where((event) => event is Map)
      .map((event) => ChannelReadStateDeltaEvent.fromJson(asMap(event)));

  Stream<int> onDmConversationOpen() => socket
      .subscribe('dms.onConversationOpen')
      .map((event) => asInt(asMap(event)['channelId']));

  Stream<VoiceUserEvent> onUserJoinVoice() => socket
      .subscribe('voice.onJoin')
      .where((event) => event is Map)
      .map((event) => VoiceUserEvent.fromJson(asMap(event), withState: true));

  Stream<VoiceUserEvent> onUserLeaveVoice() => socket
      .subscribe('voice.onLeave')
      .where((event) => event is Map)
      .map((event) => VoiceUserEvent.fromJson(asMap(event)));

  Stream<VoiceUserEvent> onUserVoiceStateUpdate() => socket
      .subscribe('voice.onUpdateState')
      .where((event) => event is Map)
      .map((event) => VoiceUserEvent.fromJson(asMap(event), withState: true));

  /// channel scoped: the server only forwards these to users sitting in the
  /// channel the producer belongs to.
  Stream<VoiceProducerEvent> onVoiceNewProducer() =>
      _producerEvent('voice.onNewProducer');

  Stream<VoiceProducerEvent> onVoiceProducerClosed() =>
      _producerEvent('voice.onProducerClosed');

  Stream<VoiceProducerEvent> _producerEvent(String path) => socket
      .subscribe(path)
      .where((event) => event is Map)
      .map((event) => VoiceProducerEvent.fromJson(asMap(event)));

  // ------------------------------------------------------------- voice media
  // the mediasoup handshake itself lives in VoiceController: these are only the
  // signaling calls it makes, in the order the session needs them.

  /// joins the channel and answers with the router RTP capabilities the device
  /// has to load before any transport can be created.
  Future<Map<String, dynamic>> joinVoice({
    required int channelId,
    required bool micMuted,
    required bool soundMuted,
  }) async {
    final result = await socket.mutate('voice.join', <String, Object?>{
      'channelId': channelId,
      'state': <String, Object?>{
        'micMuted': micMuted,
        'soundMuted': soundMuted,
      },
    });

    // the route wraps them in an envelope, and the device loads the inner object
    // rather than the response itself
    return asMap(asMap(result)['routerRtpCapabilities']);
  }

  Future<void> leaveVoice() => socket.mutate('voice.leave');

  Future<Map<String, dynamic>> createProducerTransport() async {
    final result = await socket.mutate('voice.createProducerTransport');

    return asMap(result);
  }

  Future<void> connectProducerTransport(Map<String, dynamic> dtlsParameters) =>
      socket.mutate('voice.connectProducerTransport', <String, Object?>{
        'dtlsParameters': dtlsParameters,
      });

  Future<Map<String, dynamic>> createConsumerTransport() async {
    final result = await socket.mutate('voice.createConsumerTransport');

    return asMap(result);
  }

  Future<void> connectConsumerTransport(Map<String, dynamic> dtlsParameters) =>
      socket.mutate('voice.connectConsumerTransport', <String, Object?>{
        'dtlsParameters': dtlsParameters,
      });

  Future<String> produce({
    required String transportId,
    required StreamKind kind,
    required Map<String, dynamic> rtpParameters,
  }) async {
    final result = await socket.mutate('voice.produce', <String, Object?>{
      'transportId': transportId,
      'kind': kind.wire,
      'rtpParameters': rtpParameters,
    });

    return asString(result);
  }

  Future<VoiceConsumerParams> consume({
    required StreamKind kind,
    required int remoteId,
    required Map<String, dynamic> rtpCapabilities,
  }) async {
    final result = await socket.mutate('voice.consume', <String, Object?>{
      'kind': kind.wire,
      'remoteId': remoteId,
      'rtpCapabilities': rtpCapabilities,
    });

    return VoiceConsumerParams.fromJson(asMap(result));
  }

  Future<VoiceProducerIds> getProducers() async {
    final result = await socket.query('voice.getProducers');

    return VoiceProducerIds.fromJson(asMap(result));
  }

  Future<void> updateVoiceState({bool? micMuted, bool? soundMuted}) =>
      socket.mutate('voice.updateState', <String, Object?>{
        'micMuted': ?micMuted,
        'soundMuted': ?soundMuted,
      });

  Future<void> closeProducer(StreamKind kind) => socket.mutate(
    'voice.closeProducer',
    <String, Object?>{'kind': kind.wire},
  );

  Stream<Message> _messages(String path) => socket
      .subscribe(path)
      .where((event) => event is Map)
      .map((event) => Message.fromJson(asMap(event)));

  Stream<User> _user(String path) => socket
      .subscribe(path)
      .where((event) => event is Map)
      .map((event) => User.fromJson(asMap(event)));

  Stream<Channel> _channel(String path) => socket
      .subscribe(path)
      .where((event) => event is Map)
      .map((event) => Channel.fromJson(asMap(event)));
}

class HandshakeResult {
  const HandshakeResult({required this.hash, required this.hasPassword});

  final String hash;
  final bool hasPassword;
}

class TypingEvent {
  const TypingEvent({required this.channelId, required this.userId});

  final int channelId;
  final int userId;

  factory TypingEvent.fromJson(Map<String, dynamic> json) => TypingEvent(
    channelId: asInt(json['channelId']),
    userId: asInt(json['userId']),
  );
}

class MessageDeletedEvent {
  const MessageDeletedEvent({required this.messageId, required this.channelId});

  final int messageId;
  final int channelId;

  factory MessageDeletedEvent.fromJson(Map<String, dynamic> json) =>
      MessageDeletedEvent(
        messageId: asInt(json['messageId']),
        channelId: asInt(json['channelId']),
      );
}

class ChannelReadStateEvent {
  const ChannelReadStateEvent({required this.channelId, required this.count});

  final int channelId;
  final int count;

  factory ChannelReadStateEvent.fromJson(Map<String, dynamic> json) =>
      ChannelReadStateEvent(
        channelId: asInt(json['channelId']),
        count: asInt(json['count']),
      );
}

class ChannelReadStateDeltaEvent {
  const ChannelReadStateDeltaEvent({
    required this.channelId,
    required this.delta,
  });

  final int channelId;
  final int delta;

  factory ChannelReadStateDeltaEvent.fromJson(Map<String, dynamic> json) =>
      ChannelReadStateDeltaEvent(
        channelId: asInt(json['channelId']),
        delta: asInt(json['delta']),
      );
}

class VoiceUserEvent {
  const VoiceUserEvent({
    required this.channelId,
    required this.userId,
    this.state,
    this.fromChannelId,
  });

  final int channelId;
  final int userId;
  final VoiceUserState? state;
  final int? fromChannelId;

  factory VoiceUserEvent.fromJson(
    Map<String, dynamic> json, {
    bool withState = false,
  }) => VoiceUserEvent(
    channelId: asInt(json['channelId']),
    userId: asInt(json['userId']),
    fromChannelId: asIntOrNull(json['fromChannelId']),
    state: withState ? VoiceUserState.fromJson(asMap(json['state'])) : null,
  );
}
