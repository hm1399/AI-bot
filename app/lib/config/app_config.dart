class AppConfig {
  const AppConfig._();

  static const String appName = 'AI Bot App';
  static const int defaultPort = 8000;
  static const int defaultReplayLimit = 200;
  static const Duration requestTimeout = Duration(seconds: 12);
  static const String backendNotReadyMessage =
      'Backend interface is not ready yet. The frontend wiring is prepared.';
}
