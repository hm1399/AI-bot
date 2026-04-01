import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/chat/message_model.dart';
import '../models/chat/session_model.dart';
import 'app_providers.dart';

final sessionsProvider = Provider<List<SessionModel>>(
  (Ref ref) => ref.watch(appControllerProvider).sessions,
);

final messagesProvider = Provider<List<MessageModel>>(
  (Ref ref) => ref.watch(currentMessagesProvider),
);
