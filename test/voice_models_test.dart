import 'package:flutter_test/flutter_test.dart';

import 'package:sharkord_flutter/models/voice.dart';

void main() {
  group('StreamKind', () {
    test('reads the wire values the server uses', () {
      expect(StreamKind.fromWire('audio'), StreamKind.audio);
      expect(StreamKind.fromWire('screen_audio'), StreamKind.screenAudio);
      expect(StreamKind.fromWire('external_audio'), StreamKind.externalAudio);
      expect(StreamKind.fromWire('video'), StreamKind.video);
    });

    test('falls back to audio on an unknown value', () {
      expect(StreamKind.fromWire('nope'), StreamKind.audio);
      expect(StreamKind.fromWire(null), StreamKind.audio);
    });

    test('maps every audio kind onto mediasoup audio', () {
      expect(StreamKind.audio.isAudio, isTrue);
      expect(StreamKind.screenAudio.isAudio, isTrue);
      expect(StreamKind.externalAudio.isAudio, isTrue);
      expect(StreamKind.video.isAudio, isFalse);
      expect(StreamKind.screen.isAudio, isFalse);
      expect(StreamKind.externalVideo.isAudio, isFalse);
    });
  });

  test('getProducers is parsed into per kind listener ids', () {
    final ids = VoiceProducerIds.fromJson(<String, dynamic>{
      'remoteAudioIds': <Object?>[1, 2],
      'remoteVideoIds': <Object?>[2],
      'remoteScreenIds': <Object?>[],
      'remoteScreenAudioIds': <Object?>[3],
      'remoteExternalStreamIds': <Object?>[7],
    });

    expect(ids.audio, <int>[1, 2]);
    expect(ids.video, <int>[2]);
    expect(ids.screen, isEmpty);
    expect(ids.screenAudio, <int>[3]);
    expect(ids.externalStreams, <int>[7]);
  });

  test('getProducers survives a payload with missing keys', () {
    final ids = VoiceProducerIds.fromJson(const <String, dynamic>{});

    expect(ids.audio, isEmpty);
    expect(ids.externalStreams, isEmpty);
  });

  test('a consume answer carries what the mediasoup consumer needs', () {
    final params = VoiceConsumerParams.fromJson(<String, dynamic>{
      'producerId': 'producer-1',
      'consumerId': 'consumer-1',
      'consumerKind': 'audio',
      'consumerRtpParameters': <String, dynamic>{'codecs': <Object?>[]},
    });

    expect(params.producerId, 'producer-1');
    expect(params.consumerId, 'consumer-1');
    expect(params.kind, StreamKind.audio);
    expect(params.rtpParameters['codecs'], isEmpty);
  });

  test('a producer event is read from the channel scoped subscriptions', () {
    final event = VoiceProducerEvent.fromJson(<String, dynamic>{
      'channelId': 4,
      'remoteId': 9,
      'kind': 'screen_audio',
    });

    expect(event.channelId, 4);
    expect(event.remoteId, 9);
    expect(event.kind, StreamKind.screenAudio);
  });

  group('VoiceMap', () {
    test('is read from the join payload and updated in place', () {
      final map = VoiceMap.fromJson(<String, dynamic>{
        '3': <String, dynamic>{
          'users': <String, dynamic>{
            '1': <String, dynamic>{'micMuted': true, 'soundMuted': false},
          },
        },
      });

      expect(map.countIn(3), 1);
      expect(map.usersIn(3)[1]?.micMuted, isTrue);

      final joined = map.withUser(3, 2, const VoiceUserState());
      expect(joined.countIn(3), 2);

      final updated = joined.updateState(
        3,
        2,
        const VoiceUserState(soundMuted: true),
      );
      expect(updated.usersIn(3)[2]?.soundMuted, isTrue);

      expect(updated.withoutUser(3, 1).countIn(3), 1);
    });

    test('ignores a state update for someone who is not there', () {
      const map = VoiceMap.empty;

      expect(
        map.updateState(1, 1, const VoiceUserState(micMuted: true)),
        same(map),
      );
    });
  });
}
