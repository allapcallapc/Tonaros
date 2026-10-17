/// Build-time configuration, baked in via
/// --dart-define-from-file=env/staging.json (or prod.json) - see
/// env/README.md.
class AppConfig {
  const AppConfig._();

  /// "prod", "staging", or "local" when no env file was passed.
  static const String environment =
      String.fromEnvironment('APP_ENV', defaultValue: 'local');

  static bool get isProd => environment == 'prod';
}
