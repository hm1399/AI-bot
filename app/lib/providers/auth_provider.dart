import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/connect/connection_config_model.dart';
import 'app_providers.dart';

final connectionConfigProvider = Provider<ConnectionConfigModel>(
  (Ref ref) => ref.watch(appControllerProvider).connection,
);

final authEnabledProvider = Provider<bool>(
  (Ref ref) => ref.watch(appControllerProvider).capabilities.appAuthEnabled,
);
