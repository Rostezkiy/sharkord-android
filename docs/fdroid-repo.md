# Releases: GitHub Actions and a self-hosted F-Droid repository

`.github/workflows/android.yml` builds the Android app and, in the same run, publishes the APK to
an F-Droid repository that lives in a branch of a GitHub repository and is served by GitHub Pages.
Everything in this document is a one-time setup.

## What the workflow does

| Trigger | Result |
| --- | --- |
| pull request to `main` | `flutter analyze`, `flutter test` and an APK artifact, debug signed because forks never see the secrets |
| push to `main` | the same, release signed when the secrets are configured |
| tag `v*` | build, a GitHub release carrying the APK and its checksum, and an F-Droid repository update |
| manual run | the same, with `publish_to_fdroid` and the version overrides as inputs |

`versionName` comes from the tag (`v0.2.0` becomes `0.2.0`) or from `pubspec.yaml`, and
`versionCode` is the workflow run number, which only grows, so the repository always sees a newer
release than the one it already lists. A manual run can override both.

The Flutter version is pinned in the workflow (`3.47.6`, the release the project was developed
against) so a new stable does not change the build under it.

## Signing: two keystores, both required

An APK in an F-Droid repository has to be signed with a key that never changes, or the client
refuses to install the next release as an update. The repository index is signed separately, with
its own key. Generate both once and back them up outside the repository: without them nobody can
ship an update that installs over an existing release.

```bash
# the app signing key. the workflow decodes it into android/keystore.jks, which is gitignored
keytool -genkeypair -v -keystore android/keystore.jks -storetype PKCS12 \
  -keyalg RSA -keysize 4096 -validity 10000 -alias sharkord

# the repository key, which signs index-v1.jar
keytool -genkeypair -v -keystore fdroid-keystore.p12 -storetype PKCS12 \
  -keyalg RSA -keysize 4096 -validity 10000 -alias sharkord
```

Keep the alias `sharkord` for both, or set the `*_KEY_ALIAS` secrets to whatever alias you picked.
Passwords are asked for twice by `keytool`: the store password and the key password. Using the same
one for both keeps the setup to three secrets.

Turn each keystore into base64, which is what the secrets hold:

```bash
# git bash, linux
base64 -w0 android/keystore.jks > android-keystore.b64
base64 -w0 fdroid-keystore.p12 > fdroid-keystore.b64

# macos
base64 -i android/keystore.jks -o android-keystore.b64

# powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('android/keystore.jks')) | Set-Content android-keystore.b64
```

Then store them (repository settings → secrets and variables → actions, or the `gh` commands):

```bash
gh secret set ANDROID_KEYSTORE_BASE64 < android-keystore.b64
gh secret set ANDROID_KEYSTORE_PASSWORD   # prompts, type the store password
gh secret set ANDROID_KEY_ALIAS           # only if it is not "sharkord"
gh secret set ANDROID_KEY_PASSWORD        # only if it differs from the store password

gh secret set FDROID_KEYSTORE_BASE64 < fdroid-keystore.b64
gh secret set FDROID_KEYSTORE_PASSWORD
gh secret set FDROID_KEY_ALIAS            # only if it is not "sharkord"
gh secret set FDROID_KEY_PASSWORD         # only if it differs from the store password
```

`android/key.properties` and any `*.jks` / `*.keystore` in `android/` are gitignored, and the
workflow writes them only for the duration of a build. A checkout without them still builds a
release APK, signed with the debug key, which is what a contributor gets.

## The F-Droid repository

The repository is a branch of a GitHub repository, served by GitHub Pages. Two ways to host it,
pick one:

- **A separate repository (the default).** Create `<owner>/fdroid`, public, and give the workflow a
  token that can push to it: `FDROID_REPO_TOKEN`, a fine grained personal access token with
  `Contents: read and write` on that repository. The default branch name it pushes to is
  `gh-pages`.
- **This repository.** Push the repository into a `gh-pages` branch of this one instead, which the
  workflow's own `GITHUB_TOKEN` is allowed to do, so no extra secret is needed. Set the repository
  variable `FDROID_REPO` to `<owner>/<this repo>` and leave `FDROID_REPO_TOKEN` unset.

Optional repository variables: `FDROID_REPO` (`owner/name`, default `<owner>/fdroid`) and
`FDROID_REPO_BRANCH` (default `gh-pages`).

One-time setup:

1. Create the repository (skip it if you are publishing from this one).
2. Repository settings → Pages → Source: `Deploy from a branch`, branch `gh-pages`, folder `/ (root)`.
   The branch does not exist yet, which is fine, the first run creates it.
3. Add the secrets above, plus `FDROID_REPO_TOKEN` for the separate-repository case. The repository
   must be public for the F-Droid client to reach it without credentials.
4. Run the workflow once from the Actions tab with `publish_to_fdroid` enabled.
5. In the F-Droid client: Settings → Repositories → `+`, and add
   `https://<owner>.github.io/<repo>/repo`. The `/repo` part is not optional: fdroidserver
   refuses to run when `repo_url` in `config.yml` does not end with it, because the index lives
   in the `repo` directory of the served branch.

The first run creates the branch, `metadata/com.sharkord.app.yml`, `repo/` with the renamed APK and
the signed index. `config.yml` (it holds the passwords) and `keystore.p12` are written at run time
and listed in the branch's `.gitignore`, so the published branch only ever contains APKs, metadata
and the signed index. The app metadata is created once and then left alone, so edits to its
description survive later runs.

## Cutting a release

```bash
git tag v0.2.0
git push origin v0.2.0
```

The tag run builds, creates the GitHub release with the APK and the `.sha256` next to it, and
updates the repository. Installed clients show the update once the Pages build finishes, usually a
minute or two later. Re-running a tag is safe: the release files are replaced and an unchanged
repository is not committed again.

## Notes

- The F-Droid job verifies the APK's signature before listing it, through `apksigner` from the
  Android SDK the runner image ships (the path is written into `config.yml`). AGP 9 signs release
  APKs with the v2 scheme only, so a workspace where apksigner cannot be found would make
  fdroidserver verify with `jarsigner`, reject the APK and move it to `archive/` while the run
  still looked successful. The job checks that the APK landed in `repo/` and fails loudly instead.
- `fdroid update --rename-apks` renames every APK to `com.sharkord.app_<versionCode>.apk`, and
  `archive_older: 0` keeps only the newest one in `repo/`. Raise `archive_older` in the workflow if
  the repository should keep older versions too.
- This is a self-hosted repository. It has nothing to do with the official F-Droid catalogue;
  getting listed there means a merge request against `fdroiddata`, a build recipe and a
  reproducible build.
- `repo_keyalias`, not `keyalias`, is the config key for the repository key. `keystorepass` and
  `keypass` hold its passwords; `config.yml` is written with mode 0600 because of them.
- Windows is not part of the workflow. Add a second job if the desktop build should be attached to
  the release as well.
- `flutter analyze` and `flutter test` gate the build, so a broken commit never reaches the
  repository.
