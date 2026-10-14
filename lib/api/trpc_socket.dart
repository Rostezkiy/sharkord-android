import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_exception.dart';
import 'server_endpoint.dart';

enum TrpcConnectionState { disconnected, connecting, connected, reconnecting }

/// one long-lived subscription, kept across reconnects so a dropped socket does
/// not silently stop the realtime feed.
class _Subscription {
  _Subscription(this.path, this.input, this.controller);

  final String path;
  final Object? input;
  final StreamController<Object?> controller;

  int? requestId;
  bool cancelled = false;
}

/// the tRPC v11 websocket protocol, spoken by hand: a request is
/// `{"id":1,"method":"query","params":{"path":"...","input":...}}` and the answer
/// is `{"id":1,"result":{"type":"data","data":...}}` or `{"id":1,"error":{...}}`.
class TrpcSocket {
  TrpcSocket({required this.endpoint, required this.token, this.onReconnect});

  final ServerEndpoint endpoint;
  final String token;

  /// runs on every reconnect, right after the new socket is up and before anything is
  /// sent on it: the server treats each connection as unauthenticated until the
  /// session has been established on that connection again.
  final Future<void> Function()? onReconnect;

  final StreamController<TrpcConnectionState> _stateController =
      StreamController<TrpcConnectionState>.broadcast();
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  final List<_Subscription> _subscriptions = <_Subscription>[];

  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _incoming;
  Timer? _heartbeat;
  int _nextId = 1;
  bool _closedByUs = false;
  bool _reconnecting = false;

  DateTime _lastInboundAt = DateTime.now();

  Stream<TrpcConnectionState> get connectionState => _stateController.stream;

  TrpcConnectionState _state = TrpcConnectionState.disconnected;
  TrpcConnectionState get state => _state;

  /// the server pings every 30 seconds, so a socket that has said nothing for much
  /// longer than that is gone even when nothing reported it yet: android suspends the
  /// app in the background and the connection can die there without an error.
  bool get isSilent =>
      DateTime.now().difference(_lastInboundAt) > const Duration(seconds: 70);

  Future<void> connect() async {
    _closedByUs = false;
    _setState(TrpcConnectionState.connecting);
    await _open();
    _setState(TrpcConnectionState.connected);
  }

  Future<void> _open() async {
    final channel = WebSocketChannel.connect(endpoint.websocketUri);
    await channel.ready;

    _channel = channel;
    _incoming = channel.stream.listen(
      _handleMessage,
      onDone: _handleClosed,
      onError: (_) => _handleClosed(),
      cancelOnError: false,
    );

    // must be the very first frame: the server builds the connection context from it
    _send(<String, Object?>{
      'method': 'connectionParams',
      'data': <String, Object?>{'token': token},
    });

    _lastInboundAt = DateTime.now();

    _startHeartbeat();
  }

  Future<Object?> query(String path, [Object? input]) =>
      _request('query', path, input);

  Future<Object?> mutate(String path, [Object? input]) =>
      _request('mutation', path, input);

  Stream<Object?> subscribe(String path, [Object? input]) {
    final controller = StreamController<Object?>();
    final subscription = _Subscription(path, input, controller);

    controller.onListen = () {
      _subscriptions.add(subscription);
      _startSubscription(subscription);
    };
    controller.onCancel = () {
      subscription.cancelled = true;
      _subscriptions.remove(subscription);

      final requestId = subscription.requestId;
      if (requestId != null) {
        _pending.remove(requestId);
        _send(<String, Object?>{
          'id': requestId,
          'method': 'subscription.stop',
        });
      }

      return controller.close();
    };

    return controller.stream;
  }

  void _startSubscription(_Subscription subscription) {
    final id = _nextId++;

    subscription.requestId = id;
    _send(<String, Object?>{
      'id': id,
      'method': 'subscription',
      'params': <String, Object?>{
        'path': subscription.path,
        if (subscription.input != null) 'input': subscription.input,
      },
    });
  }

  Future<Object?> _request(String method, String path, Object? input) {
    final channel = _channel;
    if (channel == null) {
      throw const ApiException('Not connected to the server', code: 'CLOSED');
    }

    final id = _nextId++;
    final completer = Completer<Object?>();

    _pending[id] = completer;

    _send(<String, Object?>{
      'id': id,
      'method': method,
      'params': <String, Object?>{
        'path': path,
        // a void input must be omitted, not sent as null: the server validates it
        // against z.void() before the handler runs
        'input': ?input,
      },
    });

    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _pending.remove(id);

        throw const ApiException(
          'The server did not answer in time',
          code: 'TIMEOUT',
        );
      },
    );
  }

  void _send(Map<String, Object?> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  void _handleMessage(Object? raw) {
    _lastInboundAt = DateTime.now();
    if (raw is String) {
      // the server pings on a 30 second timer and kills the socket when nothing
      // comes back within 5 seconds, so this answer is not optional
      if (raw == 'PING') {
        _channel?.sink.add('PONG');
        return;
      }

      if (raw == 'PONG') return;
    }

    final Object? decoded;
    try {
      decoded = raw is String ? jsonDecode(raw) : null;
    } on FormatException {
      return;
    }

    final items = decoded is List ? decoded : <Object?>[decoded];

    for (final item in items) {
      if (item is! Map) continue;

      _handleEnvelope(item.cast<String, dynamic>());
    }
  }

  void _handleEnvelope(Map<String, dynamic> envelope) {
    // the server asks every client to reconnect when it is shutting down
    if (envelope['method'] == 'reconnect') {
      unawaited(reconnect());

      return;
    }

    final id = envelope['id'] is int ? envelope['id'] as int : null;
    if (id == null) {
      final error = envelope['error'];
      if (error != null) {
        _failEverything(ApiException.fromTrpcError(error));
      }

      return;
    }

    final result = envelope['result'];
    final error = envelope['error'];

    if (error != null) {
      final exception = ApiException.fromTrpcError(error);
      final subscription = _findSubscription(id);

      if (subscription != null) {
        subscription.controller.addError(exception);
        subscription.requestId = null;
        return;
      }

      _pending.remove(id)?.completeError(exception);

      return;
    }

    if (result is! Map) return;

    final type = result['type'];

    if (type == 'started') return;

    final subscription = _findSubscription(id);

    if (type == 'stopped') {
      subscription?.requestId = null;
      return;
    }

    final data = result['data'];

    // a subscription may emit many payloads over the life of one request id
    if (subscription != null) {
      subscription.controller.add(data);
      return;
    }

    _pending.remove(id)?.complete(data);
  }

  _Subscription? _findSubscription(int id) {
    for (final subscription in _subscriptions) {
      if (subscription.requestId == id) return subscription;
    }

    return null;
  }

  void _handleClosed() {
    if (_closedByUs) return;

    _failPending();

    if (_reconnecting) return;

    unawaited(reconnect());
  }

  /// re-establishes the socket and every subscription that was still open, so a
  /// network blip or a laptop waking up does not leave a dead channel on screen.
  Future<void> reconnect() async {
    if (_closedByUs || _reconnecting) return;

    _reconnecting = true;
    _setState(TrpcConnectionState.reconnecting);

    try {
      for (var attempt = 0; attempt < 6; attempt++) {
        final delay = Duration(milliseconds: 500 * (attempt + 1));

        await Future<void>.delayed(delay);

        if (_closedByUs) return;

        try {
          await _incoming?.cancel();
          await _channel?.sink.close();
          await _open();

          // the resubscribe below is refused on a connection that has not joined
          // again, so the session is established on it first
          await onReconnect?.call();

          for (final subscription in _subscriptions) {
            _startSubscription(subscription);
          }

          _setState(TrpcConnectionState.connected);

          return;
        } catch (_) {
          continue;
        }
      }

      _setState(TrpcConnectionState.disconnected);
      _failEverything(
        const ApiException('Lost connection to the server', code: 'CLOSED'),
      );
    } finally {
      _reconnecting = false;
    }
  }

  Future<void> close() async {
    _closedByUs = true;
    _heartbeat?.cancel();

    for (final subscription in _subscriptions) {
      await subscription.controller.close();
    }
    _subscriptions.clear();

    _failPending();

    await _incoming?.cancel();
    await _channel?.sink.close();
    _channel = null;

    _setState(TrpcConnectionState.disconnected);
    await _stateController.close();
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      // a closed socket is not always reported as closed, which is what happens when
      // android suspends the app with it open: rebuild it instead of writing into a
      // dead connection
      if (isSilent) {
        unawaited(reconnect());

        return;
      }

      _channel?.sink.add('PING');
    });
  }

  void _failPending() {
    final pending = List<Completer<Object?>>.from(_pending.values);
    _pending.clear();

    for (final completer in pending) {
      if (completer.isCompleted) continue;

      completer.completeError(
        const ApiException('Connection to the server was lost', code: 'CLOSED'),
      );
    }
  }

  void _failEverything(ApiException exception) {
    _failPending();

    for (final subscription in _subscriptions) {
      subscription.requestId = null;

      if (!subscription.controller.isClosed) {
        subscription.controller.addError(exception);
      }
    }
  }

  void _setState(TrpcConnectionState state) {
    _state = state;

    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }
}
