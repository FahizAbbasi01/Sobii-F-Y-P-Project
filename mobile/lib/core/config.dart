/// Build-time configuration. Override with:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:4000
///
/// Defaults to the Android emulator's alias for your PC's localhost.
/// No secrets live in the app: it only talks to the DeviceTrust API.
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:4000',
  );

  static String get apiRoot => '$apiBaseUrl/api/v1';
}
