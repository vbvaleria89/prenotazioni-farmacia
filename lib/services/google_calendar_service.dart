import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import '../models/appointment.dart';
import 'calendar_service.dart';

@JS('gcal')
external JSObject? get _gcal;

/// Google Calendar reale (web) sul calendario unico "Stanza servizi".
/// Se non collegato, ripiega sul mock (e la UI staff lo segnala).
class GoogleCalendarService implements CalendarService {
  final CalendarService fallback;
  GoogleCalendarService({required this.fallback});

  bool get available => _gcal != null;
  bool get isConnected => available && (_gcal!.callMethod<JSBoolean>('isConnected'.toJS)).toDart;

  Future<void> connect() async {
    if (!available) throw StateError('Google Calendar disponibile solo nella versione web');
    await _gcal!.callMethod<JSPromise>('connect'.toJS).toDart;
  }

  void disconnect() { if (available) _gcal!.callMethod<JSAny?>('disconnect'.toJS); }

  @override
  Future<String> createEvent(Appointment a) async {
    if (!isConnected) return fallback.createEvent(a);
    // Nome operatore consentito; nessun dato identificativo/sanitario del cliente.
    final r = await _gcal!.callMethod<JSPromise<JSString>>('createEvent'.toJS,
        _title(a).toJS, _description(a).toJS,
        a.start.toUtc().toIso8601String().toJS, a.end.toUtc().toIso8601String().toJS).toDart;
    return r.toDart;
  }

  String _title(Appointment a) => [a.service.name, a.stanzaLabel,
    if ((a.employeeNome ?? '').trim().isNotEmpty) a.employeeNome!.trim(), a.shortCode].join(' · ');
  String _description(Appointment a) => 'Prenotazione app · ${a.stanzaLabel}'
    '${(a.employeeNome ?? '').trim().isNotEmpty ? ' · Operatore: ${a.employeeNome!.trim()}' : ''} · codice ${a.shortCode}';

  /// PATCH dell'evento esistente: non perdiamo il riferimento se Google fallisce.
  Future<String> syncEvent(Appointment a, String? eventId) async {
    if (eventId == null || eventId.startsWith('mock-')) return createEvent(a);
    if (!isConnected) throw StateError('Google Calendar non collegato');
    final result = await _gcal!.callMethodVarArgs<JSPromise<JSString>>('updateEvent'.toJS, [eventId.toJS,
      _title(a).toJS, _description(a).toJS,
      a.start.toUtc().toIso8601String().toJS, a.end.toUtc().toIso8601String().toJS]).toDart;
    return result.toDart;
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    if (!isConnected || eventId.startsWith('mock-')) return fallback.deleteEvent(eventId);
    await _gcal!.callMethod<JSPromise>('deleteEvent'.toJS, eventId.toJS).toDart;
  }

  @override
  Future<List<(DateTime, DateTime)>> busyIntervals(DateTime day) async {
    if (!isConnected) return fallback.busyIntervals(day);
    final d = DateTime(day.year, day.month, day.day);
    final r = await _gcal!.callMethod<JSPromise<JSString>>('busy'.toJS,
        d.toUtc().toIso8601String().toJS, d.add(const Duration(days: 1)).toUtc().toIso8601String().toJS).toDart;
    return [
      for (final b in jsonDecode(r.toDart) as List)
        (DateTime.parse(b['start'] as String).toLocal(), DateTime.parse(b['end'] as String).toLocal())
    ];
  }
}
