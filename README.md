# Sharkord Client

An unofficial Flutter client for a [Sharkord](https://github.com/Sharkord/sharkord) server, for
**Android** and **Windows**. It connects to the same self-hosted server the web client uses, voice
included.

## Features

- Sign in with an identity and a password, and stay signed in between launches
- Categories, text channels and voice channels, with unread badges
- Message history with pagination, attachments, emoji reactions and typing indicators
- Text formatting, links, mentions and custom emoji
- Online and offline members with their roles and role colours
- Direct messages, when the server has them enabled
- Voice channels: join, talk, mute, deafen and see who is in the call
- The server address is entered on first launch and can be changed at any time
- Automatic reconnect that restores the session and the current call state

## Requirements

- Flutter 3.35 or newer, developed against 3.47
- A running Sharkord server

## Build and run

```bash
flutter pub get

flutter run -d windows     # desktop
flutter run -d android     # a connected device or emulator
```

Release builds:

```bash
flutter build apk --release
flutter build appbundle --release
flutter build windows --release
```

A release build is signed from `android/key.properties` when that file exists, using the layout
described on [flutter.dev/to/reference-keystore](https://flutter.dev/to/reference-keystore), and
with the debug key otherwise, so a fresh checkout still builds. The keystore and its passwords are
gitignored.

Android asks for the microphone the first time a voice channel is joined. The launcher icons are
generated from the artwork in `assets/icon/` with `dart run flutter_launcher_icons`.

## Continuous integration

`.github/workflows/android.yml` runs the analyzer and the tests, builds the release APK, attaches it
to a GitHub release for a `v*` tag, and publishes it to a self-hosted F-Droid repository served by
GitHub Pages. See [docs/fdroid-repo.md](docs/fdroid-repo.md) for the signing keys and the one-time
setup.

## Tests

```bash
flutter test
```

## Limitations

- Voice is audio only: no video calls and no screen sharing
- No per-user volume, no audio device pickers, no push to talk
- No file uploads, no message search, no server administration
- Android and Windows only, there is no iOS build

## Credits

Sharkord is an open source, self-hosted communication platform, released under the MIT license. This
client is an independent, unofficial project; the name and the artwork it uses for its icon belong to
the Sharkord project.
