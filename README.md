# Sharkord Flutter client (MVP)

A minimal native client for a [Sharkord](../../README.md) server, built with Flutter for
**Android** and **Windows**. It talks to the same backend as the web client: the REST
endpoints for login and the server card, the tRPC WebSocket for everything else, and
mediasoup for voice.

This is a feasibility MVP, not a full client. It covers the parts that prove the protocol
is reachable from Flutter: sign in, browse channels, read and send messages, react, see who
is online, **join a voice channel and talk**.

## Requirements

- Flutter 3.35 or newer (developed against 3.47).
- A running Sharkord server. The address is **not hardcoded**: it is entered on the first
  screen and can be changed later from the sidebar menu (Change server / Sign out).

## Run

```bash
flutter pub get

flutter run -d windows     # desktop
flutter run -d android     # a connected device or emulator
```

Release builds:

```bash
flutter build windows --release
flutter build apk --release
```

The first build pulls a prebuilt libwebrtc for the platform, so it takes noticeably longer
than the builds of the earlier text-only version.

Android asks for the microphone the first time a voice channel is joined. On a real phone
the call is routed to the speaker; on Windows it follows the system default devices.

The Android build also declares `ACCESS_NETWORK_STATE` in
`android/app/src/main/AndroidManifest.xml`. WebRTC's network monitor queries the active
network as soon as the first peer connection is built, and when the permission is missing the
thrown JNI exception aborts the native library (SIGABRT in `network_thread`).

## Release

The project is set up to be signed and published as it stands:

- The version lives in `pubspec.yaml` (`0.1.0+1`). Flutter maps it to `versionName` and
  `versionCode` on Android and to the file version on Windows. A store rejects an upload
  that repeats a `versionCode`, so bump the number after the `+` for every build.
- The Android application id is `com.sharkord.app` and the label is `Sharkord`
  (`android/app/build.gradle.kts` and `android/app/src/main/AndroidManifest.xml`). The id
  is permanent once the first release is published.
- The launcher icons use the artwork the web client ships, kept in `assets/icon/`, and are
  generated rather than edited by hand: `dart run flutter_launcher_icons` writes the Android
  legacy and adaptive icons plus the Windows `.ico`. The configuration is in `pubspec.yaml`
  under `flutter_launcher_icons`.
- Release builds currently sign with the **debug** key, which a store refuses. Add a keystore
  the way [flutter.dev/to/reference-keystore](https://flutter.dev/to/reference-keystore)
  describes before uploading; `android/key.properties` and any `*.jks` are already
  gitignored.

```bash
flutter build apk --release --split-per-abi   # apks to sideload
flutter build appbundle --release             # the file Play wants
flutter build windows --release
```

## What works

| Area | State |
| --- | --- |
| Server address + server card (name, description, logo) | yes |
| Login with identity + password, session persisted across launches | yes |
| Server password (`handshake.hasPassword` + `joinServer` retry) | yes |
| Categories, text channels, voice channel list | yes |
| Message history with cursor pagination (scroll up to load older) | yes |
| Send messages, edit/delete reflected from the realtime stream | yes |
| Emoji reactions | yes |
| Typing indicator | yes |
| Unread badges and mark-as-read | yes |
| Online/offline member list, roles, role colours | yes |
| Avatars, attachments, linkified message HTML | yes |
| Direct messages (when the server enables them) | yes |
| Realtime reconnect: the session is established again and subscriptions restored | yes |
| Join a voice channel, hear everyone, be heard | yes |
| Mute microphone / deafen / disconnect, live in the channel list | yes |
| Video, screen share, per-user volume, device pickers | no |

## Voice

Voice is an SFU, not a peer to peer call, so joining a channel is a short negotiation with
the server before any audio moves:

1. `voice.join` adds the account to the channel and returns the router RTP capabilities.
2. The client loads them into a mediasoup `Device`, which is what makes the codecs the
   browser and the server share explicit.
3. `voice.createProducerTransport` / `voice.createConsumerTransport` create the two
   WebRTC transports, one per direction. Each connects over DTLS
   (`voice.connectProducerTransport`, `voice.connectConsumerTransport`) the first time it
   carries something.
4. `voice.getProducers` lists who is already publishing, and every id is turned into a
   consumer, then `voice.produce` publishes the microphone.
5. `voice.onNewProducer` / `voice.onProducerClosed` keep that list current for the rest of
   the call.

`lib/state/voice_controller.dart` owns the session: the device, both transports, the
microphone producer and one consumer per remote stream. The tRPC calls it makes are the
ones spelled out in `lib/api/sharkord_api.dart`; the RTP/ORTC negotiation is done by
[`mediasfu_mediasoup_client`](https://pub.dev/packages/mediasfu_mediasoup_client), a
maintained port of mediasoup-client that tracks the current `flutter_webrtc`.

Only audio is handled. Video and screen share producers of other users are skipped on
purpose (`getProducers` returns them, the client ignores those lists), so a call with
someone who is sharing their screen still works and simply does not show the video.

Remote audio plays through the WebRTC audio device without a renderer, which is why no
audio widget appears anywhere: mute is the local track being disabled, deafen is pausing
every consumer.

If the microphone cannot be opened (no device, permission refused) the session still
connects: the call is joined, the other side is audible, and the voice strip says what
happened. Pressing the microphone button retries it.

## Layout

```
lib/
  api/       transport: REST client, tRPC socket, endpoint parsing, error mapping
  models/    the join payload and everything it contains, parsed leniently
  state/     SessionController (the session), VoiceController (the call),
             MessageStore, preferences
  helpers/   url and text formatting
  theme/     the dark palette and the Material theme built from it
  ui/        screens and widgets, no business logic
```

`SessionController` owns the socket, the subscriptions, the selected channel, the message
store and the voice controller; `VoiceController` owns the media session and is handed the
api when a session starts. Widgets read both through `provider` and never call the API
themselves.

## Protocol notes

These took probing against a live server to pin down, and are the reason the client is a
few hundred lines rather than a generated SDK:

- The socket connects to `wss://host/?connectionParams=1` and the **first frame** must be
  `{"method":"connectionParams","data":{"token":"<jwt>"}}`. The server builds the request
  context from it and waits for it before answering anything.
- Requests are `{"id":N,"method":"query"|"mutation"|"subscription","params":{"path":...,
  "input":...}}`. An input of `void` has to be **omitted**, not sent as `null`.
- Responses are `{"id":N,"result":{"type":"data","data":...}}`, errors
  `{"id":N,"error":{"message":...,"data":{"code":"FORBIDDEN",...}}}`. The useful code is
  `error.data.code`, not the numeric one next to it.
- The server sends a raw `PING` text frame every 30s and drops the connection if no
  `PONG` arrives within 5s, so the socket answers it and also uses its own keep-alive.
- The voice transports are addressed implicitly: the server keys a producer and a consumer
  transport by the authenticated user, so `voice.connectProducerTransport` and friends send
  no transport id (except `voice.produce`, which echoes the id back).
- `voice.consume` answers with the consumer's own RTP parameters, so the client never
  negotiates codecs itself; it hands them straight to the consumer.
- A new websocket counts as unauthenticated on the server until `others.joinServer` has run
  on it, so every reconnect has to handshake and join again before it resubscribes. The
  client reuses the saved server password for it and keeps the open channel and its messages.
- Losing the socket kills the media session with it (the server drops the transports), so a
  reconnect tears the call down and leaves rejoining to the user.

## Limitations

- **No video or screen share**: neither is produced nor consumed, so a call works but only
  the audio of a screen share is heard.
- **No per-user volume, no audio device pickers, no push to talk.** The microphone uses the
  system default device with echo cancellation and noise suppression on.
- **Nothing survives a reconnect**: the call is dropped and has to be joined again.
- **No file uploads**: attachments are displayed and opened in the browser, nothing is
  sent from the app.
- Message HTML is rendered by a small custom renderer (`ui/widgets/message_content.dart`)
  that understands the subset the server's sanitizer allows (paragraphs, line breaks,
  bold, italic, code, links, mentions, emoji spans). It is not a general HTML engine.
- No settings screen, no role management, no moderation actions.

## Tests

```bash
flutter test
```

The voice tests cover the payloads the server sends (stream kinds, producer ids, consume
answers, the voice map in the join payload). The negotiation itself is exercised only
against a real server, since it needs WebRTC and a microphone.
