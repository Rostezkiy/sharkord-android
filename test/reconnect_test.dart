import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sharkord_flutter/api/server_endpoint.dart';
import 'package:sharkord_flutter/api/trpc_socket.dart';

/// the smallest tRPC websocket server the client can talk to: it answers every call with
/// a canned result and keeps the frames of each connection in arrival order, which is
/// what the reconnect ordering is asserted on.
class _FakeTrpcServer {
  _FakeTrpcServer._(this._http);

  static Future<_FakeTrpcServer> start() async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = _FakeTrpcServer._(http);

    http.listen(server._handleRequest);

    return server;
  }

  final HttpServer _http;
  final Map<int, List<String>> _frames = <int, List<String>>{};
  final List<WebSocket> _sockets = <WebSocket>[];

  int connections = 0;

  String get baseUrl => 'http://127.0.0.1:${_http.port}';

  Future<void> _handleRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();

      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    final connection = ++connections;

    _frames[connection] = <String>[];
    _sockets.add(socket);

    socket.listen((Object? raw) => _handleFrame(socket, connection, raw));
  }

  void _handleFrame(WebSocket socket, int connection, Object? raw) {
    if (raw is! String) return;

    // the liveness ping is answered but is not a frame the ordering below cares about
    if (raw == 'PING') {
      _send(socket, 'PONG');

      return;
    }

    if (raw == 'PONG') return;

    final decoded = jsonDecode(raw);

    if (decoded is! Map) return;

    if (decoded['method'] == 'connectionParams') {
      _frames[connection]!.add('connectionParams');

      return;
    }

    final id = decoded['id'];
    final method = decoded['method'];
    final params = decoded['params'];
    final path = params is Map ? params['path'] : null;

    _frames[connection]!.add('$method:$path');

    if (method == 'subscription') {
      _send(
        socket,
        jsonEncode(<String, Object?>{
          'id': id,
          'result': <String, Object?>{'type': 'started'},
        }),
      );

      return;
    }

    _send(
      socket,
      jsonEncode(<String, Object?>{
        'id': id,
        'result': <String, Object?>{
          'type': 'data',
          'data': const <String, Object?>{'ok': true},
        },
      }),
    );
  }

  /// a frame can still arrive while the connection is being torn down at the end of a
  /// test, and adding to a sink that is already closed throws.
  void _send(WebSocket socket, String payload) {
    try {
      socket.add(payload);
    } on StateError {
      return;
    }
  }

  /// waits until [connection] has received every frame in [expected] and answers the
  /// frames of that connection in arrival order.
  Future<List<String>> waitForFrames(
    int connection,
    List<String> expected,
  ) async {
    for (var attempt = 0; attempt < 500; attempt++) {
      final received = _frames[connection] ?? const <String>[];

      if (expected.every(received.contains)) return received;

      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    throw StateError('connection $connection never received $expected');
  }

  /// closes the server side of every connection, which is how a socket dies while the
  /// app is in the background.
  Future<void> dropConnections() async {
    for (final socket in List<WebSocket>.from(_sockets)) {
      await socket.close();
    }

    _sockets.clear();
  }

  Future<void> stop() async {
    await dropConnections();
    await _http.close(force: true);
  }
}

void main() {
  test('a reconnect joins the session again before it resubscribes', () async {
    final server = await _FakeTrpcServer.start();
    addTearDown(server.stop);

    var reconnects = 0;

    late final TrpcSocket socket;
    socket = TrpcSocket(
      endpoint: ServerEndpoint.parse(server.baseUrl),
      token: 'test-token',
      // what the app passes in: the session has to be established again on the new
      // socket, since the server counts a connection as unauthenticated until it joined
      onReconnect: () async {
        reconnects += 1;

        await socket.query('others.joinServer', const <String, Object?>{
          'handshakeHash': 'hash',
        });
      },
    );
    addTearDown(socket.close);

    await socket.connect();

    final events = socket.subscribe('test.events');
    addTearDown(events.listen((_) {}).cancel);

    await server.waitForFrames(1, <String>[
      'connectionParams',
      'subscription:test.events',
    ]);

    await server.dropConnections();

    final frames = await server.waitForFrames(2, <String>[
      'connectionParams',
      'query:others.joinServer',
      'subscription:test.events',
    ]);

    expect(reconnects, 1);
    expect(socket.state, TrpcConnectionState.connected);

    // the join has to reach the server before the resubscribe: it refuses a subscription
    // on a connection that never joined, which is what left the app telling the user it
    // was not authenticated until the app was restarted
    expect(
      frames.indexOf('query:others.joinServer'),
      lessThan(frames.indexOf('subscription:test.events')),
    );
  });
}
