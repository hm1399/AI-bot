import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'app_providers.dart';
import 'app_state.dart';

final connectStateProvider = Provider<AppState>(
  (Ref ref) => ref.watch(appControllerProvider),
);
