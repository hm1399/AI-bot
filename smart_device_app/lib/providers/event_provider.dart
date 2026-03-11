import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/event.dart';
import '../services/api_service.dart';

final eventProvider = StateNotifierProvider<EventNotifier, EventState>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return EventNotifier(apiService);
});

class EventState {
  final List<Event> events;
  final bool isLoading;
  final String? error;
  
  EventState({
    required this.events,
    this.isLoading = false,
    this.error,
  });
  
  EventState copyWith({
    List<Event>? events,
    bool? isLoading,
    String? error,
  }) {
    return EventState(
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
  
  // 获取指定日期的事件
  List<Event> getEventsForDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);
    
    return events.where((event) {
      if (event.isAllDay) {
        // 全天事件：检查事件的开始日期是否等于指定日期
        return event.startTime.year == date.year &&
               event.startTime.month == date.month &&
               event.startTime.day == date.day;
      } else {
        // 非全天事件：检查事件是否与指定日期重叠
        return (event.startTime.isAfter(startOfDay) && event.startTime.isBefore(endOfDay)) ||
               (event.endTime.isAfter(startOfDay) && event.endTime.isBefore(endOfDay)) ||
               (event.startTime.isBefore(startOfDay) && event.endTime.isAfter(endOfDay)) ||
               (event.startTime.year == date.year && 
                event.startTime.month == date.month && 
                event.startTime.day == date.day);
      }
    }).toList();
  }
  
  // 获取指定月份的事件
  List<Event> getEventsForMonth(int year, int month) {
    return events.where((event) {
      return event.startTime.year == year && event.startTime.month == month;
    }).toList();
  }
  
  // 检查指定日期是否有事件
  bool hasEventsOnDate(DateTime date) {
    return getEventsForDate(date).isNotEmpty;
  }
}

class EventNotifier extends StateNotifier<EventState> {
  final ApiService _apiService;
  final _uuid = Uuid();
  
  EventNotifier(this._apiService) : super(EventState(events: [])) {
    loadEvents();
  }
  
  // 加载事件列表
  Future<void> loadEvents() async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final events = await _apiService.getEvents();
      state = state.copyWith(events: events, isLoading: false);
    } catch (e) {
      print('Error loading events: $e');
      state = state.copyWith(isLoading: false, error: 'Failed to load events');
    }
  }
  
  // 创建新事件
  Future<void> createEvent({
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    bool isAllDay = false,
  }) async {
    try {
      final newEvent = Event(
        id: _uuid.v4(),
        title: title,
        description: description,
        startTime: startTime,
        endTime: endTime,
        isAllDay: isAllDay,
      );
      
      state = state.copyWith(isLoading: true, error: null);
      final createdEvent = await _apiService.createEvent(newEvent);
      
      state = state.copyWith(
        events: [...state.events, createdEvent],
        isLoading: false,
      );
    } catch (e) {
      print('Error creating event: $e');
      state = state.copyWith(isLoading: false, error: 'Failed to create event');
    }
  }
  
  // 更新事件
  Future<void> updateEvent(Event event) async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final updatedEvent = await _apiService.updateEvent(event);
      
      final updatedEvents = state.events.map((e) => 
        e.id == event.id ? updatedEvent : e
      ).toList();
      
      state = state.copyWith(
        events: updatedEvents,
        isLoading: false,
      );
    } catch (e) {
      print('Error updating event: $e');
      state = state.copyWith(isLoading: false, error: 'Failed to update event');
    }
  }
  
  // 删除事件
  Future<void> deleteEvent(String eventId) async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      await _apiService.deleteEvent(eventId);
      
      final updatedEvents = state.events.where((e) => e.id != eventId).toList();
      state = state.copyWith(
        events: updatedEvents,
        isLoading: false,
      );
    } catch (e) {
      print('Error deleting event: $e');
      state = state.copyWith(isLoading: false, error: 'Failed to delete event');
    }
  }
}