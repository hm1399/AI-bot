import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/event.dart';

class EventState {
  final List<Event> events;

  EventState({required this.events});

  EventState copyWith({List<Event>? events}) {
    return EventState(events: events ?? this.events);
  }
}


class EventNotifier extends StateNotifier<EventState> {
  EventNotifier() : super(EventState(events: []));

  void setEvents(List<Event> newEvents) {
    state = state.copyWith(events: newEvents);
  }

  void addEvent(Event event) {
    state = state.copyWith(events: [...state.events, event]);
  }

  void updateEvent(Event updatedEvent) {
    final index = state.events.indexWhere((e) => e.id == updatedEvent.id);
    if (index != -1) {
      final newList = List<Event>.from(state.events);
      newList[index] = updatedEvent;
      state = state.copyWith(events: newList);
    }
  }

  void removeEvent(String id) {
    state = state.copyWith(events: state.events.where((e) => e.id != id).toList());
  }

  void handleWsMessage(Map<String, dynamic> message) {
    if (message['type'] == 'event_update') {
      final eventsData = message['data'] as List;
      final events = eventsData.map((e) => Event.fromJson(e)).toList();
      setEvents(events);
    } else if (message['type'] == 'event_created') {
      addEvent(Event.fromJson(message['data']));
    }
  }
}

final eventProvider = StateNotifierProvider<EventNotifier, EventState>((ref) {
  return EventNotifier();
});

final eventWsHandlerProvider = Provider<Function>((ref) {
  return (Map<String, dynamic> message) {
    ref.read(eventProvider.notifier).handleWsMessage(message);
  };
});