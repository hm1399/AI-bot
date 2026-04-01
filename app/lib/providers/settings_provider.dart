import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/settings/settings_model.dart';
import 'app_providers.dart';
import 'app_state.dart';

final settingsStatusProvider = Provider<FeatureStatus>(
  (Ref ref) => ref.watch(appControllerProvider).settingsStatus,
);

final settingsModelProvider = Provider<AppSettingsModel?>(
  (Ref ref) => ref.watch(appControllerProvider).settings,
);
