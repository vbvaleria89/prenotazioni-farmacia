import '../models/appointment.dart';

/// PUNTO DI INNESTO GOOGLE CALENDAR.
/// Implementazione reale: Cloud Function (service account) che usa la
/// Google Calendar API su UN SOLO calendario "Stanza servizi" (la stanza è unica),
/// così anche eventi creati a mano dallo staff in Calendar bloccano gli slot.
abstract class CalendarService {
  Future<String> createEvent(Appointment a); // ritorna eventId
  Future<void> deleteEvent(String eventId);
  /// Intervalli occupati esterni all'app (freebusy query).
  Future<List<(DateTime, DateTime)>> busyIntervals(DateTime day);
}

class MockCalendarService implements CalendarService {
  int _n = 0;
  @override
  Future<String> createEvent(Appointment a) async => 'mock-event-${_n++}';
  @override
  Future<void> deleteEvent(String eventId) async {}
  @override
  Future<List<(DateTime, DateTime)>> busyIntervals(DateTime day) async {
    // Esempio: pausa pranzo bloccata in Calendar 13:00-14:30
    final d = DateTime(day.year, day.month, day.day);
    return [(d.add(const Duration(hours: 13)), d.add(const Duration(hours: 14, minutes: 30)))];
  }
}
