# CLAUDE.md

Guidance for Claude Code when working in this repository.

## PR titles must follow Conventional Commits

Releases are automated by [release-please](https://github.com/googleapis/release-please-action) (`.github/workflows/release-please.yml`), which decides the next version and writes the changelog by parsing commit messages - specifically the PR title, since PRs are squash-merged into a single commit.

Every PR title must start with one of:

- `fix: ...` - bug fix, bumps the patch version (0.1.0 -> 0.1.1)
- `feat: ...` - new feature, bumps the minor version (0.1.0 -> 0.2.0)
- `feat!: ...` or `fix!: ...` - breaking change, bumps the major version (0.1.0 -> 1.0.0)
- `chore: ...`, `refactor: ...`, `docs: ...`, `test: ...`, `ci: ...` - no version bump, but still recorded

A PR title without one of these prefixes won't be picked up by release-please at all - the change merges normally but is invisible to the changelog/version bump.

## Release flow

1. Merging a correctly-titled PR updates release-please's running "Release PR" (changelog + next version).
2. Merging that Release PR is the only manual release step: it creates the release as a draft, `release-apk.yml` builds the signed APK and attaches it, then publishes the release, which triggers `deploy.yml` to deploy the web build to GitHub Pages.
3. Do not create GitHub Releases manually via the UI, and do not push tags directly - either bypasses release-please's version tracking and can conflict with GitHub's immutable-releases restriction (once a tag name has been used by a published release, it can never have a release re-attached to it, even if that release is deleted).

## Architecture: no backend

Tonaros is a standalone Flutter app (web + Android) - there is no server
side. The only network call it makes is `lib/services/update_service.dart`
checking GitHub Releases for a newer APK (Android only); keep it that way
unless a backend is deliberately introduced.

## Two environments: staging and production

Selected at build time with `--dart-define-from-file=env/<env>.json`, read
by `lib/config/app_config.dart` (see `env/README.md`):

- **Staging** (`env/staging.json`): every push to `main` deploys to
  `/main/` on GitHub Pages (`deploy-main.yml`), and every PR gets a preview
  at `/pr-<n>/` (`deploy-pr-preview.yml`, removed when the PR closes).
  Shows a "STAGING" corner banner.
- **Production** (`env/prod.json`): published releases deploy the web app
  to the root of GitHub Pages (`deploy.yml`) and attach the release APK
  (`release-apk.yml`). No banner.

New per-environment settings go in both `env/*.json` files plus a matching
`String.fromEnvironment` in `AppConfig` - never hard-coded.

## App icons are generated, not committed

`assets/logo.png` (and `assets/logo_foreground.png` for the Android
adaptive icon) are the source of truth; `flutter_launcher_icons` generates
the Android mipmaps and web icons from them (config in `pubspec.yaml`).
Those generated files are gitignored - run `dart run flutter_launcher_icons`
after a fresh checkout, and CI does the same via
`.github/actions/generate-app-icons`.
