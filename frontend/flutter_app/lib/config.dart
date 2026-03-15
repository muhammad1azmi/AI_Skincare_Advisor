/// App-wide configuration constants.
class AppConfig {
  AppConfig._();

  /// Cloud Run backend URL — set via environment or override for local dev.
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'wss://skincare-advisor-1089521368524.us-central1.run.app',
  );

  /// REST API base URL (same host, different scheme).
  static String get restBaseUrl =>
      backendUrl.replaceFirst('wss://', 'https://').replaceFirst('ws://', 'http://');

  /// WebSocket path template.
  static String wsUrl(String userId, String sessionId) =>
      '$backendUrl/ws/$userId/$sessionId';

  /// App name used for ADK sessions.
  static const String appName = 'skincare_advisor';
}
