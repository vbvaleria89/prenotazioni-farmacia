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
    final r = await _gcal!.callMethod<JSPromise<JSString>>('createEvent'.toJS,
        _title(a).toJS, _description(a).toJS,
        a.start.toUtc().toIso8601String().toJS, a.end.toUtc().toIso8601String().toJS).toDart;
    return r.toDart;
  }

  String _customerLabel(Appointment a) {
    final name = a.customerName.trim();
    if (name.isNotEmpty) return name;
    final mail = (a.email ?? '').trim();
    if (mail.isNotEmpty) return mail;
    return 'Cliente';
  }

  String? _telUri(String phone) {
    var n = phone.trim().replaceAll(RegExp(r'[^\d+]'), '');
    if (n.startsWith('00')) n = '+${n.substring(2)}';
    final digits = n.replaceAll('+', '');
    if (digits.length < 6) return null;
    if (n.startsWith('+')) return 'tel:$n';
    if (n.startsWith('39') && n.length >= 11) return 'tel:+$n';
    if (n.startsWith('0')) return 'tel:+39${n.substring(1)}';
    return 'tel:+39$n';
  }

  String _statusLabel(AppointmentStatus s) => switch (s) {
        AppointmentStatus.inAttesa => 'Da confermare',
        AppointmentStatus.confermato => 'Confermato',
        AppointmentStatus.completato => 'Effettuata',
        AppointmentStatus.annullato => 'Annullato',
      };

  String _title(Appointment a) => '${_customerLabel(a)} · ${a.service.name}';

  String _description(Appointment a) {
    final lines = <String>[];
    final phone = a.phone.trim();
    if (phone.isNotEmpty) {
      final href = _telUri(phone);
      lines.add(href != null ? 'Telefono: <a href="$href">$phone</a>' : 'Telefono: $phone');
      if (href != null) lines.add(href);
    }
    lines.add('Servizio: ${a.service.name}');
    lines.add('Stanza: ${a.stanzaLabel}');
    final op = (a.employeeNome ?? '').trim();
    if (op.isNotEmpty) lines.add('Operatore: $op');
    var stato = 'Stato: ${_statusLabel(a.status)}';
    if (a.pagato) {
      stato += switch (a.metodoPagamento) {
        'carta' => ' · Pagato · Carta',
        'contanti' => ' · Pagato · Contanti',
        'bancomat' => ' · Pagato · Bancomat',
        _ => ' · Pagato',
      };
    }
    lines.add(stato);
    lines.add('Codice: ${a.shortCode}');
    return lines.join('\n');
  }

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
