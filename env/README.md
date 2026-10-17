# env/*.json

`--dart-define-from-file` configs read by `lib/config/app_config.dart`.
Tonaros has no backend, so for now the only value is `APP_ENV`; add any
future per-environment setting here (and a matching `String.fromEnvironment`
in `AppConfig`) rather than hard-coding it in the app.

- `staging.json` - used by the `main` branch deploy (`/main/` on GitHub
  Pages) and per-PR previews (`/pr-<n>/`). The app shows a "STAGING"
  corner banner.
- `prod.json` - used by published releases: the web deploy at the root of
  GitHub Pages and the release APK. No banner.

A build with no `--dart-define-from-file` at all (e.g. a bare
`flutter run`) reports `local` and shows a "LOCAL" banner.
