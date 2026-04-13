class ApiConstants {
  static const String healthPath = '/api/health';
  static const String basePath = '/api/app/v1';
  static const String bootstrapPath = '$basePath/bootstrap';
  static const String capabilitiesPath = '$basePath/capabilities';
  static const String sessionsPath = '$basePath/sessions';
  static const String sessionsActivePath = '$sessionsPath/active';
  static const String runtimeStatePath = '$basePath/runtime/state';
  static const String runtimeStopPath = '$basePath/runtime/stop';
  static const String todoSummaryPath = '$basePath/runtime/todo-summary';
  static const String calendarSummaryPath =
      '$basePath/runtime/calendar-summary';
  static const String devicePath = '$basePath/device';
  static const String deviceSpeakPath = '$basePath/device/speak';
  static const String deviceCommandsPath = '$basePath/device/commands';
  static const String devicePairingBundlePath =
      '$basePath/device/pairing/bundle';
  static const String settingsPath = '$basePath/settings';
  static const String settingsTestPath = '$basePath/settings/llm/test';
  static const String tasksPath = '$basePath/tasks';
  static const String eventsPath = '$basePath/events';
  static const String notificationsPath = '$basePath/notifications';
  static const String notificationsReadAllPath =
      '$basePath/notifications/read-all';
  static const String remindersPath = '$basePath/reminders';
  static const String planningPath = '$basePath/planning';
  static const String planningBundlesPath = '$planningPath/bundles';
  static const String planningOverviewPath = '$planningPath/overview';
  static const String planningTimelinePath = '$planningPath/timeline';
  static const String planningConflictsPath = '$planningPath/conflicts';
  static const String wsEventsPath = '/ws/app/v1/events';
}
