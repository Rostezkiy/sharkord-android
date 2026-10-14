import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mediasfu_mediasoup_client/mediasfu_mediasoup_client.dart'
    as mediasoup;

import '../api/api_exception.dart';
import '../api/sharkord_api.dart';
import '../models/voice.dart';

/// where a voice session is, from the UI's point of view.
enum VoiceStatus {
  /// not in a voice channel
  idle,

  /// joined on the server, media still being negotiated
  connecting,

  /// media flows both ways
  connected,

  /// the session could not be established, [VoiceController.errorMessage] says
  /// why
  failed,
}

/// a failure of the media session itself, as opposed to an error the server
/// answered with.
class VoiceSetupException implements Exception {
  const VoiceSetupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// owns one voice session: the mediasoup device, the send and the receive
/// transport, the microphone producer and one consumer per remote stream.
///
/// The server is an SFU, so nothing here is peer to peer. The client asks the
/// server to create a transport, connects it over DTLS, publishes the
/// microphone through it and subscribes to every other producer in the channel.
/// Signaling goes through [SharkordApi]; the RTP/ORTC negotiation itself is the
/// mediasoup client's job.
class VoiceController extends ChangeNotifier {
  SharkordApi? _api;
  int _ownUserId = 0;

  VoiceStatus status = VoiceStatus.idle;
  String? errorMessage;

  /// the channel this session is for, null when not in one.
  int? channelId;

  bool micMuted = false;
  bool soundMuted = false;

  /// a free-text line used by the voice panel to show what the session is doing
  /// while it connects, and how many streams are coming in once it is up.
  String? detail;

  /// set when the microphone could not be opened. The session stays usable, the
  /// microphone is the only part that is missing.
  String? micError;

  mediasoup.Device? _device;
  mediasoup.Transport? _sendTransport;
  mediasoup.Transport? _recvTransport;
  mediasoup.Producer? _micProducer;
  MediaStream? _micStream;

  /// one consumer per remote stream, keyed `<remoteId>:<kind>`.
  final Map<String, mediasoup.Consumer> _consumers =
      <String, mediasoup.Consumer>{};

  /// the consumer callback of the receive transport is global, so the consumer
  /// it hands back is matched to the request waiting for it.
  final List<Completer<mediasoup.Consumer>> _pendingConsumers =
      <Completer<mediasoup.Consumer>>[];

  /// consumes are serialized: exactly one is in flight, which is what makes the
  /// single pending completer above unambiguous.
  Future<void> _consumeChain = Future<void>.value();

  final Set<String> _consuming = <String>{};

  bool _tearingDown = false;
  bool _startingMic = false;

  bool get isActive => status != VoiceStatus.idle;
  bool get isConnected => status == VoiceStatus.connected;
  bool get isBusy => status == VoiceStatus.connecting;
  bool get isInChannel => channelId != null;

  int get remoteStreamCount => _consumers.length;

  /// called by the session when it has an api to signal with. Everything is
  /// dropped again in [detach], because a new session means a new socket.
  void attach({required SharkordApi api, required int ownUserId}) {
    _api = api;
    _ownUserId = ownUserId;
  }

  Future<void> detach() async {
    _api = null;
    await _teardown();
  }

  // ------------------------------------------------------------------ session

  Future<void> join(int targetChannelId) async {
    final api = _api;
    if (api == null) return;

    if (isInChannel) {
      if (channelId == targetChannelId) return;

      await leave();
    }

    channelId = targetChannelId;
    status = VoiceStatus.connecting;
    errorMessage = null;
    micError = null;
    _setDetail('joining');
    _notify();

    try {
      final capabilities = await api.joinVoice(
        channelId: targetChannelId,
        micMuted: micMuted,
        soundMuted: soundMuted,
      );

      _setDetail('loading the device');
      final device = mediasoup.Device();

      await device.load(
        routerRtpCapabilities: mediasoup.RtpCapabilities.fromMap(capabilities),
      );
      _device = device;

      _setDetail('creating transports');
      await _createSendTransport(api, device);
      await _createRecvTransport(api, device);

      _setDetail('subscribing to streams');
      await _consumeExistingProducers(api);

      _setDetail('opening the microphone');
      await _startMicrophone();

      status = VoiceStatus.connected;
      _setDetail(null);
      _notify();

      if (Platform.isAndroid) {
        // without this the call comes out of the earpiece on a phone
        await Helper.setSpeakerphoneOn(true);
      }
    } on ApiException catch (error) {
      await _fail(error.message);
    } on VoiceSetupException catch (error) {
      await _fail(error.message);
    } catch (error) {
      await _fail('${error is Exception ? error : error.toString()}');
    }
  }

  Future<void> leave() async {
    final api = _api;

    if (api != null) {
      try {
        await api.leaveVoice();
      } on ApiException {
        // the server may already have dropped the session (a moderator moved
        // us, or the socket reconnected), which is not worth reporting
      }
    }

    await _teardown();
    _notify();
  }

  Future<void> _fail(String message) async {
    final api = _api;

    if (api != null) {
      try {
        await api.leaveVoice();
      } on ApiException {
        // nothing to undo remotely when the join never completed
      }
    }

    await _teardown();

    status = VoiceStatus.failed;
    errorMessage = message;
    _notify();
  }

  /// drops the session without telling the server, for a socket that is already
  /// gone: the server cleans its side up when the connection closes.
  Future<void> resetLocal() async {
    await _teardown();
    _notify();
  }

  /// clears the error banner left by [VoiceStatus.failed].
  void dismissError() {
    errorMessage = null;

    if (status == VoiceStatus.failed) status = VoiceStatus.idle;

    _notify();
  }

  Future<void> _teardown() async {
    if (_tearingDown) return;

    _tearingDown = true;

    try {
      for (final consumer in _consumers.values) {
        await consumer.close();
      }
      _consumers.clear();
      _consuming.clear();
      _pendingConsumers.clear();

      _micProducer?.close();
      _micProducer = null;

      await _sendTransport?.close();
      await _recvTransport?.close();
      _sendTransport = null;
      _recvTransport = null;
      _device = null;

      await _stopMicrophone();
    } catch (error) {
      debugPrint('voice teardown: $error');
    } finally {
      _tearingDown = false;
    }

    channelId = null;
    status = VoiceStatus.idle;
    detail = null;
    micError = null;
  }

  // -------------------------------------------------------------- transports

  Future<void> _createSendTransport(
    SharkordApi api,
    mediasoup.Device device,
  ) async {
    final params = await api.createProducerTransport();

    final transport = device.createSendTransportFromMap(
      params,
      producerCallback: _handleProducer,
    );

    transport.on('connect', _connectHandler(api.connectProducerTransport));
    transport.on('produce', _produceHandler(api));
    transport.on('connectionstatechange', (dynamic data) {
      _handleConnectionState('send', data);
    });

    _sendTransport = transport;
  }

  Future<void> _createRecvTransport(
    SharkordApi api,
    mediasoup.Device device,
  ) async {
    final params = await api.createConsumerTransport();

    final transport = device.createRecvTransportFromMap(
      params,
      consumerCallback: _handleConsumer,
    );

    transport.on('connect', _connectHandler(api.connectConsumerTransport));
    transport.on('connectionstatechange', (dynamic data) {
      _handleConnectionState('recv', data);
    });

    _recvTransport = transport;
  }

  /// the transport asks for a DTLS connection before it can carry anything,
  /// which is the one extra round trip the server has to make.
  Function _connectHandler(
    Future<void> Function(Map<String, dynamic>) connect,
  ) {
    return (dynamic raw) async {
      final data = _asMap(raw);
      final callback = data['callback'] as Function?;
      final errback = data['errback'] as Function?;
      final dtlsParameters = data['dtlsParameters'] as mediasoup.DtlsParameters;

      try {
        await connect(dtlsParameters.toMap());
        callback?.call();
      } on ApiException catch (error) {
        errback?.call(VoiceSetupException(error.message));
      } catch (error) {
        errback?.call(error);
      }
    };
  }

  Function _produceHandler(SharkordApi api) {
    return (dynamic raw) async {
      final data = _asMap(raw);
      final callback = data['callback'] as Function?;
      final errback = data['errback'] as Function?;
      final appData = _asMap(data['appData']);
      final rtpParameters = data['rtpParameters'] as mediasoup.RtpParameters;
      final kind = StreamKind.fromWire(appData['kind']);
      final transport = _sendTransport;

      if (transport == null) {
        errback?.call(const VoiceSetupException('Sending transport is gone'));

        return;
      }

      try {
        final producerId = await api.produce(
          transportId: transport.id,
          kind: kind,
          rtpParameters: rtpParameters.toMap(),
        );

        callback?.call(producerId);
      } on ApiException catch (error) {
        // the usual cause is a missing SPEAK permission in this channel
        errback?.call(VoiceSetupException(error.message));
      } catch (error) {
        errback?.call(error);
      }
    };
  }

  void _handleConnectionState(String which, dynamic raw) {
    final state = '${_asMap(raw)['connectionState']}';

    debugPrint('voice: $which transport is $state');

    if (state != 'failed') return;

    _sendTransport?.close();
    _recvTransport?.close();
  }

  void _handleProducer(mediasoup.Producer producer) {
    if (producer.appData['kind'] == StreamKind.audio.wire) {
      _micProducer = producer;
    }

    _notify();
  }

  void _handleConsumer(mediasoup.Consumer consumer, dynamic accept) {
    if (_pendingConsumers.isEmpty) return;

    final completer = _pendingConsumers.removeAt(0);

    if (!completer.isCompleted) completer.complete(consumer);
  }

  // ------------------------------------------------------------------- media

  Future<void> _startMicrophone() async {
    final transport = _sendTransport;
    if (transport == null) {
      throw const VoiceSetupException('The sending transport is not ready');
    }

    if (_micProducer != null || _startingMic) return;

    _startingMic = true;

    try {
      final stream = await navigator.mediaDevices.getUserMedia(
        <String, dynamic>{
          'audio': <String, dynamic>{
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          },
          'video': false,
        },
      );

      final track = _firstAudioTrack(stream);

      if (track == null) {
        await _releaseStream(stream);

        throw const VoiceSetupException(
          'The microphone returned no audio track',
        );
      }

      _micStream = stream;
      track.enabled = !micMuted;

      transport.produce(
        track: track,
        stream: stream,
        source: 'mic',
        codecOptions: mediasoup.ProducerCodecOptions(
          opusStereo: 0,
          opusFec: 1,
          opusDtx: 0,
          opusMaxPlaybackRate: 48000,
          opusMaxAverageBitrate: 128000,
        ),
        appData: <String, dynamic>{'kind': StreamKind.audio.wire},
      );

      micError = null;
    } on VoiceSetupException catch (error) {
      micError = error.message;
    } catch (error) {
      // a denied permission or a machine without a microphone lands here. The
      // session survives, so the user can still listen and retry with the mic
      // button.
      micError = 'Microphone unavailable';
      debugPrint('voice: microphone failed: $error');
    } finally {
      _startingMic = false;
      _notify();
    }
  }

  Future<void> _stopMicrophone() async {
    final stream = _micStream;
    _micStream = null;

    if (stream == null) return;

    await _releaseStream(stream);
  }

  Future<void> _releaseStream(MediaStream stream) async {
    for (final track in stream.getTracks()) {
      try {
        await track.stop();
      } catch (error) {
        debugPrint('voice: stopping a track failed: $error');
      }
    }

    try {
      await stream.dispose();
    } catch (error) {
      debugPrint('voice: disposing a stream failed: $error');
    }
  }

  // --------------------------------------------------------------- consuming

  Future<void> _consumeExistingProducers(SharkordApi api) async {
    final ids = await api.getProducers();

    // audio only on purpose: video and screen share are out of scope for this
    // build, and an audio session must not be held up by them
    for (final remoteId in ids.audio) {
      await _consume(api, remoteId, StreamKind.audio);
    }

    for (final remoteId in ids.screenAudio) {
      await _consume(api, remoteId, StreamKind.screenAudio);
    }

    // external streams are radio style broadcasts a bot may be pushing into the
    // channel. A stream without an audio track simply answers NOT_FOUND, which
    // is not worth surfacing.
    for (final streamId in ids.externalStreams) {
      await _consume(api, streamId, StreamKind.externalAudio);
    }
  }

  Future<void> _consume(SharkordApi api, int remoteId, StreamKind kind) async {
    if (!kind.isAudio) return;
    if (remoteId == _ownUserId) return;
    if (_tearingDown || _recvTransport == null || _device == null) return;

    final key = '$remoteId:${kind.wire}';

    if (_consuming.contains(key) || _consumers.containsKey(key)) return;

    _consuming.add(key);

    try {
      final params = await api.consume(
        kind: kind,
        remoteId: remoteId,
        rtpCapabilities: _device!.rtpCapabilities.toMap(),
      );

      final consumer = await _attachConsumer(params);

      if (_tearingDown) {
        await consumer.close();

        return;
      }

      _consumers[key] = consumer;

      if (soundMuted) consumer.pause();

      _setDetail(null);
      _notify();
    } on ApiException catch (error) {
      // a producer can disappear between the listing and the request
      debugPrint('voice: consuming $key failed: ${error.message}');
    } catch (error) {
      debugPrint('voice: consuming $key failed: $error');
    } finally {
      _consuming.remove(key);
    }
  }

  Future<mediasoup.Consumer> _attachConsumer(VoiceConsumerParams params) {
    final transport = _recvTransport;

    if (transport == null) {
      throw const VoiceSetupException('The receiving transport is gone');
    }

    final completer = Completer<mediasoup.Consumer>();
    _pendingConsumers.add(completer);

    transport.consume(
      id: params.consumerId,
      producerId: params.producerId,
      // peer to peer transports are not used by the server, which is why the
      // mediasoup client wants an empty one here
      peerId: '',
      kind: params.kind.isAudio
          ? RTCRtpMediaType.RTCRtpMediaTypeAudio
          : RTCRtpMediaType.RTCRtpMediaTypeVideo,
      rtpParameters: mediasoup.RtpParameters.fromMap(params.rtpParameters),
    );

    return completer.future.timeout(const Duration(seconds: 15));
  }

  void _scheduleConsume(int remoteId, StreamKind kind) {
    final api = _api;
    if (api == null) return;

    _consumeChain = _consumeChain.then((_) => _consume(api, remoteId, kind));
  }

  Future<void> _closeConsumer(String key) async {
    final consumer = _consumers.remove(key);

    if (consumer == null) return;

    try {
      await consumer.close();
    } catch (error) {
      debugPrint('voice: closing consumer $key failed: $error');
    }

    _notify();
  }

  // ----------------------------------------------------- realtime entrypoints

  /// a remote producer appeared in the channel this session is in.
  void handleProducerAdded(VoiceProducerEvent event) {
    if (event.channelId != channelId) return;
    if (channelId == null) return;

    _scheduleConsume(event.remoteId, event.kind);
  }

  void handleProducerClosed(VoiceProducerEvent event) {
    if (event.channelId != channelId) return;

    unawaited(_closeConsumer('${event.remoteId}:${event.kind.wire}'));
  }

  /// a user dropped out of the channel: every stream of theirs goes with them.
  void handleUserLeft(int leftChannelId, int userId) {
    if (leftChannelId != channelId) return;

    final keys = _consumers.keys
        .where((key) => key.startsWith('$userId:'))
        .toList(growable: false);

    for (final key in keys) {
      unawaited(_closeConsumer(key));
    }
  }

  // ----------------------------------------------------------------- controls

  Future<void> toggleMic() async {
    if (!isInChannel) return;

    final next = !micMuted;

    micMuted = next;
    _notify();

    final track = _firstAudioTrack(_micStream);
    if (track != null) track.enabled = !next;

    // a previous attempt may have failed because the device was busy or the
    // permission had not been granted yet
    if (!next && _micProducer == null) await _startMicrophone();

    await _pushState();
  }

  Future<void> toggleSound() async {
    if (!isInChannel) return;

    soundMuted = !soundMuted;
    _applySoundMuted();
    _notify();

    await _pushState();
  }

  /// deafening is local: the consumers are paused, which also stops the server
  /// from sending those streams.
  void _applySoundMuted() {
    for (final consumer in _consumers.values) {
      if (soundMuted) {
        consumer.pause();
      } else {
        consumer.resume();
      }
    }
  }

  Future<void> _pushState() async {
    final api = _api;
    if (api == null) return;

    try {
      await api.updateVoiceState(micMuted: micMuted, soundMuted: soundMuted);
    } on ApiException catch (error) {
      debugPrint('voice: pushing state failed: ${error.message}');
    }
  }

  bool _disposed = false;

  /// the session outlives a single widget, and its teardown can still emit
  /// transport events, so late notifications are dropped instead of throwing.
  void _notify() {
    if (_disposed) return;

    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;

    super.dispose();
  }

  // ------------------------------------------------------------------ helpers

  void _setDetail(String? value) {
    detail = value;
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();

    return const <String, dynamic>{};
  }

  static MediaStreamTrack? _firstAudioTrack(MediaStream? stream) {
    if (stream == null) return null;

    final tracks = stream.getAudioTracks();

    return tracks.isEmpty ? null : tracks.first;
  }
}
