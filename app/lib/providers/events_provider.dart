import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/events/event_model.dart';
import 'app_providers.dart';
import 'app_state.dart';

final eventsStatusProvider = Provider<FeatureStatus>(
  (Ref ref) => ref.watch(appControllerProvider).eventsStatus,
);

final eventsProvider = Provider<List<EventModel>>(
  (Ref ref) => ref.watch(upcomingEventsProvider),
);
