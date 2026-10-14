import 'package:flutter_test/flutter_test.dart';

import 'package:sharkord_flutter/api/server_endpoint.dart';
import 'package:sharkord_flutter/api/sharkord_api.dart';
import 'package:sharkord_flutter/api/trpc_socket.dart';

/// answers every call with the payload the test is about, so the parsing rules of
/// the api can be checked without a server behind it.
class _FakeSocket extends TrpcSocket {
  _FakeSocket(this.answers)
    : super(endpoint: ServerEndpoint.parse('localhost:4991'), token: 'test');

  final Map<String, Object?> answers;

  @override
  Future<Object?> mutate(String path, [Object? input]) async => answers[path];

  @override
  Future<Object?> query(String path, [Object? input]) async => answers[path];
}

void main() {
  test(
    'joinVoice answers with the router capabilities the device loads',
    () async {
      final api = SharkordApi(
        _FakeSocket(<String, Object?>{
          'voice.join': <String, Object?>{
            'routerRtpCapabilities': <String, Object?>{
              'codecs': <Object?>[
                <String, Object?>{'mimeType': 'audio/opus'},
              ],
              'headerExtensions': <Object?>[],
            },
          },
        }),
      );

      final capabilities = await api.joinVoice(
        channelId: 3,
        micMuted: false,
        soundMuted: false,
      );

      // the device reads `codecs` off this map, so handing it the envelope instead
      // of the capabilities throws on a null list before anything is negotiated
      expect(capabilities['codecs'], isNotEmpty);
      expect(capabilities.containsKey('routerRtpCapabilities'), isFalse);
    },
  );

  test(
    'joinVoice survives a server that answers without capabilities',
    () async {
      final api = SharkordApi(
        _FakeSocket(<String, Object?>{'voice.join': null}),
      );

      final capabilities = await api.joinVoice(
        channelId: 3,
        micMuted: false,
        soundMuted: false,
      );

      expect(capabilities, isEmpty);
    },
  );
}
