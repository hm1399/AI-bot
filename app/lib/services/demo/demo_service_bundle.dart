import '../../models/chat/message_model.dart';
import '../../models/chat/session_model.dart';
import '../../models/connect/bootstrap_model.dart';
import '../../models/events/event_model.dart';
import '../../models/home/runtime_state_model.dart';
import '../../models/notifications/notification_model.dart';
import '../../models/reminders/reminder_model.dart';
import '../../models/settings/settings_model.dart';
import '../../models/tasks/task_model.dart';

class DemoServiceBundle {
  static final List<SessionModel> sessions = <SessionModel>[
    SessionModel(
      sessionId: 'app:demo',
      channel: 'app',
      title: 'Demo Session',
      summary: 'Explore the UI without a live backend.',
      lastMessageAt: DateTime.now()
          .subtract(const Duration(minutes: 20))
          .toIso8601String(),
      messageCount: 3,
      pinned: true,
      archived: false,
    ),
  ];

  static final RuntimeStateModel runtime = RuntimeStateModel(
    currentTask: RuntimeTaskModel(
      taskId: 'task_demo_current',
      kind: 'chat',
      sourceChannel: 'app',
      sourceSessionId: 'app:demo',
      summary: 'Preparing a short demo reply',
      stage: 'thinking',
      cancellable: true,
      startedAt: DateTime.now()
          .subtract(const Duration(minutes: 2))
          .toIso8601String(),
    ),
    taskQueue: <RuntimeTaskModel>[
      RuntimeTaskModel(
        taskId: 'task_demo_queue',
        kind: 'chat',
        sourceChannel: 'app',
        sourceSessionId: 'app:demo',
        summary: 'Summarize runtime status',
        stage: 'queued',
        cancellable: true,
        startedAt: null,
      ),
    ],
    device: const DeviceStatusModel(
      connected: true,
      state: 'idle',
      battery: 85,
      wifiRssi: -54,
      wifiSignal: 77,
      charging: false,
      reconnectCount: 0,
    ),
    todoSummary: TodoSummaryModel(
      enabled: true,
      pendingCount: 5,
      overdueCount: 1,
      nextDueAt: DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
    ),
    calendarSummary: CalendarSummaryModel(
      enabled: true,
      todayCount: 3,
      nextEventAt: DateTime.now()
          .add(const Duration(hours: 1))
          .toIso8601String(),
      nextEventTitle: 'Team sync',
    ),
  );

  static final BootstrapModel bootstrap = BootstrapModel(
    serverVersion: 'demo',
    capabilities: const CapabilitiesModel(
      chat: true,
      deviceControl: true,
      voicePipeline: true,
      whatsappBridge: false,
      todoSummary: true,
      calendarSummary: true,
      appEvents: true,
      eventReplay: true,
      appAuthEnabled: false,
    ),
    runtime: runtime,
    sessions: sessions,
    eventStream: const EventStreamModel(
      type: 'websocket',
      path: '/ws/app/v1/events',
      resume: EventResumeModel(
        query: 'last_event_id',
        replayLimit: 200,
        latestEventId: 'evt_demo_latest',
      ),
    ),
  );

  static final Map<String, List<MessageModel>>
  messagesBySession = <String, List<MessageModel>>{
    'app:demo': <MessageModel>[
      MessageModel(
        id: 'msg_demo_1',
        sessionId: 'app:demo',
        role: 'assistant',
        text: 'Demo mode runs locally. Real mode uses app-v1 HTTP and events.',
        status: 'completed',
        createdAt: DateTime.now()
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
      ),
      MessageModel(
        id: 'msg_demo_2',
        sessionId: 'app:demo',
        role: 'user',
        text: 'What changes in real mode?',
        status: 'completed',
        createdAt: DateTime.now()
            .subtract(const Duration(minutes: 58))
            .toIso8601String(),
      ),
      MessageModel(
        id: 'msg_demo_3',
        sessionId: 'app:demo',
        role: 'assistant',
        text:
            'Messages go through the backend and the assistant reply comes from the event stream.',
        status: 'completed',
        createdAt: DateTime.now()
            .subtract(const Duration(minutes: 57))
            .toIso8601String(),
      ),
    ],
  };

  static final AppSettingsModel settings = AppSettingsModel(
    serverUrl: 'demo.local',
    serverPort: 8000,
    llmProvider: 'server-managed',
    llmModel: 'demo-model',
    llmApiKeyConfigured: true,
    llmBaseUrl: null,
    sttProvider: 'server-managed',
    sttModel: 'demo-stt',
    sttLanguage: 'en-US',
    ttsProvider: 'server-managed',
    ttsModel: 'demo-tts',
    ttsVoice: 'alloy',
    ttsSpeed: 1,
    deviceVolume: 70,
    ledEnabled: true,
    ledBrightness: 80,
    ledMode: 'breathing',
    ledColor: '#2563eb',
    wakeWord: 'Hey Assistant',
    autoListen: true,
  );

  static final List<TaskModel> tasks = <TaskModel>[
    TaskModel(
      id: 'task_demo_1',
      title: 'Review project proposal',
      description: 'Prepare feedback for the team.',
      priority: 'high',
      completed: false,
      dueAt: DateTime.now().add(const Duration(days: 1)).toIso8601String(),
      createdAt: DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String(),
      updatedAt: DateTime.now()
          .subtract(const Duration(hours: 1))
          .toIso8601String(),
    ),
    TaskModel(
      id: 'task_demo_2',
      title: 'Update documentation',
      description: null,
      priority: 'medium',
      completed: true,
      dueAt: null,
      createdAt: DateTime.now()
          .subtract(const Duration(days: 2))
          .toIso8601String(),
      updatedAt: DateTime.now()
          .subtract(const Duration(hours: 12))
          .toIso8601String(),
    ),
  ];

  static final List<EventModel> events = <EventModel>[
    EventModel(
      id: 'event_demo_1',
      title: 'Team Standup',
      description: 'Daily team sync.',
      startAt: DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      endAt: DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
      location: 'Conference Room A',
      createdAt: DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String(),
      updatedAt: DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String(),
    ),
  ];

  static final List<NotificationModel> notifications = <NotificationModel>[
    NotificationModel(
      id: 'notif_demo_1',
      type: 'task_due',
      priority: 'high',
      title: 'Task Due Soon',
      message: 'Review project proposal is due in 1 hour.',
      read: false,
      createdAt: DateTime.now()
          .subtract(const Duration(minutes: 30))
          .toIso8601String(),
      metadata: const <String, dynamic>{'task_id': 'task_demo_1'},
    ),
  ];

  static final List<ReminderModel> reminders = <ReminderModel>[
    ReminderModel(
      id: 'rem_demo_1',
      title: 'Morning Standup',
      message: 'Daily team standup meeting.',
      time: '09:00',
      repeat: 'daily',
      enabled: true,
      createdAt: DateTime.now()
          .subtract(const Duration(days: 5))
          .toIso8601String(),
      updatedAt: DateTime.now()
          .subtract(const Duration(hours: 2))
          .toIso8601String(),
    ),
  ];
}
