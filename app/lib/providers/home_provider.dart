import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/home/runtime_state_model.dart';
import 'app_providers.dart';

final runtimeStateProvider = Provider<RuntimeStateModel>(
  (Ref ref) => ref.watch(appControllerProvider).runtimeState,
);
