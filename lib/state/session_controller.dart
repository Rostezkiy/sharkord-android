import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

import '../api/api_exception.dart';
import '../api/rest_client.dart';
import '../api/server_endpoint.dart';
import '../api/sharkord_api.dart';
import '../api/trpc_socket.dart';
import '../helpers/message_text.dart';
import '../models/channel.dart';
import '../models/dm_conversation.dart';
import '../models/message.dart';
import '../models/role.dart';
import '../models/server_info.dart';
import '../models/server_join.dart';
import '../models/server_settings.dart';
import '../models/user.dart';
import '../models/voice.dart';
import 'app_preferences.dart';
import 'message_store.dart';
import 'voice_controller.dart';

enum SessionPhase {
  /// reading what was stored from the last run
  starting,

  /// nothing is loaded: the connect screen is showing
  unauthenticated,

  /// a connection is being established (handshake, login, join)
  connecting,

  /// joined, the server screen is showing
  ready,

  /// a step failed and the reason is in [SessionController.errorMessage]
  failed,
}

/// everything the UI reads and nothing else: the whole session (server state,
/// realtime subscriptions, message history and the actions on them) lives here.
class SessionController extends ChangeNotifier {
  final AppPreferences preferences = AppPreferences();
  final MessageStore messages = MessageStore();

  /// the media session for the voice channel this account is connected to.
  final VoiceController voice = VoiceController();

  SessionPhase phase = SessionPhase.starting;
  String? errorMessage;
  String? statusMessage;
  bool connectionLost = false;

  ServerInfo? serverInfo;
  ServerEndpoint? endpoint;

  RestClient? _rest;
  TrpcSocket? _socket;
  SharkordApi? _api;

  int ownUserId = 0;
  List<Category> categories = <Category>[];
  List<Channel> channels = <Channel>[];
  List<Role> roles = <Role>[];
  List<DirectMessageConversation> dmConversations =
      <DirectMessageConversation>[];
  Map<int, User> users = <int, User>{};
  Map<int, int> readStates = <int, int>{};
  Map<int, Map<String, bool>> channelPermissions = <int, Map<String, bool>>{};
  VoiceMap voiceMap = VoiceMap.empty;
  ServerSettings? settings;
  bool serverNeedsPassword = false;

  int? selectedChannelId;
  bool isTypingNotified = false;

  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  final Map<int, DateTime> _lastReadAt = <int, DateTime>{};
  Timer? _typingResetTimer;
  AppLifecycleListener? _lifecycle;

  // ---------------------------------------------------------------- lifecycle

  Future<void> bootstrap() async {
    // the socket can die while the app is in the background with nothing reporting it
    _lifecycle ??= AppLifecycleListener(onResume: _handleAppResumed);
    await preferences.load();

    final storedUrl = preferences.serverUrl;
    if (storedUrl == null || storedUrl.isEmpty) {
      _setPhase(SessionPhase.unauthenticated);

      return;
    }

    try {
      await refreshServerInfo(storedUrl);
    } on RestException {
      // an unreachable server is not fatal: the connect screen shows the address
      // the user typed last and lets them fix it
      _setPhase(SessionPhase.unauthenticated);

      return;
    } on ApiException {
      // a stored address that no longer parses sends the user back to the
      // connect form rather than failing on every launch
      _setPhase(SessionPhase.unauthenticated);

      return;
    }

    final token = preferences.token;
    if (token == null || token.isEmpty) {
      _setPhase(SessionPhase.unauthenticated);

      return;
    }

    await _startSession(
      serverUrl: storedUrl,
      token: token,
      identity: preferences.identity,
    );
  }

  /// loads the unauthenticated server card for the address being typed.
  Future<void> refreshServerInfo(String serverUrl) async {
    final parsed = ServerEndpoint.parse(serverUrl);

    final rest = RestClient(parsed);
    final info = await rest.fetchInfo();

    rest.close();

    endpoint = parsed;
    serverInfo = info;

    await preferences.saveServerUrl(parsed.httpBase);
    notifyListeners();
  }

  Future<void> signIn({
    required String serverUrl,
    required String identity,
    required String password,
  }) async {
    _setPhase(SessionPhase.connecting, status: 'Connecting to $serverUrl');

    final parsed = ServerEndpoint.parse(serverUrl);
    final rest = RestClient(parsed);

    try {
      if (serverInfo == null || endpoint?.httpBase != parsed.httpBase) {
        serverInfo = await rest.fetchInfo();
      }

      final token = await rest.login(identity: identity, password: password);

      rest.close();

      await preferences.saveSession(
        serverUrl: parsed.httpBase,
        identity: identity,
        token: token,
      );

      await _startSession(
        serverUrl: parsed.httpBase,
        token: token,
        identity: identity,
      );
    } on RestException catch (error) {
      rest.close();
      _setPhase(SessionPhase.failed, error: error.message);
    } on ApiException catch (error) {
      rest.close();
      _setPhase(SessionPhase.failed, error: error.message);
    }
  }

  /// drops the session and goes back to the connect screen, keeping the address
  /// so switching servers starts from where the last one was.
  Future<void> signOut({bool forget = false}) async {
    await _teardown();
    await preferences.clearToken();

    if (forget) {
      endpoint = null;
      serverInfo = null;
    }

    _setPhase(SessionPhase.unauthenticated);
  }

  Future<void> _startSession({
    required String serverUrl,
    required String token,
    String? identity,
  }) async {
    _setPhase(SessionPhase.connecting, status: 'Signing in');

    final parsed = ServerEndpoint.parse(serverUrl);
    final socket = TrpcSocket(
      endpoint: parsed,
      token: token,
      onReconnect: _resumeSession,
    );
    final api = SharkordApi(socket);

    endpoint = parsed;
    _socket = socket;
    _api = api;

    _socketSubscription?.cancel();
    _socketSubscription = socket.connectionState.listen(_handleSocketState);

    try {
      await socket.connect();

      _setPhase(SessionPhase.connecting, status: 'Handshaking');

      final handshake = await api.handshake();

      _setPhase(SessionPhase.connecting, status: 'Joining');

      final join = await api.joinServer(
        handshakeHash: handshake.hash,
        password: preferences.passwords[parsed.httpBase],
      );

      await _applyJoin(join, handshake.hasPassword);

      if (identity != null) await preferences.saveIdentity(identity);

      _setPhase(SessionPhase.ready);
    } on ApiException catch (error) {
      await _teardown();

      // an expired or revoked token must not keep bouncing the app back in
      if (error.isUnauthorized) {
        await preferences.clearToken();
      }

      _setPhase(SessionPhase.failed, error: error.message);
    } on RestException catch (error) {
      await _teardown();
      _setPhase(SessionPhase.failed, error: error.message);
    }
  }

  /// retries the join with the server password, which the server only reports as
  /// needed after the handshake.
  Future<void> retryWithPassword({required String password}) async {
    final serverUrl = endpoint?.httpBase;
    final token = preferences.token;

    if (serverUrl == null || token == null) return;

    await preferences.saveServerPassword(serverUrl, password);

    await _startSession(serverUrl: serverUrl, token: token);
  }

  Future<void> retry() async {
    final serverUrl = endpoint?.httpBase ?? preferences.serverUrl;
    final token = preferences.token;

    if (serverUrl == null) {
      _setPhase(SessionPhase.unauthenticated);

      return;
    }

    if (token == null || token.isEmpty) {
      _setPhase(SessionPhase.unauthenticated);

      return;
    }

    await _startSession(serverUrl: serverUrl, token: token);
  }

  /// replaces the whole server owned state with what the join returned, leaving the
  /// view state (the open channel and the messages already loaded for it) alone so a
  /// reconnect does not throw the user out of the channel they are reading.
  void _applyServerState(ServerJoin join, bool hasPassword) {
    ownUserId = join.ownUserId;
    categories = join.categories;
    channels = join.channels;
    roles = join.roles;
    users = <int, User>{for (final user in join.users) user.id: user};
    readStates = <int, int>{...join.readStates};
    channelPermissions = join.channelPermissions;
    voiceMap = join.voiceMap;
    settings = join.settings;
    serverNeedsPassword = hasPassword;
  }

  Future<void> _applyJoin(ServerJoin join, bool hasPassword) async {
    final api = _api;

    if (api == null) return;

    _applyServerState(join, hasPassword);

    messages.clear();
    selectedChannelId = null;

    voice.attach(api: api, ownUserId: join.ownUserId);
    _wireRealtime(api);

    if (settings?.directMessagesEnabled ?? false) {
      unawaited(_loadDirectMessages());
    }

    final firstTextChannel = _firstOrNull(textChannels);
    if (firstTextChannel != null) {
      await selectChannel(firstTextChannel.id);
    }

    notifyListeners();
  }

  /// every reconnect opens a brand new socket, and the server refuses both calls and
  /// subscriptions on a connection that has never joined, so the handshake and the join
  /// run again before the socket resubscribes. The server owned state is reloaded, the
  /// open channel and its messages are kept.
  Future<void> _resumeSession() async {
    final api = _api;
    final serverUrl = endpoint?.httpBase;

    if (api == null || serverUrl == null) return;

    try {
      final handshake = await api.handshake();

      final join = await api.joinServer(
        handshakeHash: handshake.hash,
        password: preferences.passwords[serverUrl],
      );

      _applyServerState(join, handshake.hasPassword);
      voice.attach(api: api, ownUserId: join.ownUserId);

      notifyListeners();
    } on ApiException catch (error) {
      // a token revoked while the app was away cannot be retried into working, so the
      // session is dropped instead of looping on a connection that will never join
      if (error.isUnauthorized) {
        await signOut();
        _setPhase(SessionPhase.failed, error: error.message);

        return;
      }

      rethrow;
    }
  }

  StreamSubscription<TrpcConnectionState>? _socketSubscription;

  Future<void> _teardown() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    await _socketSubscription?.cancel();
    _socketSubscription = null;

    _typingResetTimer?.cancel();
    _typingResetTimer = null;

    await _socket?.close();
    _socket = null;
    _api = null;

    await voice.detach();
    _rest?.close();
    _rest = null;

    messages.clear();
    users = <int, User>{};
    channels = <Channel>[];
    categories = <Category>[];
    readStates = <int, int>{};
    voiceMap = VoiceMap.empty;
    selectedChannelId = null;
    connectionLost = false;
    statusMessage = null;
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_socketSubscription?.cancel());
    _typingResetTimer?.cancel();
    _lifecycle?.dispose();
    unawaited(_socket?.close());
    unawaited(voice.detach());
    voice.dispose();

    super.dispose();
  }

  // -------------------------------------------------------------- realtime

  void _wireRealtime(SharkordApi api) {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();

    void listen<T>(Stream<T> stream, void Function(T event) onEvent) {
      _subscriptions.add(stream.listen(onEvent, onError: (Object _) {}));
    }

    listen(api.onNewMessage(), _handleNewMessage);
    listen(api.onMessageUpdate(), _handleMessageUpdate);
    listen(api.onMessageDelete(), _handleMessageDelete);
    listen(api.onTyping(), _handleTyping);

    listen(api.onUserJoin(), _handleUserJoin);
    listen(api.onUserUpdate(), _handleUserUpdate);
    listen(api.onUserLeave(), _handleUserLeave);

    listen(api.onChannelCreate(), _handleChannelCreate);
    listen(api.onChannelUpdate(), _handleChannelUpdate);
    listen(api.onChannelDelete(), _handleChannelDelete);

    listen(api.onChannelPermissionsUpdate(), _handleChannelPermissionsUpdate);

    listen(api.onReadStateUpdate(), _handleReadStateUpdate);
    listen(api.onReadStateDelta(), _handleReadStateDelta);

    listen(api.onDmConversationOpen(), _handleDmConversationOpen);

    listen(api.onUserJoinVoice(), _handleVoiceJoin);
    listen(api.onUserLeaveVoice(), _handleVoiceLeave);
    listen(api.onUserVoiceStateUpdate(), _handleVoiceState);
    listen(api.onVoiceNewProducer(), _handleVoiceProducerAdded);
    listen(api.onVoiceProducerClosed(), _handleVoiceProducerClosed);
  }

  void _handleSocketState(TrpcConnectionState state) {
    if (phase != SessionPhase.ready) return;

    final lost = state == TrpcConnectionState.disconnected;

    // a dropped socket takes the mediasoup session with it
    if (lost && voice.isActive) {
      unawaited(voice.resetLocal());
    }
    if (lost == connectionLost) return;

    connectionLost = lost;
    notifyListeners();
  }

  /// android suspends the app and the socket can die in the background without anything
  /// reporting it, so coming back to the foreground checks the connection instead of
  /// waiting for a request to hang on it.
  void _handleAppResumed() {
    final socket = _socket;

    if (phase != SessionPhase.ready || socket == null) return;

    if (!socket.isSilent) return;

    unawaited(reconnect());
  }

  void _handleNewMessage(Message message) {
    messages.applyNewMessage(message);
    messages.clearTyping(message.channelId, message.userId ?? -1);

    if (message.channelId == selectedChannelId) {
      unawaited(_markRead(message.channelId, force: true));
    }

    notifyListeners();
  }

  void _handleMessageUpdate(Message message) {
    messages.applyMessageUpdate(message);
    notifyListeners();
  }

  void _handleMessageDelete(MessageDeletedEvent event) {
    messages.removeMessage(event.channelId, event.messageId);
    notifyListeners();
  }

  /// the server sends the whole map again, not a delta
  void _handleChannelPermissionsUpdate(
    Map<int, Map<String, bool>> permissions,
  ) {
    channelPermissions = permissions;
    notifyListeners();
  }

  void _handleTyping(TypingEvent event) {
    if (event.userId == ownUserId) return;

    messages.noteTyping(event.channelId, event.userId, DateTime.now());

    _typingResetTimer?.cancel();
    _typingResetTimer = Timer(MessageStore.typingTtl, notifyListeners);

    notifyListeners();
  }

  void _handleUserJoin(User user) {
    users[user.id] = user;
    notifyListeners();
  }

  void _handleUserUpdate(User user) {
    final existing = users[user.id];

    users[user.id] = existing == null
        ? user
        : user.copyWith(status: existing.status);

    notifyListeners();
  }

  void _handleUserLeave(int userId) {
    final user = users[userId];
    users[userId] = user == null
        ? User(
            id: userId,
            name: 'unknown',
            profileColor: fallbackProfileColor,
            status: UserStatus.offline,
            roleIds: const <int>[],
          )
        : user.copyWith(status: UserStatus.offline);

    notifyListeners();
  }

  void _handleChannelCreate(Channel channel) {
    if (channels.any((existing) => existing.id == channel.id)) {
      _handleChannelUpdate(channel);

      return;
    }

    channels = <Channel>[...channels, channel];
    notifyListeners();
  }

  void _handleChannelUpdate(Channel channel) {
    channels = <Channel>[
      for (final existing in channels)
        if (existing.id == channel.id) channel else existing,
    ];
    notifyListeners();
  }

  void _handleChannelDelete(int channelId) {
    channels = channels
        .where((channel) => channel.id != channelId)
        .toList(growable: false);
    readStates.remove(channelId);
    messages.clearChannel(channelId);

    if (selectedChannelId == channelId) {
      selectedChannelId = _firstOrNull(textChannels)?.id;
    }

    notifyListeners();
  }

  void _handleReadStateUpdate(ChannelReadStateEvent event) {
    readStates[event.channelId] = event.count;
    notifyListeners();
  }

  void _handleReadStateDelta(ChannelReadStateDeltaEvent event) {
    // the channel on screen is already being marked read, and that response is
    // the authoritative count
    if (event.channelId == selectedChannelId) return;

    final current = readStates[event.channelId] ?? 0;

    readStates[event.channelId] = (current + event.delta)
        .clamp(0, 9999)
        .toInt();
    notifyListeners();
  }

  void _handleDmConversationOpen(int channelId) {
    unawaited(_loadDirectMessages());
  }

  void _handleVoiceJoin(VoiceUserEvent event) {
    voiceMap = voiceMap.withUser(
      event.channelId,
      event.userId,
      event.state ?? const VoiceUserState(),
    );
    notifyListeners();
  }

  void _handleVoiceLeave(VoiceUserEvent event) {
    voice.handleUserLeft(event.channelId, event.userId);
    voiceMap = voiceMap.withoutUser(event.channelId, event.userId);
    notifyListeners();
  }

  void _handleVoiceState(VoiceUserEvent event) {
    final state = event.state;
    if (state == null) return;

    voiceMap = voiceMap.updateState(event.channelId, event.userId, state);
    notifyListeners();
  }

  void _handleVoiceProducerAdded(VoiceProducerEvent event) {
    voice.handleProducerAdded(event);
  }

  void _handleVoiceProducerClosed(VoiceProducerEvent event) {
    voice.handleProducerClosed(event);
  }

  // ------------------------------------------------------------------ actions

  Future<void> selectChannel(int channelId) async {
    if (selectedChannelId == channelId) return;

    selectedChannelId = channelId;
    isTypingNotified = false;
    notifyListeners();

    await _ensureChannelLoaded(channelId);
    unawaited(_markRead(channelId, force: true));
  }

  Future<void> _ensureChannelLoaded(int channelId) async {
    final api = _api;
    if (api == null) return;

    if (messages.isLoaded(channelId)) return;

    messages.beginLoad(channelId);
    notifyListeners();

    try {
      final page = await api.getMessages(channelId: channelId);
      messages.applyPage(channelId, page);
    } on ApiException catch (error) {
      messages.failLoad(channelId, error.message);
    }

    notifyListeners();
  }

  Future<void> loadOlder(int channelId) async {
    final api = _api;
    if (api == null || !messages.isLoaded(channelId)) return;

    final channel = messages.of(channelId);

    if (channel.isLoadingOlder || channel.reachedStart) {
      return;
    }

    channel.isLoadingOlder = true;
    notifyListeners();

    try {
      final page = await api.getMessages(
        channelId: channelId,
        cursor: channel.cursor,
      );
      messages.applyPage(channelId, page);
    } on ApiException catch (error) {
      messages.failLoad(channelId, error.message);
    }

    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    final api = _api;
    final channelId = selectedChannelId;

    if (api == null || channelId == null) return;

    final content = MessageText.buildOutgoing(text);
    if (content.isEmpty) return;

    await api.sendMessage(channelId: channelId, content: content);
  }

  Future<void> notifyTyping() async {
    final api = _api;
    final channelId = selectedChannelId;

    if (api == null || channelId == null || isTypingNotified) return;

    isTypingNotified = true;

    // the server rate limits this to a handful per window, so it is sent once
    // per composing burst rather than on every keystroke
    Timer(const Duration(seconds: 3), () => isTypingNotified = false);

    try {
      await api.signalTyping(channelId);
    } on ApiException {
      isTypingNotified = false;
    }
  }

  Future<void> toggleReaction(Message message, String emoji) async {
    final api = _api;
    if (api == null) return;

    await api.toggleReaction(messageId: message.id, emoji: emoji);
  }

  Future<void> openDirectMessage(int userId) async {
    final api = _api;
    if (api == null) return;

    final channelId = await api.openDirectMessage(userId);

    await _loadDirectMessages();
    await selectChannel(channelId);
  }

  Future<void> _markRead(int channelId, {bool force = false}) async {
    final api = _api;
    if (api == null) return;

    final last = _lastReadAt[channelId];
    if (!force &&
        last != null &&
        DateTime.now().difference(last).inSeconds < 2) {
      return;
    }

    _lastReadAt[channelId] = DateTime.now();

    try {
      await api.markAsRead(channelId);
    } on ApiException {
      // a read receipt is not worth surfacing to the user
    }
  }

  Future<void> _loadDirectMessages() async {
    final api = _api;
    if (api == null) return;

    try {
      dmConversations = await api.getDirectMessages();
      notifyListeners();
    } on ApiException {
      dmConversations = <DirectMessageConversation>[];
    }
  }

  // -------------------------------------------------------------- selectors

  void _setPhase(SessionPhase next, {String? error, String? status}) {
    phase = next;
    errorMessage = error;
    statusMessage = status;

    if (next != SessionPhase.ready) connectionLost = false;

    notifyListeners();
  }

  /// true while a connection is being established, so the connect screen can
  /// disable its button and show a spinner.
  bool get isBusy =>
      phase == SessionPhase.starting || phase == SessionPhase.connecting;

  /// the address every relative file url is resolved against.
  String? get serverBaseUrl => endpoint?.httpBase;

  String? get serverName => serverInfo?.name;

  /// drops the realtime socket and rebuilds it, keeping the token and the
  /// currently selected channel. Used by the banner shown while it is down.
  Future<void> reconnect() async {
    connectionLost = false;
    notifyListeners();

    await _socket?.reconnect();
  }

  /// a problem the connect screen spots before a request (an empty field, for
  /// instance) so it lands in the same banner as the server's own errors.
  void setTransientError(String message) {
    errorMessage = message;
    notifyListeners();
  }

  void clearError() {
    errorMessage = null;

    if (phase == SessionPhase.failed) {
      phase = SessionPhase.unauthenticated;
    }

    notifyListeners();
  }

  User? get ownUser => users[ownUserId];

  Channel? get selectedChannel {
    final channelId = selectedChannelId;
    if (channelId == null) return null;

    return channelById(channelId);
  }

  Channel? channelById(int channelId) =>
      _firstOrNull(channels.where((channel) => channel.id == channelId));

  List<Channel> get textChannels =>
      channels
          .where((channel) => channel.type == ChannelType.text && !channel.isDm)
          .toList(growable: false)
        ..sort((a, b) => a.position.compareTo(b.position));

  List<Channel> get voiceChannels =>
      channels
          .where(
            (channel) => channel.type == ChannelType.voice && !channel.isDm,
          )
          .toList(growable: false)
        ..sort((a, b) => a.position.compareTo(b.position));

  List<Channel> get directMessageChannels =>
      channels.where((channel) => channel.isDm).toList(growable: false);

  List<Channel> textChannelsIn(int? categoryId) => textChannels
      .where((channel) => channel.categoryId == categoryId)
      .toList(growable: false);

  List<Channel> voiceChannelsIn(int? categoryId) => voiceChannels
      .where((channel) => channel.categoryId == categoryId)
      .toList(growable: false);

  List<Category> get orderedCategories {
    final sorted = <Category>[...categories]
      ..sort((a, b) => a.position.compareTo(b.position));

    return sorted;
  }

  List<User> get orderedUsers {
    final sorted = users.values.toList()
      ..sort((a, b) {
        if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;

        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return sorted;
  }

  User? userById(int? userId) => userId == null ? null : users[userId];

  bool get dmsEnabled => settings?.directMessagesEnabled ?? false;

  int unreadFor(int channelId) => readStates[channelId] ?? 0;

  User? dmPartnerOf(Channel channel) {
    for (final conversation in dmConversations) {
      if (conversation.channelId == channel.id) {
        return users[conversation.userId];
      }
    }

    return null;
  }

  DirectMessageConversation? conversationFor(int channelId) => _firstOrNull(
    dmConversations.where(
      (conversation) => conversation.channelId == channelId,
    ),
  );

  /// the server answers "may this user do X in this channel" with a rule of its
  /// own: a dm is membership only, a public channel grants everything, and only
  /// a private channel falls through to the override map. that map is what the
  /// join payload carries, it holds the overrides alone and defaults to false,
  /// so reading it on its own locks every public channel. the rule is
  /// reproduced here before the map is trusted.
  bool canInChannel(int channelId, String permission) {
    final channel = channelById(channelId);
    if (channel == null) return false;

    if (channel.isDm || !channel.private) return true;

    // the owner role skips the override table altogether, exactly as the server
    // does, so a private channel does not lock the person running the server
    if (isOwner) return true;

    return channelPermissions[channelId]?[permission] ?? false;
  }

  bool get isOwner {
    final user = users[ownUserId];
    if (user == null) return false;

    return user.roleIds.contains(_ownerRoleId);
  }

  /// the union of the own user's role permissions: what the server checks
  /// globally, before it ever looks at a channel
  bool hasPermission(String permission) {
    if (isOwner) return true;

    final user = users[ownUserId];
    if (user == null) return false;

    for (final role in roles) {
      if (!user.roleIds.contains(role.id)) continue;
      if (role.can(permission)) return true;
    }

    return false;
  }

  bool canSendIn(int channelId) =>
      hasPermission('SEND_MESSAGES') &&
      canInChannel(channelId, 'SEND_MESSAGES');

  /// sending is a server wide permission checked before the channel one, and
  /// reacting is only that global permission: the channel just has to be visible
  bool canReactIn(int channelId) =>
      hasPermission('REACT_TO_MESSAGES') &&
      canInChannel(channelId, 'VIEW_CHANNEL');

  /// the colour a name is written in: a member's highest tinted role, falling
  /// back to the plain text colour for the default role.
  Color roleColorFor(User user) {
    Role? tinted;

    for (final role in roles) {
      if (!user.roleIds.contains(role.id)) continue;
      if (!role.isTintable) continue;

      if (tinted == null || role.id < tinted.id) tinted = role;
    }

    return tinted?.color ?? AppColors.text;
  }
}

/// the list helpers this file needs, written out rather than pulled in from
/// package:collection for two call sites.
T? _firstOrNull<T>(Iterable<T> items) => items.isEmpty ? null : items.first;

/// the owner role is seeded with every permission and passes every global check
/// the server makes
const int _ownerRoleId = 1;
