# Tonaros

A mobile-first timer for physiotherapy exercises (Flutter web + Android). No backend.

- Production: https://allapcallapc.github.io/Tonaros/ (+ APK on each [GitHub Release](https://github.com/allapcallapc/Tonaros/releases))
- Staging (latest `main`): https://allapcallapc.github.io/Tonaros/main/

## Running locally

```
flutter pub get
dart run flutter_launcher_icons
flutter run -d chrome --dart-define-from-file=env/staging.json
```

Or use the `.vscode/launch.json` configs. `.claude/launch.json` serves an already-built `build/web` (run `flutter build web --dart-define-from-file=env/staging.json` first). See `env/README.md` for what each environment sets.

## Project structure

- `lib/config/` - `AppConfig` (build-time environment, from `env/*.json`)
- `lib/models/` - `Session`, `HoldExercise`, `TempoExercise`, `Transition` (JSON-serialisable)
- `lib/engine/` - `buildPlan`: a session as a flat list of timed phases (also drives the duration estimate)
- `lib/screens/` - sessions list (home), session editor, exercise editor, settings
- `lib/services/` - `SessionStore`/`SettingsStore` (shared preferences), `UpdateService` + `UpdateController` (Android in-app updates from GitHub Releases)
- `lib/theme/` - per-phase colors
- `lib/widgets/` - number stepper, dialogs, the update prompt/download dialogs
- `assets/` - the logo, source for all generated launcher/PWA icons

## One-time GitHub setup

- **Pages**: Settings → Pages → deploy from branch `gh-pages` (root). The branch is created by the first deploy.
- **Secrets** (Settings → Secrets and variables → Actions):
  - `RELEASE_PLEASE_TOKEN` - a PAT with `contents` + `pull-requests` write on this repo (the default `GITHUB_TOKEN` can't trigger the follow-up deploy workflow).
  - `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` - the release signing key. Keep the same key forever, or installed apps can't update.

## Releases

Automated via release-please - see `CLAUDE.md` for the full flow and PR title conventions.
