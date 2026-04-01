import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/tasks/task_model.dart';
import 'app_providers.dart';
import 'app_state.dart';

final tasksStatusProvider = Provider<FeatureStatus>(
  (Ref ref) => ref.watch(appControllerProvider).tasksStatus,
);

final tasksProvider = Provider<List<TaskModel>>(
  (Ref ref) => ref.watch(sortedTasksProvider),
);
