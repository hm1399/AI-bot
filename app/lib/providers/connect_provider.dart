import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'app_providers.dart';

final connectStateProvider = Provider<AppState>(
  (Ref ref) => ref.watch(appControllerProvider),
);
