import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/notifications/notification_model.dart';
import '../models/reminders/reminder_model.dart';
import 'app_providers.dart';

final notificationsProvider = Provider<List<NotificationModel>>(
  (Ref ref) => ref.watch(appControllerProvider).notifications,
);

final remindersProvider = Provider<List<ReminderModel>>(
  (Ref ref) => ref.watch(appControllerProvider).reminders,
);
