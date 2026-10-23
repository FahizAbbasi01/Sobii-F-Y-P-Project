/// Build-time configuration.
///
/// DEMO_MODE (default: true) runs the whole app against the in-app demo backend
/// with sample data stored on the phone, so no server or internet is needed.
/// Build against the real server with:
///   flutter build apk --dart-define=DEMO_MODE=false --dart-define=API_BASE_URL=https://your-api
class AppConfig {
  static const bool demoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: true);

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:4000',
  );

  static String get apiRoot => '$apiBaseUrl/api/v1';
}
