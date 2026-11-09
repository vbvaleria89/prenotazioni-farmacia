import 'auth_persistence.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/appointment.dart';
import '../models/fascia.dart';
import '../models/codice_fiscale.dart';
import '../models/customer_bookings.dart';
import '../models/customer.dart';
import '../models/service_type.dart';
import '../models/settings.dart';
import 'google_calendar_service.dart';

/// Prenotazioni su Firestore. Due stanze fisse (1 e 2): overlap solo sulla stessa stanza.
/// `roomDays/{yyyy-mm-dd}` contiene blocks con roomId; una prenotazione occupa UNA sola stanza.
/// Se il servizio ammette entrambe, si sceglie la prima libera (preferenza 1 poi 2).
/// Calendar: sincronizzato lato server (`/api/gcal-sync`) dopo ogni scrittura.
/// Non dipende dal token Google nel browser.
class _DeviceBusyInTx implements Exception {}

class BookingService extends ChangeNotifier {
  final GoogleCalendarService calendar;
  BookingService({required this.calendar});

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  static const slotStep = Duration(minutes: 15);
  /// Evita doppie scritture concurrent su scadute → completato.
  final Set<String> _markingExpired = {};

  /// Cache di sessione per il calcolo slot.
  Map<String, List<Fascia>>? _fasceByDay;
  DateTime? _fasceRangeStart, _fasceRangeEnd;
  Future<Map<String, List<Fascia>>>? _fasceRangeLoading;
  Map<String, List<String>>? _staffServicesCache;
  Future<Map<String, List<String>>>? _staffServicesLoading;
  final Map<String, Map<String, dynamic>?> _roomDayCache = {};
  final Map<String, List<Appointment>> _apptsDayCache = {};
  final Map<String, List<DeviceHold>> _deviceDayCache = {};
  final Map<String, (List<DateTime> slots, Map<DateTime, List<(String, String)>> people)> _slotsCache = {};
  int _slotQueries = 0;
  /// Ultima misurazione di [availableSlots] (query Firestore e millisecondi).
  int lastSlotQueryCount = 0;
  int lastSlotMs = 0;

  void _clearSlotOccupancyCache() {
    _roomDayCache.clear();
    _apptsDayCache.clear();
    _deviceDayCache.clear();
    _slotsCache.clear();
  }

  void _invalidateStaticSlotCache() {
    _fasceByDay = null;
    _fasceRangeStart = null;
    _fasceRangeEnd = null;
    _fasceRangeLoading = null;
    _staffServicesCache = null;
    _staffServicesLoading = null;
    _clearSlotOccupancyCache();
  }

  @override
  void notifyListeners() {
    _clearSlotOccupancyCache();
    super.notifyListeners();
  }

  bool _fasceRangeCovers(DateTime start, DateTime end) =>
      _fasceByDay != null &&
      _fasceRangeStart != null &&
      _fasceRangeEnd != null &&
      !_fasceRangeStart!.isAfter(_d0(start)) &&
      !_fasceRangeEnd!.isBefore(_d0(end));

  Future<Map<String, List<Fascia>>> _ensureFasceRange(DateTime start, DateTime end) async {
    start = _d0(start);
    end = _d0(end);
    if (_fasceRangeCovers(start, end)) return _fasceByDay!;
    if (_fasceRangeLoading != null) {
      final loaded = await _fasceRangeLoading!;
      if (_fasceRangeCovers(start, end)) return loaded;
    }
    final fut = () async {
      _slotQueries++;
      final q = await _db.collection('availability')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: availKey(start))
          .where(FieldPath.documentId, isLessThanOrEqualTo: availKey(end))
          .get();
      final map = {for (final d in q.docs) d.id: fasceOf(d.data())};
      _fasceByDay = map;
      _fasceRangeStart = start;
      _fasceRangeEnd = end;
      return map;
    }();
    _fasceRangeLoading = fut;
    try {
      return await fut;
    } finally {
      if (identical(_fasceRangeLoading, fut)) _fasceRangeLoading = null;
    }
  }

  DateTime _parseAvailKey(String id) {
    final parts = id.split('-');
    if (parts.length != 3) return DateTime(0);
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return DateTime(0);
    return DateTime(y, m, d);
  }

  Future<Map<String, dynamic>?> _roomDayData(DateTime day) async {
    final key = _dayKey(day);
    if (_roomDayCache.containsKey(key)) return _roomDayCache[key];
    try {
      _slotQueries++;
      final data = (await _db.doc('roomDays/$key').get()).data();
      _roomDayCache[key] = data;
      return data;
    } catch (_) {
      _roomDayCache[key] = null;
      return null;
    }
  }

  String _slotsCacheKey(ServiceType service, DateTime day, {String? excludeId, DateTime? keepSlot}) =>
      '${service.id}|${availKey(day)}|${excludeId ?? ''}|${keepSlot?.millisecondsSinceEpoch ?? 0}';

  /// Persone libere per gli slot già calcolati (stessa cache di [availableSlots], niente letture extra).
  Map<DateTime, List<(String, String)>> slotPeople(ServiceType service, DateTime day, {String? excludeId, DateTime? keepSlot}) =>
      Map.of(_slotsCache[_slotsCacheKey(service, day, excludeId: excludeId, keepSlot: keepSlot)]?.$2 ?? const {});

  void prefetchSlots(ServiceType service, DateTime day, {String? excludeId, DateTime? keepSlot}) {
    unawaited(availableSlots(service, day, excludeId: excludeId, keepSlot: keepSlot));
  }

  CollectionReference<Map<String, dynamic>> get _appts => _db.collection('appointments');
  DocumentReference<Map<String, dynamic>> get settingsRef => _db.doc('settings/pharmacy');

  /// Clienti senza login: sessione anonima (serve perché le regole richiedono auth).
  Future<void> ensureClientAuth() async {
    if (_auth.currentUser != null || authLoginInProgress) return;
    try {
      await _auth.signInAnonymously();
    } on FirebaseAuthException catch (e) {
      throw StateError(e.code == 'admin-restricted-operation' || e.code == 'operation-not-allowed'
          ? 'Prenotazione online non ancora attiva (accesso anonimo da abilitare in Firebase). Chiama la farmacia.'
          : 'Accesso non riuscito: ${e.code}');
    }
  }

  Future<PharmacySettings> settings() async => PharmacySettings.fromMap((await settingsRef.get()).data());
  Stream<PharmacySettings> settingsStream() => settingsRef.snapshots().map((d) => PharmacySettings.fromMap(d.data()));
  Future<void> saveSettings(PharmacySettings s) => settingsRef.set(s.toMap(), SetOptions(merge: true));

  // ---- Servizi (collection `services`) ----
  CollectionReference<Map<String, dynamic>> get servicesRef => _db.collection('services');

  /// Tutti i servizi (anche disattivati), ordinati. Aggiorna il registry.
  Stream<List<ServiceType>> watchServices() => servicesRef.snapshots().map((q) {
        final list = q.docs.map(ServiceType.fromDoc).toList()..sort((a, b) => a.ordine != b.ordine ? a.ordine.compareTo(b.ordine) : a.name.compareTo(b.name));
        for (final s in list) { ServiceType.registry[s.id] = s; }
        return list.isEmpty ? List<ServiceType>.from(mockServices) : list;
      });

  Stream<List<ServiceType>> watchActiveServices() async* {
    await ensureClientAuth();
    yield* watchServices().map((l) => l.where((s) => s.attivo).toList());
  }

  Future<void> saveService(ServiceType s) => servicesRef.doc(s.id).set(s.toMap(), SetOptions(merge: true));

  /// Seed/migrazione: se `services` è vuota crea i servizi di base, importando giorni e persona del tricologico da settings.
  Future<void> seedServicesIfEmpty() async {
    if ((await servicesRef.limit(1).get()).docs.isNotEmpty) return;
    final cfg = await settings();
    for (final s in mockServices) {
      final t = s.id == 'tricologico';
      await saveService(ServiceType(id: s.id, name: s.name, description: s.description, duration: s.duration, ordine: s.ordine,
          giorni: t ? cfg.tricologicoDays : const {}, dipendenteId: t ? cfg.tricologoEmployeeId : '', dipendenteNome: t ? cfg.tricologoNome : '',
          stanze: s.stanze, deviceId: s.deviceId, deviceHoldHours: s.deviceHoldHours));
    }
  }

  /// Collega ogni servizio Holter al proprio apparecchio (cardiaco ≠ pressorio), 1 pezzo e 24 ore, se i campi mancano o sono lo slug condiviso precedente.
  Future<void> seedHolterDevice() async {
    await Device.seedIfEmpty();
    final q = await servicesRef.get();
    for (final d in q.docs) {
      final raw = d.data();
      final nome = (raw['nome'] ?? d.id).toString();
      final inferred = Device.inferredId(nome, id: d.id);
      if (inferred == null) continue;
      final rawId = (raw['deviceId'] ?? '').toString().trim();
      final rawHours = (raw['deviceHoldHours'] as num?)?.toInt() ?? 0;
      final wrongShared = rawId.isNotEmpty && rawId != inferred
          && (rawId == Device.holterId || rawId == Device.holterPressorioId);
      if (rawId.isNotEmpty && rawHours > 0 && !wrongShared) continue;
      await servicesRef.doc(d.id).set({
        'deviceId': inferred,
        'deviceHoldHours': rawHours > 0 ? rawHours : Device.holterDefaultHours,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Sposta su `holter-pressorio` prenotazioni e hold che erano finiti sotto l'apparecchio cardiaco.
  Future<void> _reassignPressorioDeviceHolds() async {
    Future<String?> wantedFor(String serviceId, String serviceName, String deviceId) async {
      final inferred = Device.inferredId(serviceName, id: serviceId);
      if (inferred == Device.holterPressorioId && deviceId != inferred) return inferred;
      return null;
    }

    try {
      final byService = await _appts.where('servizio', isEqualTo: Device.holterPressorioId).get();
      final byDevice = await _appts.where('deviceId', isEqualTo: Device.holterId).get();
      final seen = <String>{};
      for (final d in [...byService.docs, ...byDevice.docs]) {
        if (!seen.add(d.id)) continue;
        final m = d.data();
        final want = await wantedFor((m['servizio'] ?? '').toString(), (m['servizioNome'] ?? '').toString(), (m['deviceId'] ?? '').toString());
        if (want == null) continue;
        await d.reference.set({'deviceId': want, 'deviceHoldHours': (m['deviceHoldHours'] as num?)?.toInt() ?? Device.holterDefaultHours, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      }
    } catch (_) {}

    try {
      final days = await _db.collection('deviceDays').get();
      for (final doc in days.docs) {
        final raw = doc.data()['holds'];
        if (raw is! Map) continue;
        final next = <String, dynamic>{};
        raw.forEach((k, v) => next[k.toString()] = v);
        var changed = false;
        for (final id in next.keys.toList()) {
          final h = next[id];
          if (h is! Map) continue;
          final cur = (h['deviceId'] ?? '').toString();
          if (cur != Device.holterId) continue;
          String serviceId = '';
          String serviceName = '';
          try {
            final ap = await _appts.doc(id).get();
            serviceId = (ap.data()?['servizio'] ?? '').toString();
            serviceName = (ap.data()?['servizioNome'] ?? '').toString();
          } catch (_) {}
          final want = Device.inferredId(serviceName, id: serviceId);
          if (want != Device.holterPressorioId) continue;
          next[id] = {...Map<String, dynamic>.from(h), 'deviceId': Device.holterPressorioId};
          changed = true;
        }
        if (changed) {
          await doc.reference.set({'holds': next, 'touched': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        }
      }
    } catch (_) {}
  }

  // ---- Disponibilità giornaliere (collection `availability/{yyyy-mm-dd}`) ----
  /// Fasce {start,end} in minuti dalla mezzanotte. Nessun documento/fasce = chiuso.
  static String availKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  DocumentReference<Map<String, dynamic>> availRef(DateTime d) => _db.doc('availability/${availKey(d)}');
  static List<(int, int)> rangesOf(Map<String, dynamic>? m) {
    final raw = m?['fasce'];
    if (raw is! List) return const [];
    final out = <(int, int)>[];
    for (final f in raw) {
      if (f is Map && f['start'] is num && f['end'] is num) out.add(((f['start'] as num).toInt(), (f['end'] as num).toInt()));
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }
  Future<List<(int, int)>> availability(DateTime d) async {
    final f = await fasce(d);
    return [for (final x in f) (x.start, x.end)];
  }
  Stream<Map<String, List<(int, int)>>> watchAvailabilityMonth(DateTime month) => _db.collection('availability')
      .where(FieldPath.documentId, isGreaterThanOrEqualTo: availKey(DateTime(month.year, month.month, 1)))
      .where(FieldPath.documentId, isLessThanOrEqualTo: availKey(DateTime(month.year, month.month + 1, 0)))
      .snapshots().map((q) => {for (final d in q.docs) d.id: rangesOf(d.data())});
  /// Fasce complete (con persona). Le vecchie senza `employeeId` sono generiche «Farmacia».
  static List<Fascia> fasceOf(Map<String, dynamic>? m) {
    final raw = m?['fasce'];
    if (raw is! List) return const [];
    final out = [for (final f in raw) Fascia.fromMap(f)].whereType<Fascia>().toList()
      ..sort((a, b) => a.start != b.start ? a.start.compareTo(b.start) : a.chi.compareTo(b.chi));
    return out;
  }
  Future<List<Fascia>> fasce(DateTime d) async {
    final key = availKey(d);
    final day = _d0(d);
    if (_fasceRangeCovers(day, day)) return _fasceByDay![key] ?? const [];
    try {
      final today = _d0(DateTime.now());
      final horizon = today.add(const Duration(days: 60));
      if (!day.isBefore(today) && !day.isAfter(horizon)) {
        final map = await _ensureFasceRange(today, horizon);
        return map[key] ?? const [];
      }
    } catch (_) {}
    _slotQueries++;
    final list = fasceOf((await availRef(d).get()).data());
    (_fasceByDay ??= {})[key] = list;
    return list;
  }
  Stream<Map<String, List<Fascia>>> watchFasceMonth(DateTime month) => _db.collection('availability')
      .where(FieldPath.documentId, isGreaterThanOrEqualTo: availKey(DateTime(month.year, month.month, 1)))
      .where(FieldPath.documentId, isLessThanOrEqualTo: availKey(DateTime(month.year, month.month + 1, 0)))
      .snapshots().map((q) => {for (final d in q.docs) d.id: fasceOf(d.data())});
  Future<void> saveFasce(DateTime d, List<Fascia> fasce) async {
    _invalidateStaticSlotCache();
    if (fasce.isEmpty) {
      await availRef(d).delete();
    } else {
      await availRef(d).set({'fasce': [for (final f in fasce) f.toMap()], 'updatedAt': FieldValue.serverTimestamp()});
    }
  }
  /// Una transazione atomica sul mese (massimo 31 documenti): preserva modifiche concorrenti.
  Future<int> deleteFasce(List<(DateTime, Fascia)> rows) async {
    final grouped = <String, List<Fascia>>{};
    for (final r in rows) { grouped.putIfAbsent(availKey(r.$1), () => []).add(r.$2); }
    if (grouped.length > 31) throw StateError('Seleziona un mese alla volta');
    return _db.runTransaction((tx) async {
      final docs = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final key in grouped.keys) { docs.add(await tx.get(_db.doc('availability/$key'))); }
      var removed = 0;
      for (final doc in docs) {
        final current = fasceOf(doc.data());
        final next = current.where((f) => !grouped[doc.id]!.any((x) => x.same(f))).toList();
        removed += current.length - next.length;
        if (current.length == next.length) continue;
        if (next.isEmpty) { tx.delete(doc.reference); } else {
          tx.update(doc.reference, {'fasce': [for (final f in next) f.toMap()], 'updatedAt': FieldValue.serverTimestamp()});
        }
      }
      return removed;
    }).whenComplete(_invalidateStaticSlotCache);
  }

  Future<void> saveAvailability(DateTime d, List<(int, int)> fasce) => saveFasce(d, [for (final f in fasce) Fascia(f.$1, f.$2)]);

  // ---- Servizi per persona (collection pubblica `staffServices/{uid}` = {servizi: [serviceId]}) ----
  /// Nessun documento o lista vuota = la persona può fare TUTTI i servizi attivi (migrazione soft).
  Future<Map<String, List<String>>> staffServices() async {
    if (_staffServicesCache != null) return _staffServicesCache!;
    if (_staffServicesLoading != null) return _staffServicesLoading!;
    final fut = () async {
      try {
        _slotQueries++;
        final q = await _db.collection('staffServices').get();
        final map = {for (final d in q.docs) d.id: [for (final x in (d.data()['servizi'] as List? ?? const [])) x.toString()]};
        _staffServicesCache = map;
        return map;
      } catch (_) {
        return const <String, List<String>>{};
      }
    }();
    _staffServicesLoading = fut;
    try {
      return await fut;
    } finally {
      if (identical(_staffServicesLoading, fut)) _staffServicesLoading = null;
    }
  }
  Future<void> saveStaffServices(String uid, List<String> servizi) async {
    _staffServicesCache = null;
    _staffServicesLoading = null;
    _slotsCache.clear();
    await _db.doc('staffServices/$uid').set({'servizi': servizi, 'updatedAt': FieldValue.serverTimestamp()});
  }
  static bool canDo(Map<String, List<String>> svc, String? emp, String serviceId) {
    if (emp == null || emp.isEmpty) return true;
    final l = svc[emp];
    return l == null || l.isEmpty || l.contains(serviceId);
  }
  /// Fasce utili per il servizio: generiche + quelle delle persone abilitate.
  Future<List<Fascia>> _fasceFor(ServiceType service, DateTime d, [Map<String, List<String>>? svc]) async {
    final all = (await fasce(d)).where((f) => f.vale(service.id)).toList();
    if (all.every((f) => f.generica)) return all;
    final s = svc ?? await staffServices();
    return all.where((f) => canDo(s, f.employeeId, service.id)).toList();
  }

  /// (blockId, start, end, status, employeeId) dai blocchi giornalieri.
  List<(String, DateTime, DateTime, String, String?)> _empBlocksOf(Map<String, dynamic>? data) {
    final raw = data?['blocks'];
    if (raw is! Map) return const [];
    final out = <(String, DateTime, DateTime, String, String?)>[];
    raw.forEach((id, v) {
      if (v is! Map || v['start'] is! Timestamp || v['end'] is! Timestamp) return;
      final e = v['employeeId'];
      out.add((id.toString(), (v['start'] as Timestamp).toDate(), (v['end'] as Timestamp).toDate(), (v['status'] ?? 'inAttesa').toString(), e is String && e.isNotEmpty ? e : null));
    });
    return out;
  }
  bool _personBusy(String emp, DateTime s, DateTime e, List<(String, DateTime, DateTime, String, String?)> eb, List<Appointment> appts, {String? excludeId}) =>
      eb.any((b) => b.$1 != excludeId && b.$5 == emp && _blocksRoomStatus(b.$4) && _hits(s, e, b.$2, b.$3))
      || appts.any((a) => a.id != excludeId && a.blocksRoom && a.employeeId == emp && a.overlaps(s, e));

  /// Persone con fascia che copre [s,e], abilitate al servizio e senza altre prenotazioni sovrapposte.
  List<(String, String)> _freePeople(List<Fascia> fasce, DateTime s, DateTime e, List<(String, DateTime, DateTime, String, String?)> eb, List<Appointment> appts, {String? excludeId}) {
    final a = s.hour * 60 + s.minute, b = a + e.difference(s).inMinutes;
    final out = <String, String>{};
    for (final f in fasce) {
      if (f.generica || !f.covers(a, b) || out.containsKey(f.employeeId)) continue;
      if (_personBusy(f.employeeId!, s, e, eb, appts, excludeId: excludeId)) continue;
      out[f.employeeId!] = f.chi;
    }
    return [for (final x in out.entries) (x.key, x.value)];
  }
  bool _genericCovers(List<Fascia> fasce, DateTime s, DateTime e) {
    final a = s.hour * 60 + s.minute, b = a + e.difference(s).inMinutes;
    return fasce.any((f) => f.generica && f.covers(a, b));
  }

  /// Staff/admin: chi è libero per [service] alle [start] (fascia + servizio + nessun altro appuntamento).
  Future<List<(String, String)>> freeEmployees(ServiceType service, DateTime start, {String? excludeId}) async {
    final end = start.add(service.duration);
    final f = await _fasceFor(service, start);
    final appts = await _appointmentsOrEmpty(start);
    final eb = _empBlocksOf((await _db.doc('roomDays/${_dayKey(start)}').get()).data());
    return _freePeople(f, start, end, eb, appts, excludeId: excludeId);
  }

  /// Sceglie la persona per una prenotazione. [prefer] (scelta banco o dipendente del servizio) se libera;
  /// altrimenti la prima libera; se copre solo una fascia generica → nessuna persona (come prima).
  Future<(String?, String?)> _resolveEmployee(ServiceType service, DateTime s, DateTime e, {String? prefer, String? preferNome, String? excludeId, bool manual = false, bool strict = false}) async {
    final f = await _fasceFor(service, s);
    final appts = await _appointmentsOrEmpty(s);
    final eb = _empBlocksOf((await _db.doc('roomDays/${_dayKey(s)}').get()).data());
    final free = _freePeople(f, s, e, eb, appts, excludeId: excludeId);
    if (prefer != null && prefer.isNotEmpty) {
      for (final p in free) { if (p.$1 == prefer) return (p.$1, p.$2); }
      final busy = _personBusy(prefer, s, e, eb, appts, excludeId: excludeId);
      if (busy && (strict || manual)) throw StateError('${preferNome ?? 'La persona scelta'} ha già una prenotazione in questo orario');
      if (!busy && (manual || strict)) return (prefer, preferNome);
    }
    if (free.isNotEmpty) return (free.first.$1, free.first.$2);
    if (manual || _genericCovers(f, s, e)) return (null, null);
    throw StateError('Nessuna persona disponibile per questo servizio in questo orario');
  }

  static bool _inRanges(List<(int, int)> r, DateTime s, DateTime e) {
    final a = s.hour * 60 + s.minute, b = a + e.difference(s).inMinutes;
    return r.any((f) => a >= f.$1 && b <= f.$2);
  }
  Future<void> _checkAvailable(DateTime s, DateTime e, [ServiceType? service]) async {
    final r = service == null ? await availability(s) : [for (final f in await _fasceFor(service, s)) (f.start, f.end)];
    if (!_inRanges(r, s, e)) throw StateError('Orario fuori dalle disponibilità della farmacia');
  }

  static DateTime _d0(DateTime d) => DateTime(d.year, d.month, d.day);
  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Blocco: (id, start, end, status, roomId). Senza dati cliente; leggibile anche dagli anonimi.
  List<(String, DateTime, DateTime, String, int)> _blocksOf(Map<String, dynamic>? data) {
    final raw = data?['blocks'];
    if (raw is! Map) return const [];
    final out = <(String, DateTime, DateTime, String, int)>[];
    raw.forEach((id, value) {
      if (value is! Map) return;
      final start = value['start'];
      final end = value['end'];
      if (start is! Timestamp || end is! Timestamp) return;
      final room = (value['roomId'] as num?)?.toInt();
      out.add((id.toString(), start.toDate(), end.toDate(), (value['status'] ?? 'inAttesa') as String,
          room ?? kStanza1));
    });
    return out;
  }

  bool _blocksRoomStatus(String status) => status == AppointmentStatus.inAttesa.name || status == AppointmentStatus.confermato.name;

  Map<String, dynamic> _blockMap(DateTime start, DateTime end, String status, int roomId, [String? employeeId]) => {
        if (employeeId != null && employeeId.isNotEmpty) 'employeeId': employeeId,
        'start': Timestamp.fromDate(start),
        'end': Timestamp.fromDate(end),
        'status': status,
        'roomId': roomId,
        'roomName': Room.registry[roomId]?.nome,
      };

  Future<List<(String, DateTime, DateTime, String, int)>> _blocks(DateTime day) async =>
      _blocksOf(await _roomDayData(day));

  Future<void> _backfillBlocks(DateTime day, List<Appointment> appts) async {
    if (appts.isEmpty) return;
    final ref = _db.doc('roomDays/${_dayKey(day)}');
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final blocks = <String, dynamic>{};
      final current = snap.data()?['blocks'];
      if (current is Map) {
        current.forEach((key, value) => blocks[key.toString()] = value);
      }
      var changed = false;
      for (final a in appts) {
        final cur = blocks[a.id];
        if (cur is Map) {
          // Migrazione soft: aggiungi roomId ai blocchi vecchi.
          if (cur['roomId'] == null || (cur['employeeId'] == null && (a.employeeId ?? '').isNotEmpty)) {
            blocks[a.id] = {...Map<String, dynamic>.from(cur), 'roomId': a.roomId, if ((a.employeeId ?? '').isNotEmpty) 'employeeId': a.employeeId};
            changed = true;
          }
          continue;
        }
        blocks[a.id] = _blockMap(a.start, a.end, a.status.name, a.roomId, a.employeeId);
        changed = true;
      }
      if (changed) tx.set(ref, {'blocks': blocks, 'touched': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    });
  }

  /// Lo staff può ancora leggere le prenotazioni: copia i prossimi giorni nei blocchi stanza.
  Future<void> backfillUpcomingBlocks({int days = 21}) async {
    final start = _d0(DateTime.now());
    for (var i = 0; i < days; i++) {
      final day = start.add(Duration(days: i));
      try {
        await _backfillBlocks(day, await forDay(day));
      } catch (_) {}
    }
  }

  Future<void> _setBlockStatus(Appointment a, String status) async {
    final ref = _db.doc('roomDays/${_dayKey(a.start)}');
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final blocks = <String, dynamic>{};
        final current = snap.data()?['blocks'];
        if (current is Map) current.forEach((key, value) => blocks[key.toString()] = value);
        final cur = blocks[a.id];
        if (cur is! Map) return;
        blocks[a.id] = {...Map<String, dynamic>.from(cur), 'status': status};
        tx.set(ref, {'blocks': blocks, 'touched': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      });
    } catch (_) {}
  }
  Query<Map<String, dynamic>> _dayQuery(DateTime day) => _appts
      .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(_d0(day)))
      .where('start', isLessThan: Timestamp.fromDate(_d0(day).add(const Duration(days: 1))));

  Future<List<Appointment>> forDay(DateTime day) async =>
      ((await _dayQuery(day).get()).docs.map(Appointment.fromDoc).toList())..sort((a, b) => a.start.compareTo(b.start));

  Stream<List<Appointment>> watchDay(DateTime day) => _dayQuery(day)
      .snapshots()
      .map((q) {
        final list = q.docs.map(Appointment.fromDoc).toList()..sort((a, b) => a.start.compareTo(b.start));
        unawaited(markExpiredCompleted(list));
        return list;
      });

  Stream<List<Appointment>> watchRange(DateTime from, DateTime to) => _appts
      .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .where('start', isLessThan: Timestamp.fromDate(to))
      .snapshots()
      .map((q) {
        final list = q.docs.map(Appointment.fromDoc).toList()..sort((a, b) => a.start.compareTo(b.start));
        unawaited(markExpiredCompleted(list));
        return list;
      });

  Future<List<(DateTime, DateTime)>> _busy(DateTime day) async {
    if (!calendar.isConnected) return [];
    try { return await calendar.busyIntervals(day); } catch (_) { return []; }
  }

  bool _hits(DateTime s, DateTime e, DateTime bs, DateTime be) => bs.isBefore(e) && s.isBefore(be);

  /// Libero sulla STESSA stanza (e nessun busy Calendar globale).
  bool _freeOnRoom(int roomId, DateTime s, DateTime e, List<Appointment> appts, List<(String, DateTime, DateTime, String, int)> blocks, List<(DateTime, DateTime)> busy, {String? excludeId}) =>
      !appts.any((a) => a.id != excludeId && a.blocksRoom && a.roomId == roomId && a.overlaps(s, e))
      && !blocks.any((b) => b.$1 != excludeId && b.$5 == roomId && _blocksRoomStatus(b.$4) && _hits(s, e, b.$2, b.$3))
      && !busy.any((b) => b.$1.isBefore(e) && s.isBefore(b.$2));

  /// Prima stanza libera tra quelle ammesse dal servizio (ordine 1 poi 2). Null = nessuna.
  int? _pickRoom(ServiceType service, DateTime s, DateTime e, List<Appointment> appts, List<(String, DateTime, DateTime, String, int)> blocks, List<(DateTime, DateTime)> busy, {String? excludeId, int? prefer}) {
    final allowed = service.stanzeOrdinate;
    if (prefer != null && allowed.contains(prefer) && _freeOnRoom(prefer, s, e, appts, blocks, busy, excludeId: excludeId)) {
      return prefer;
    }
    for (final r in allowed) {
      if (_freeOnRoom(r, s, e, appts, blocks, busy, excludeId: excludeId)) return r;
    }
    return null;
  }

  bool _slotOk(ServiceType service, DateTime s, DateTime e, List<Appointment> appts, List<(String, DateTime, DateTime, String, int)> blocks, List<(DateTime, DateTime)> busy, {String? excludeId, List<DeviceHold> deviceHolds = const []}) =>
      _pickRoom(service, s, e, appts, blocks, busy, excludeId: excludeId) != null
      && _deviceFree(service, s, deviceHolds, excludeId: excludeId);

  DocumentReference<Map<String, dynamic>> _deviceDayRef(DateTime d) => _db.doc('deviceDays/${_dayKey(d)}');

  List<DeviceHold> _holdsOf(Map<String, dynamic>? data) {
    final raw = data?['holds'];
    if (raw is! Map) return const [];
    final out = <DeviceHold>[];
    raw.forEach((id, v) {
      if (v is! Map) return;
      final start = v['start'];
      final end = v['holdEnd'];
      if (start is! Timestamp || end is! Timestamp) return;
      final dev = (v['deviceId'] ?? '').toString();
      if (dev.isEmpty) return;
      out.add(DeviceHold(appointmentId: id.toString(), deviceId: dev, start: start.toDate(), holdEnd: end.toDate(), status: (v['status'] ?? 'inAttesa').toString()));
    });
    return out;
  }

  Map<String, dynamic> _holdEntry(String deviceId, DateTime start, DateTime holdEnd, String status) => {
        'deviceId': deviceId,
        'start': Timestamp.fromDate(start),
        'holdEnd': Timestamp.fromDate(holdEnd),
        'status': status,
      };

  Future<List<DeviceHold>> _loadDeviceHoldsRange(DateTime from, DateTime to) async {
    final end = to.isAfter(from) ? to : from.add(const Duration(seconds: 1));
    final out = <DeviceHold>[];
    final missing = <DateTime>[];
    for (final d in daysOverlappingHold(from, end)) {
      final key = _dayKey(d);
      if (_deviceDayCache.containsKey(key)) {
        out.addAll(_deviceDayCache[key]!);
      } else {
        missing.add(d);
      }
    }
    if (missing.isNotEmpty) {
      final snaps = await Future.wait(missing.map((d) async {
        try {
          _slotQueries++;
          return (d, _holdsOf((await _deviceDayRef(d).get()).data()));
        } catch (_) {
          return (d, const <DeviceHold>[]);
        }
      }));
      for (final item in snaps) {
        _deviceDayCache[_dayKey(item.$1)] = item.$2;
        out.addAll(item.$2);
      }
    }
    return out;
  }

  /// Per uno slot a [start], servono i giorni che coprono [start-hold, start+hold) così si vedono anche gli hold iniziati il giorno prima.
  Future<List<DeviceHold>> _loadDeviceHoldsAround(DateTime start, int holdHours) async {
    if (holdHours <= 0) return const [];
    return _loadDeviceHoldsRange(start.subtract(Duration(hours: holdHours)), start.add(Duration(hours: holdHours)));
  }

  Future<List<DocumentSnapshot<Map<String, dynamic>>>> _txDeviceDaySnaps(Transaction tx, Iterable<DateTime> days) async {
    final seen = <String>{};
    final snaps = <DocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in days) {
      if (!seen.add(_dayKey(d))) continue;
      snaps.add(await tx.get(_deviceDayRef(d)));
    }
    return snaps;
  }

  List<DeviceHold> _holdsFromSnaps(Iterable<DocumentSnapshot<Map<String, dynamic>>> snaps) =>
      [for (final s in snaps) ..._holdsOf(s.data())];

  bool _deviceFree(ServiceType service, DateTime start, Iterable<DeviceHold> holds, {String? excludeId}) {
    if (!service.usesDevice) return true;
    final n = countOverlappingDeviceHolds(
      deviceId: service.deviceId,
      windowStart: start,
      windowEnd: service.deviceHoldEnd(start),
      holds: holds,
      excludeId: excludeId,
    );
    return isDeviceQuantityFree(quantity: Device.quantityOf(service.deviceId), overlapping: n);
  }

  /// Primo inizio libero >= [requested]: fine dell'occupazione in conflitto, poi (se esistono) il primo slot in fascia.
  Future<DateTime?> nextDeviceBookable(ServiceType service, DateTime requested, {String? excludeId}) async {
    if (!service.usesDevice) return requested;
    final holds = await _loadDeviceHoldsRange(
      requested.subtract(Duration(hours: service.deviceHoldHours)),
      requested.add(const Duration(days: 62)),
    );
    final t = nextFreeDeviceStart(
      deviceId: service.deviceId,
      holdHours: service.deviceHoldHours,
      quantity: Device.quantityOf(service.deviceId),
      requested: requested,
      holds: holds,
      excludeId: excludeId,
    );
    if (t == null) return null;
    final startDay = DateTime(t.year, t.month, t.day);
    for (var i = 0; i < 60; i++) {
      final day = startDay.add(Duration(days: i));
      if (!service.availableOn(day.weekday)) continue;
      final fl = await _fasceFor(service, day);
      if (fl.isEmpty) continue;
      for (final f in fl) {
        for (var slot = day.add(Duration(minutes: f.start)); !slot.add(service.duration).isAfter(day.add(Duration(minutes: f.end))); slot = slot.add(slotStep)) {
          if (slot.isBefore(t)) continue;
          if (_deviceFree(service, slot, holds, excludeId: excludeId)) return slot;
        }
      }
    }
    return t;
  }

  Future<DeviceUnavailableException> _deviceUnavailable(ServiceType service, DateTime start, {String? excludeId}) async =>
      DeviceUnavailableException(service.deviceLabel, nextFree: await nextDeviceBookable(service, start, excludeId: excludeId));

  /// Lettura fresca; se occupato non si deve salvare. Lancia [DeviceUnavailableException].
  Future<void> _ensureDeviceFree(ServiceType service, DateTime start, {String? excludeId}) async {
    if (!service.usesDevice) return;
    final holds = await _loadDeviceHoldsAround(start, service.deviceHoldHours);
    if (!_deviceFree(service, start, holds, excludeId: excludeId)) {
      throw await _deviceUnavailable(service, start, excludeId: excludeId);
    }
  }

  void _assertDeviceFreeTx(ServiceType service, DateTime start, Iterable<DeviceHold> holds, {String? excludeId}) {
    if (!_deviceFree(service, start, holds, excludeId: excludeId)) throw _DeviceBusyInTx();
  }

  /// Null se libero o se il servizio non usa apparecchio; altrimenti messaggio per UI staff (pre-check).
  Future<String?> deviceBusyMessage(ServiceType service, DateTime start, {String? excludeId}) async {
    if (!service.usesDevice) return null;
    final holds = await _loadDeviceHoldsAround(start, service.deviceHoldHours);
    if (_deviceFree(service, start, holds, excludeId: excludeId)) return null;
    return (await _deviceUnavailable(service, start, excludeId: excludeId)).message;
  }

  void _putHold(Transaction tx, DocumentSnapshot<Map<String, dynamic>> snap, String appointmentId, String deviceId, DateTime start, DateTime holdEnd, String status) {
    final next = <String, dynamic>{};
    final cur = snap.data()?['holds'];
    if (cur is Map) cur.forEach((k, v) => next[k.toString()] = v);
    next[appointmentId] = _holdEntry(deviceId, start, holdEnd, status);
    tx.set(snap.reference, {'holds': next, 'touched': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  void _dropHold(Transaction tx, DocumentSnapshot<Map<String, dynamic>> snap, String appointmentId) {
    final next = <String, dynamic>{};
    final cur = snap.data()?['holds'];
    if (cur is Map) cur.forEach((k, v) => next[k.toString()] = v);
    if (!next.containsKey(appointmentId)) return;
    next.remove(appointmentId);
    tx.set(snap.reference, {'holds': next, 'touched': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<void> _setDeviceHoldStatus(Appointment a, String status) async {
    if (!a.usesDevice) return;
    final days = daysOverlappingHold(a.start, a.deviceHoldEnd);
    if (days.isEmpty) return;
    try {
      await _db.runTransaction((tx) async {
        final snaps = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final d in days) {
          snaps.add(await tx.get(_deviceDayRef(d)));
        }
        for (final snap in snaps) {
          final next = <String, dynamic>{};
          final cur = snap.data()?['holds'];
          if (cur is Map) cur.forEach((k, v) => next[k.toString()] = v);
          final existing = next[a.id];
          if (existing is! Map) continue;
          next[a.id] = {...Map<String, dynamic>.from(existing), 'status': status};
          tx.set(snap.reference, {'holds': next, 'touched': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        }
      });
    } catch (_) {}
  }

  /// Scrive (o aggiorna) gli hold dell'apparecchio per una prenotazione già esistente (backfill).
  Future<void> _writeDeviceHoldsDirect(Appointment a) async {
    if (!a.usesDevice || a.status == AppointmentStatus.annullato) return;
    final days = daysOverlappingHold(a.start, a.deviceHoldEnd);
    for (final d in days) {
      final ref = _deviceDayRef(d);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        _putHold(tx, snap, a.id, a.effectiveDeviceId, a.start, a.deviceHoldEnd, a.status.name);
      });
    }
  }

  /// Copia le prenotazioni con apparecchio in `deviceDays` (anche completate: l'apparecchio resta occupato fino a holdEnd).
  Future<void> backfillDeviceHolds({int daysBack = 2, int daysAhead = 21}) async {
    try {
      await seedHolterDevice();
      await _reassignPressorioDeviceHolds();
    } catch (_) {}
    final today = _d0(DateTime.now());
    final from = today.subtract(Duration(days: daysBack + 2));
    final to = today.add(Duration(days: daysAhead + 2));
    try {
      final q = await _appts
          .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('start', isLessThan: Timestamp.fromDate(to))
          .get();
      for (final a in q.docs.map(Appointment.fromDoc)) {
        try {
          await _writeDeviceHoldsDirect(a);
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<List<Appointment>> _appointmentsOrEmpty(DateTime day) async {
    final key = _dayKey(day);
    final cached = _apptsDayCache[key];
    if (cached != null) return cached;
    try {
      _slotQueries++;
      final list = await forDay(day);
      _apptsDayCache[key] = list;
      // Non bloccare la lettura slot: il backfill può avvenire in background.
      unawaited(Future(() async { try { await _backfillBlocks(day, list); } catch (_) {} }));
      return list;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        _apptsDayCache[key] = const [];
        return const [];
      }
      rethrow;
    }
  }

  /// Giorni da oggi in poi (entro [daysAhead]) con almeno una fascia in `availability`.
  Future<List<DateTime>> daysWithAvailability({int daysAhead = 60}) async {
    await ensureClientAuth();
    final start = _d0(DateTime.now());
    final end = start.add(Duration(days: daysAhead));
    final map = await _ensureFasceRange(start, end);
    final days = <DateTime>[];
    for (final e in map.entries) {
      if (e.value.isEmpty) continue;
      final day = _parseAvailKey(e.key);
      if (day.year == 0 || day.isBefore(start)) continue;
      days.add(day);
    }
    days.sort();
    return days;
  }

  /// Primo giorno futuro con fasce e, se possibile, almeno uno slot libero per [service].
  /// Se tutti i giorni con fasce sono pieni, torna comunque il primo con fasce compatibili.
  Future<DateTime?> firstBookableDay(ServiceType service, {int daysAhead = 60}) async {
    final candidates = await daysWithAvailability(daysAhead: daysAhead);
    unawaited(staffServices());
    DateTime? firstWithFasce;
    for (final d in candidates) {
      if (!service.availableOn(d.weekday)) continue;
      firstWithFasce ??= d;
      final slots = await availableSlots(service, d);
      if (slots.isNotEmpty) return d;
    }
    return firstWithFasce;
  }

  /// Slot liberi se almeno una stanza ammessa dal servizio è libera in quell'orario.
  /// [excludeId] ignora quella prenotazione (modifica).
  /// [keepSlot] resta selezionabile anche se nel passato (slot attuale in modifica).
  Future<List<DateTime>> availableSlots(ServiceType service, DateTime day, {String? excludeId, DateTime? keepSlot}) async {
    await ensureClientAuth();
    if (!service.availableOn(day.weekday)) return [];
    final cacheKey = _slotsCacheKey(service, day, excludeId: excludeId, keepSlot: keepSlot);
    final memo = _slotsCache[cacheKey];
    if (memo != null) return List<DateTime>.of(memo.$1);

    _slotQueries = 0;
    final sw = Stopwatch()..start();
    // staffServices in parallelo alle fasce (spesso già in cache dopo il primo giorno).
    final staffFut = staffServices();
    final fl = await _fasceFor(service, day);
    await staffFut;
    if (fl.isEmpty) {
      lastSlotQueryCount = _slotQueries;
      lastSlotMs = sw.elapsedMilliseconds;
      _slotsCache[cacheKey] = (const [], const {});
      debugPrint('slot ${availKey(day)} ${service.id}: ${lastSlotMs}ms queries=$lastSlotQueryCount slots=0 (niente fasce)');
      return const [];
    }
    final fasce = [for (final f in fl) (f.start, f.end)];
    final deviceFut = service.usesDevice
        ? _loadDeviceHoldsAround(_d0(day).add(const Duration(hours: 12)), service.deviceHoldHours + 12)
        : Future<List<DeviceHold>>.value(const []);
    final apptsFut = _appointmentsOrEmpty(day);
    final roomFut = _roomDayData(day);
    final busyFut = _busy(day);
    final appts = await apptsFut;
    final room = await roomFut;
    final blocks = _blocksOf(room);
    final eb = _empBlocksOf(room);
    final deviceHolds = await deviceFut;
    final busy = await busyFut;
    bool personOk(DateTime t) {
      final e = t.add(service.duration);
      return _genericCovers(fl, t, e) || _freePeople(fl, t, e, eb, appts, excludeId: excludeId).isNotEmpty;
    }
    final d = _d0(day);
    final now = DateTime.now();
    final keep = keepSlot == null ? null : DateTime(keepSlot.year, keepSlot.month, keepSlot.day, keepSlot.hour, keepSlot.minute);
    final out = <DateTime>{};
    for (final f in fasce) {
      for (var t = d.add(Duration(minutes: f.$1)); !t.add(service.duration).isAfter(d.add(Duration(minutes: f.$2))); t = t.add(slotStep)) {
        final isKeep = keep != null && t == keep;
        if ((t.isAfter(now) || isKeep) && _slotOk(service, t, t.add(service.duration), appts, blocks, busy, excludeId: excludeId, deviceHolds: deviceHolds) && (isKeep || personOk(t))) out.add(t);
      }
    }
    if (keep != null && _d0(keep) == d && !out.contains(keep)) {
      // in modifica lo slot attuale resta selezionabile anche se fuori disponibilità
      if (_slotOk(service, keep, keep.add(service.duration), appts, blocks, busy, excludeId: excludeId, deviceHolds: deviceHolds)) out.add(keep);
    }
    final slots = out.toList()..sort();
    final people = <DateTime, List<(String, String)>>{
      for (final t in slots) t: _freePeople(fl, t, t.add(service.duration), eb, appts, excludeId: excludeId),
    };
    _slotsCache[cacheKey] = (slots, people);
    lastSlotQueryCount = _slotQueries;
    lastSlotMs = sw.elapsedMilliseconds;
    debugPrint('slot ${availKey(day)} ${service.id}: ${lastSlotMs}ms queries=$lastSlotQueryCount slots=${slots.length}');
    return List<DateTime>.of(slots);
  }

  Future<String?> _customerUid() async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return null;
    try {
      final emp = await _db.doc('employees/${user.uid}').get();
      if (emp.exists) return null;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }
    return user.uid;
  }

  void _writeAssignment(Transaction tx, DocumentReference<Map<String, dynamic>> notification,
      String appointmentId, ServiceType service, DateTime start, String employeeId) {
    tx.set(notification, {
      'appointmentId': appointmentId, 'serviceName': service.name, 'customerName': '',
      'start': Timestamp.fromDate(start), 'createdAt': FieldValue.serverTimestamp(),
      'readBy': <String, dynamic>{}, 'type': 'assegnazione', 'targetEmployeeId': employeeId,
    });
  }

  Future<Appointment> book(ServiceType service, DateTime start, String name, String phone, {required String codiceFiscale, String? email, bool esenzione = false, String? ricettaNumero, String? ricettaNote, String? ricettaFotoB64, bool pagato = false, String? metodoPagamento, bool manualTime = false, String? employeeId, String? employeeNome}) async {
    await ensureClientAuth();
    final cf = normalizeCodiceFiscale(codiceFiscale);
    if (!isValidCodiceFiscale(cf)) throw StateError('Codice fiscale non valido');
    final end = start.add(service.duration);
    // Staff/admin: orario a mano ammesso solo nei giorni SENZA fasce di disponibilità.
    final manualOk = manualTime && (await availability(start)).isEmpty;
    if (!manualOk) {
      if (!service.availableOn(start.weekday)) throw StateError('Servizio non disponibile in questo giorno');
      await _checkAvailable(start, end, service);
    }
    final explicit = employeeId != null && employeeId.isNotEmpty;
    final (empId, empNome) = await _resolveEmployee(service, start, end,
        prefer: explicit ? employeeId : (service.dipendenteId.isNotEmpty ? service.dipendenteId : null),
        preferNome: explicit ? employeeNome : service.dipendenteNome, manual: manualOk, strict: explicit);
    final appts = await _appointmentsOrEmpty(start);
    final blocks = await _blocks(start);
    final busy = await _busy(start);
    final roomId = _pickRoom(service, start, end, appts, blocks, busy);
    if (roomId == null) throw StateError('Nessuna stanza libera in questo orario');
    await _ensureDeviceFree(service, start);
    final mail = (email == null || email.trim().isEmpty) ? null : email.trim().toLowerCase();
    final clienteUid = await _customerUid();
    final ref = _appts.doc();
    final metodo = (metodoPagamento == null || metodoPagamento.trim().isEmpty) ? null : metodoPagamento.trim().toLowerCase();
    final paid = pagato || metodo == 'carta' || metodo == 'bancomat';
    final devId = service.usesDevice ? service.deviceId : null;
    final devHours = service.usesDevice ? service.deviceHoldHours : null;
    var a = Appointment(id: ref.id, service: service, start: start, customerName: name, phone: phone, email: mail, codiceFiscale: cf,
        clienteUid: clienteUid, createdBy: _auth.currentUser?.uid, esenzione: esenzione, ricettaNumero: ricettaNumero, ricettaNote: ricettaNote, ricettaFoto: ricettaFotoB64 != null, pagato: paid, metodoPagamento: paid ? metodo : null, employeeId: empId, employeeNome: empNome, roomId: roomId, deviceId: devId, deviceHoldHours: devHours);
    final dayKey = _dayKey(start);
    final assignment = _db.collection('notifications').doc();
    final deviceDays = service.usesDevice ? daysOverlappingHold(start, service.deviceHoldEnd(start)) : const <DateTime>[];
    try {
    await _db.runTransaction((tx) async {
      final lock = _db.doc('roomDays/$dayKey');
      final lockSnap = await tx.get(lock);
      final deviceSnaps = service.usesDevice ? await _txDeviceDaySnaps(tx, deviceDays) : const <DocumentSnapshot<Map<String, dynamic>>>[];
      final existing = _blocksOf(lockSnap.data());
      if (empId != null && _personBusy(empId, start, end, _empBlocksOf(lockSnap.data()), const [])) {
        throw StateError('${empNome ?? 'La persona'} ha già una prenotazione in questo orario');
      }
      // Ricalcola stanza nella transazione (race): preferisci quella già scelta se ancora libera.
      int? chosen;
      final allowed = service.stanzeOrdinate;
      if (allowed.contains(roomId) && !existing.any((b) => b.$5 == roomId && _blocksRoomStatus(b.$4) && _hits(start, end, b.$2, b.$3))) {
        chosen = roomId;
      } else {
        for (final r in allowed) {
          if (!existing.any((b) => b.$5 == r && _blocksRoomStatus(b.$4) && _hits(start, end, b.$2, b.$3))) {
            chosen = r;
            break;
          }
        }
      }
      if (chosen == null) throw StateError('Nessuna stanza libera in questo orario');
      if (service.usesDevice) _assertDeviceFreeTx(service, start, _holdsFromSnaps(deviceSnaps));
      final nextBlocks = <String, dynamic>{};
      final current = lockSnap.data()?['blocks'];
      if (current is Map) current.forEach((key, value) => nextBlocks[key.toString()] = value);
      nextBlocks[ref.id] = _blockMap(start, end, AppointmentStatus.inAttesa.name, chosen, empId);
      a = Appointment(id: ref.id, service: service, start: start, customerName: name, phone: phone, email: mail, codiceFiscale: cf,
          clienteUid: clienteUid, createdBy: _auth.currentUser?.uid, esenzione: esenzione, ricettaNumero: ricettaNumero, ricettaNote: ricettaNote, ricettaFoto: ricettaFotoB64 != null, pagato: paid, metodoPagamento: paid ? metodo : null, employeeId: empId, employeeNome: empNome, roomId: chosen, deviceId: devId, deviceHoldHours: devHours);
      tx.set(lock, {'touched': FieldValue.serverTimestamp(), 'blocks': nextBlocks}, SetOptions(merge: true));
      if (service.usesDevice) {
        final holdEnd = service.deviceHoldEnd(start);
        for (final snap in deviceSnaps) {
          _putHold(tx, snap, ref.id, service.deviceId, start, holdEnd, AppointmentStatus.inAttesa.name);
        }
      }
      tx.set(ref, a.toMap());
      if ((empId ?? '').isNotEmpty) _writeAssignment(tx, assignment, ref.id, service, start, empId!);
      // Notifica staff/admin: stesso id dell'appuntamento, scritta nella stessa transazione.
      tx.set(_db.doc('notifications/${ref.id}'), {
        'appointmentId': ref.id,
        'serviceName': service.name,
        'customerName': name,
        'start': Timestamp.fromDate(start),
        'createdAt': FieldValue.serverTimestamp(),
        'readBy': <String, dynamic>{},
      });
      if (esenzione && ricettaFotoB64 != null) {
        tx.set(_db.doc('ricette/${ref.id}'), {'foto': ricettaFotoB64, 'createdBy': _auth.currentUser?.uid, 'createdAt': FieldValue.serverTimestamp()});
      }
    });
    } on _DeviceBusyInTx {
      throw await _deviceUnavailable(service, start);
    }
    if (clienteUid != null) {
      try {
        await _db.doc('customers/$clienteUid').set({
          'email': mail ?? (_auth.currentUser?.email ?? ''),
          'nome': name,
          'telefono': phone,
          'codiceFiscale': cf,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
    // Ricontrollo post-scrittura: conflitto solo sulla stessa stanza.
    final clash = (await _blocks(start)).where((b) => b.$1 != a.id && b.$5 == a.roomId && _blocksRoomStatus(b.$4) && _hits(start, end, b.$2, b.$3));
    if (clash.isNotEmpty) {
      await ref.update({'status': AppointmentStatus.annullato.name});
      await _setBlockStatus(a, AppointmentStatus.annullato.name);
      await _setDeviceHoldStatus(a, AppointmentStatus.annullato.name);
      throw StateError('Slot appena occupato da un\'altra prenotazione, scegline un altro');
    }
    if (service.usesDevice) {
      final fresh = await _loadDeviceHoldsAround(start, service.deviceHoldHours);
      if (!_deviceFree(service, start, fresh, excludeId: a.id)) {
        await ref.update({'status': AppointmentStatus.annullato.name});
        await _setBlockStatus(a, AppointmentStatus.annullato.name);
        await _setDeviceHoldStatus(a, AppointmentStatus.annullato.name);
        throw await _deviceUnavailable(service, start, excludeId: a.id);
      }
    }
    unawaited(_syncCalendar(a.id));
    if ((a.employeeId ?? '').isNotEmpty) unawaited(_notifyAssignment(a.id));
    notifyListeners();
    return a;
  }

  /// Endpoint autenticato: destinatario e contenuto risolti SOLO dal database.
  /// Best effort, mai bloccare o annullare una prenotazione per un errore mail.
  Future<void> _notifyAssignment(String appointmentId) async {
    try {
      final token = await _auth.currentUser?.getIdToken();
      if (token == null) return;
      final response = await http.post(Uri.base.resolve('/api/send-assignment'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'appointmentId': appointmentId})).timeout(const Duration(seconds: 20));
      if (response.statusCode >= 400) debugPrint('Notifica assegnazione: HTTP ${response.statusCode}');
    } catch (e) { debugPrint('Notifica assegnazione non disponibile: ${e.runtimeType}'); }
  }

  /// Best effort: non blocca la prenotazione se Google Calendar non è (ancora) collegato.
  Future<void> _syncCalendar(String appointmentId) async {
    try {
      final token = await _auth.currentUser?.getIdToken();
      if (token == null) return;
      final response = await http.post(Uri.base.resolve('/api/gcal-sync'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'appointmentId': appointmentId})).timeout(const Duration(seconds: 20));
      if (response.statusCode >= 400) debugPrint('Google Calendar sync: HTTP ${response.statusCode}');
    } catch (e) { debugPrint('Google Calendar sync non disponibile: ${e.runtimeType}'); }
  }

  Future<void> confirm(Appointment a) async {
    final upd = <String, dynamic>{'status': AppointmentStatus.confermato.name, 'updatedBy': _auth.currentUser?.uid};
    await _appts.doc(a.id).update(upd);
    await _setBlockStatus(a, AppointmentStatus.confermato.name);
    unawaited(_syncCalendar(a.id));
  }

  Future<bool> _isActiveStaff() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final emp = await _db.doc('employees/$uid').get();
    return emp.exists && (emp.data()?['attivo'] ?? true) == true;
  }

  /// Annulla prenotazione.
  /// Cliente: solo se restano ≥ 24 ore all'inizio; se pagata marca rimborso pending.
  /// Staff/admin: sempre; se pagata marca rimborso pending.
  /// [asStaff] forza il percorso staff (UI staff). Se null, rileva da `employees/{uid}`.
  Future<void> cancel(Appointment a, {bool? asStaff}) async {
    if (a.status == AppointmentStatus.annullato) return;
    final staff = asStaff ?? await _isActiveStaff();
    if (!staff && !a.clientMayCancel()) {
      throw StateError('Non è possibile annullare la prenotazione a meno di 24 ore dall\'inizio. Contatta la farmacia.');
    }
    final uid = _auth.currentUser?.uid;
    final needsRefund = a.pagato;
    final upd = <String, dynamic>{
      'status': AppointmentStatus.annullato.name,
      'updatedBy': uid,
      'annullatoDa': staff ? 'staff' : 'cliente',
      'annullatoAt': FieldValue.serverTimestamp(),
    };
    if (needsRefund) {
      upd['rimborsoRichiesto'] = true;
      upd['rimborsoStato'] = 'pending';
      upd['rimborsoAt'] = FieldValue.serverTimestamp();
      upd['clienteChiamato'] = false;
    }
    await _appts.doc(a.id).update(upd);
    await _setBlockStatus(a, AppointmentStatus.annullato.name);
    await _setDeviceHoldStatus(a, AppointmentStatus.annullato.name);
    unawaited(_syncCalendar(a.id));
    if (needsRefund) {
      try {
        await _db.doc('notifications/rimborso_${a.id}').set({
          'appointmentId': a.id,
          'serviceName': a.service.name,
          'customerName': a.customerName,
          'start': Timestamp.fromDate(a.start),
          'createdAt': FieldValue.serverTimestamp(),
          'readBy': <String, dynamic>{},
          'kind': 'rimborso',
          'phone': a.phone,
          if (a.service.prezzoFinale != null) 'importo': a.service.prezzoFinale,
          if (a.metodoPagamento != null) 'metodoPagamento': a.metodoPagamento,
        });
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Riprogramma (stesso servizio e dati cliente): sposta start/end, aggiorna blocco stanza.
  /// Cliente: solo se restano ≥ 24h all'inizio attuale. Staff: sempre. Nessun rimborso.
  Future<Appointment> reschedule(Appointment a, DateTime start, {bool? asStaff}) async {
    if (!a.blocksRoom) throw StateError('Prenotazione non attiva');
    final staff = asStaff ?? await _isActiveStaff();
    if (!staff && !a.clientMayCancel()) {
      throw StateError('Non è possibile riprogrammare la prenotazione a meno di 24 ore dall\'inizio. Contatta la farmacia.');
    }
    if (!staff && start.isBefore(DateTime.now())) throw StateError('Orario già passato');
    final service = a.service;
    final end = start.add(a.end.difference(a.start));
    if (start == a.start) return a;
    await _checkAvailable(start, end, service);
    await _ensureDeviceFree(service, start, excludeId: a.id);
    final (empId, empNome) = await _resolveEmployee(service, start, end, prefer: a.employeeId, preferNome: a.employeeNome, excludeId: a.id);
    final oldDay = _dayKey(a.start);
    final newDay = _dayKey(start);
    final dayChanged = oldDay != newDay;
    int roomId = a.roomId;
    final assignment = _db.collection('notifications').doc();
    final oldDeviceDays = a.usesDevice ? daysOverlappingHold(a.start, a.deviceHoldEnd) : const <DateTime>[];
    final newDeviceDays = service.usesDevice ? daysOverlappingHold(start, service.deviceHoldEnd(start)) : const <DateTime>[];
    try {
    await _db.runTransaction((tx) async {
      final newLock = _db.doc('roomDays/$newDay');
      final oldLock = _db.doc('roomDays/$oldDay');
      final newSnap = await tx.get(newLock);
      final oldSnap = dayChanged ? await tx.get(oldLock) : null;
      final deviceSnaps = (a.usesDevice || service.usesDevice)
          ? await _txDeviceDaySnaps(tx, [...oldDeviceDays, ...newDeviceDays])
          : const <DocumentSnapshot<Map<String, dynamic>>>[];
      final existing = _blocksOf(newSnap.data()).where((b) => b.$1 != a.id).toList();
      if (empId != null && _personBusy(empId, start, end, _empBlocksOf(newSnap.data()), const [], excludeId: a.id)) {
        throw StateError('${empNome ?? 'La persona'} ha già una prenotazione in questo orario');
      }
      final allowed = [a.roomId, ...service.stanzeOrdinate.where((r) => r != a.roomId)];
      int? chosen;
      for (final r in allowed) {
        if (!existing.any((b) => b.$5 == r && _blocksRoomStatus(b.$4) && _hits(start, end, b.$2, b.$3))) { chosen = r; break; }
      }
      if (chosen == null) throw StateError('Nessuna stanza libera in questo orario');
      if (service.usesDevice) _assertDeviceFreeTx(service, start, _holdsFromSnaps(deviceSnaps), excludeId: a.id);
      roomId = chosen;
      final nextNew = <String, dynamic>{};
      final curNew = newSnap.data()?['blocks'];
      if (curNew is Map) curNew.forEach((k, v) => nextNew[k.toString()] = v);
      nextNew[a.id] = _blockMap(start, end, a.status.name, roomId, empId);
      tx.set(newLock, {'touched': FieldValue.serverTimestamp(), 'blocks': nextNew}, SetOptions(merge: true));
      if (dayChanged) {
        final nextOld = <String, dynamic>{};
        final curOld = oldSnap?.data()?['blocks'];
        if (curOld is Map) curOld.forEach((k, v) => nextOld[k.toString()] = v);
        nextOld.remove(a.id);
        tx.set(oldLock, {'touched': FieldValue.serverTimestamp(), 'blocks': nextOld}, SetOptions(merge: true));
      }
      if (a.usesDevice || service.usesDevice) {
        final oldKeys = {for (final d in oldDeviceDays) _dayKey(d)};
        final newKeys = {for (final d in newDeviceDays) _dayKey(d)};
        final holdEnd = service.deviceHoldEnd(start);
        for (final snap in deviceSnaps) {
          if (service.usesDevice && newKeys.contains(snap.id)) {
            _putHold(tx, snap, a.id, service.deviceId, start, holdEnd, a.status.name);
          } else if (oldKeys.contains(snap.id)) {
            _dropHold(tx, snap, a.id);
          }
        }
      }
      if (empId != a.employeeId && (empId ?? '').isNotEmpty) _writeAssignment(tx, assignment, a.id, service, start, empId!);
      tx.update(_appts.doc(a.id), {
        'start': Timestamp.fromDate(start),
        'end': Timestamp.fromDate(end),
        'roomId': roomId,
        'roomName': Room.registry[roomId]?.nome,
        'employeeId': empId,
        'employeeNome': empNome,
        if (service.usesDevice) 'deviceId': service.deviceId,
        if (service.usesDevice) 'deviceHoldHours': service.deviceHoldHours,
        'updatedBy': _auth.currentUser?.uid,
        'riprogrammatoDa': staff ? 'staff' : 'cliente',
        'riprogrammatoAt': FieldValue.serverTimestamp(),
      });
    });
    } on _DeviceBusyInTx {
      throw await _deviceUnavailable(service, start, excludeId: a.id);
    }
    if (staff) {
      try {
        final n = await _db.doc('notifications/${a.id}').get();
        if (n.exists) await n.reference.update({'start': Timestamp.fromDate(start)});
      } catch (_) {}
    }
    if (empId != a.employeeId) unawaited(_notifyAssignment(a.id));
    unawaited(_syncCalendar(a.id));
    notifyListeners();
    return a;
  }

  /// Staff: cerca clienti per prefisso email (customers + prenotazioni recenti), dedup per email.
  Future<List<CustomerProfile>> searchCustomersByEmail(String q) async {
    final p = q.trim().toLowerCase();
    if (p.length < 2) return const [];
    final end = '$p\uf8ff';
    final out = <String, CustomerProfile>{};
    try {
      final cs = await _db.collection('customers').where('email', isGreaterThanOrEqualTo: p).where('email', isLessThan: end).limit(8).get();
      for (final d in cs.docs) {
        final c = CustomerProfile.fromDoc(d);
        if (c.email.isNotEmpty) out[c.email.toLowerCase()] = c;
      }
    } catch (_) {}
    if (out.length < 8) {
      try {
        final as = await _appts.where('clienteEmail', isGreaterThanOrEqualTo: p).where('clienteEmail', isLessThan: end).limit(20).get();
        for (final d in as.docs) {
          final m = d.data();
          final e = ((m['clienteEmail'] ?? '') as String).toLowerCase();
          if (e.isEmpty || out.containsKey(e)) continue;
          out[e] = CustomerProfile(id: '', email: e, nome: (m['clienteNome'] ?? '') as String, telefono: (m['clienteTel'] ?? '') as String, codiceFiscale: (m['clienteCodiceFiscale'] ?? '') as String);
        }
      } catch (_) {}
    }
    return out.values.take(8).toList();
  }

  /// Staff: rimborso effettuato al POS / cassa.
  Future<void> markRimborsato(Appointment a, {bool chiamatoCliente = false}) async {
    await _appts.doc(a.id).update({
      'rimborsoStato': 'done',
      'rimborsoRichiesto': true,
      'rimborsoAt': FieldValue.serverTimestamp(),
      'clienteChiamato': chiamatoCliente || a.clienteChiamato,
      'updatedBy': _auth.currentUser?.uid,
    });
    try {
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        await _db.doc('notifications/rimborso_${a.id}').update({'readBy.$uid': true});
      }
    } catch (_) {}
    notifyListeners();
  }

  Stream<List<Appointment>> watchPendingRefunds() => _appts
      .where('rimborsoStato', isEqualTo: 'pending')
      .limit(80)
      .snapshots()
      .map((q) {
        final list = q.docs.map(Appointment.fromDoc).toList();
        list.sort((a, b) => (b.rimborsoAt ?? b.annullatoAt ?? b.start).compareTo(a.rimborsoAt ?? a.annullatoAt ?? a.start));
        return list;
      });

  Future<void> setPagato(Appointment a, bool v, {String? metodoPagamento}) {
    final upd = <String, dynamic>{'pagato': v, 'updatedBy': _auth.currentUser?.uid};
    if (!v) {
      upd['metodoPagamento'] = null;
    } else if (metodoPagamento != null && metodoPagamento.isNotEmpty) {
      upd['metodoPagamento'] = metodoPagamento;
    }
    return _appts.doc(a.id).update(upd);
  }

  /// Modifica completa staff/admin: anagrafica, servizio, data/ora, esenzione, pagamento.
  /// Codice prenotazione e notifiche restano; ricalcola UNA stanza libera tra quelle ammesse.
  /// Un collegamento esplicito ha priorità; nessun abbinamento ambiguo per sola email.
  Future<DocumentReference<Map<String, dynamic>>?> _linkedCustomer(Appointment a) async {
    if ((a.clienteUid ?? '').isNotEmpty) return _db.doc('customers/${a.clienteUid}');
    if ((a.email ?? '').trim().isEmpty) return null;
    final matches = await _db.collection('customers').where('email', isEqualTo: a.email!.trim().toLowerCase()).limit(2).get();
    return matches.docs.length == 1 ? matches.docs.single.reference : null;
  }

  Map<String, dynamic> _customerCorrections(Appointment a, String name, String phone, String? email) => {
    if (name.trim() != a.customerName.trim()) 'nome': name.trim(),
    if (phone.trim() != a.phone.trim()) 'telefono': phone.trim(),
    if ((email ?? '').trim().toLowerCase() != (a.email ?? '').trim().toLowerCase()) 'email': (email ?? '').trim().toLowerCase(),
  };

  /// Correzione al banco senza toccare slot, stato, stanza o pagamento.
  Future<void> updateCustomerDetails(Appointment a, {required String name, required String phone, String? email}) async {
    final nome = name.trim();
    final tel = phone.trim();
    final mail = (email ?? '').trim().toLowerCase();
    if (nome.isEmpty || nome.length >= 100) throw StateError('Nome non valido');
    if (tel.length < 6 || tel.length >= 30) throw StateError('Telefono non valido');
    if (mail.length >= 120 || (mail.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail))) throw StateError('Email non valida');
    final customer = await _linkedCustomer(a);
    final changes = _customerCorrections(a, nome, tel, mail);
    await _db.runTransaction((tx) async {
      final customerDoc = customer == null ? null : await tx.get(customer);
      tx.update(_appts.doc(a.id), {
        'clienteNome': nome, 'clienteTel': tel, 'clienteEmail': mail.isEmpty ? null : mail,
        if ((a.clienteUid ?? '').isEmpty && customerDoc?.exists == true) 'clienteUid': customer!.id,
        'updatedBy': _auth.currentUser?.uid, 'updatedAt': FieldValue.serverTimestamp(),
      });
      if (customerDoc?.exists == true && changes.isNotEmpty) {
        tx.update(customer!, {...changes, 'updatedAt': FieldValue.serverTimestamp()});
      }
    });
    notifyListeners();
  }

  Future<Appointment> updateBooking(
    Appointment a, {
    required String name,
    required String phone,
    required String codiceFiscale,
    String? email,
    required ServiceType service,
    required DateTime start,
    bool esenzione = false,
    String? ricettaNumero,
    String? ricettaNote,
    bool? pagato,
    String? metodoPagamento,
    /// Persona assegnata: null = mantieni / ricalcola se cambia l'orario; '' = nessuna.
    String? employeeId,
    String? employeeNome,
  }) async {
    final cf = normalizeCodiceFiscale(codiceFiscale);
    if (!isValidCodiceFiscale(cf)) throw StateError('Codice fiscale non valido');
    final tel = phone.trim();
    if (tel.length < 6 || tel.length >= 30) throw StateError('Telefono non valido');
    final nome = name.trim();
    if (nome.isEmpty || nome.length >= 100) throw StateError('Nome non valido');
    final end = start.add(service.duration);
    final mail = (email == null || email.trim().isEmpty) ? null : email.trim().toLowerCase();
    final paid = pagato ?? a.pagato;
    final metodoRaw = metodoPagamento ?? a.metodoPagamento;
    final metodo = (!paid) ? null : ((metodoRaw == null || metodoRaw.trim().isEmpty) ? null : metodoRaw.trim().toLowerCase());
    if (esenzione && (ricettaNumero == null || ricettaNumero.trim().isEmpty)) {
      throw StateError('Con esenzione serve il numero ricetta');
    }

    if (mail != null && (mail.length >= 120 || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail))) throw StateError('Email non valida');
    final scheduleChanged = a.start != start || a.end != end || a.service.id != service.id;
    if (scheduleChanged && !service.availableOn(start.weekday)) throw StateError('Servizio non disponibile in questo giorno');
    var roomId = a.roomId;
    if (scheduleChanged) await _checkAvailable(start, end, service);
    var empId = a.employeeId;
    var empNome = a.employeeNome;
    if (employeeId != null && employeeId.isEmpty) {
      empId = null; empNome = null;
    } else if (a.blocksRoom && (scheduleChanged || (employeeId != null && employeeId != a.employeeId))) {
      final explicit = employeeId != null;
      (empId, empNome) = await _resolveEmployee(service, start, end,
          prefer: explicit ? employeeId : (service.dipendenteId.isNotEmpty ? service.dipendenteId : a.employeeId),
          preferNome: explicit ? employeeNome : (service.dipendenteId.isNotEmpty ? service.dipendenteNome : a.employeeNome),
          excludeId: a.id, strict: explicit);
    }
    final personChanged = empId != a.employeeId;
    final assignment = _db.collection('notifications').doc();
    if (scheduleChanged && a.blocksRoom) {
      final appts = await _appointmentsOrEmpty(start);
      final blocks = await _blocks(start);
      final picked = _pickRoom(service, start, end, appts, blocks, await _busy(start), excludeId: a.id, prefer: a.roomId);
      if (picked == null) throw StateError('Nessuna stanza libera in questo orario');
      roomId = picked;
    } else if (!service.stanzeOrdinate.contains(roomId)) {
      // Servizio cambiato ma orario uguale e non blocksRoom: allinea a una stanza ammessa.
      roomId = service.stanzeOrdinate.first;
    }

    final oldDay = _dayKey(a.start);
    final newDay = _dayKey(start);
    final dayChanged = oldDay != newDay;
    final cancelled = a.status == AppointmentStatus.annullato;
    final newUsesDevice = service.usesDevice && !cancelled;
    final oldDeviceDays = a.usesDevice ? daysOverlappingHold(a.start, a.deviceHoldEnd) : const <DateTime>[];
    final newDeviceDays = newUsesDevice ? daysOverlappingHold(start, service.deviceHoldEnd(start)) : const <DateTime>[];
    final deviceHoldChanged = !cancelled && (scheduleChanged
        || a.effectiveDeviceId != (service.usesDevice ? service.deviceId : '')
        || a.effectiveHoldHours != (service.usesDevice ? service.deviceHoldHours : 0));
    if (newUsesDevice && deviceHoldChanged) {
      await _ensureDeviceFree(service, start, excludeId: a.id);
    }

    final customer = await _linkedCustomer(a);
    final corrections = _customerCorrections(a, nome, tel, mail);
    try {
    await _db.runTransaction((tx) async {
      final customerDoc = customer == null ? null : await tx.get(customer);
      final notification = await tx.get(_db.doc('notifications/${a.id}'));
      DocumentSnapshot<Map<String, dynamic>>? newSnap;
      DocumentSnapshot<Map<String, dynamic>>? oldSnap;
      final newLock = _db.doc('roomDays/$newDay');
      final oldLock = _db.doc('roomDays/$oldDay');
      // Tutte le letture prima delle scritture (regola Firestore).
      if ((scheduleChanged || personChanged) && a.blocksRoom) {
        newSnap = await tx.get(newLock);
        if (dayChanged) oldSnap = await tx.get(oldLock);
      }
      final deviceSnaps = deviceHoldChanged
          ? await _txDeviceDaySnaps(tx, [...oldDeviceDays, ...newDeviceDays])
          : const <DocumentSnapshot<Map<String, dynamic>>>[];
      if (newUsesDevice && deviceHoldChanged) {
        _assertDeviceFreeTx(service, start, _holdsFromSnaps(deviceSnaps), excludeId: a.id);
      }

      if (empId != null && a.blocksRoom && _personBusy(empId, start, end, _empBlocksOf(newSnap?.data()), const [], excludeId: a.id)) {
        throw StateError('${empNome ?? 'La persona'} ha già una prenotazione in questo orario');
      }
      if (personChanged && !scheduleChanged && a.blocksRoom) {
        final next = <String, dynamic>{};
        final cur = newSnap!.data()?['blocks'];
        if (cur is Map) cur.forEach((k, v) => next[k.toString()] = v);
        next[a.id] = _blockMap(start, end, a.status.name, roomId, empId);
        tx.set(newLock, {'touched': FieldValue.serverTimestamp(), 'blocks': next}, SetOptions(merge: true));
      }
      if (scheduleChanged && a.blocksRoom) {
        final existing = _blocksOf(newSnap!.data()).where((b) => b.$1 != a.id).toList();
        final allowed = service.stanzeOrdinate;
        int? chosen;
        if (allowed.contains(roomId) && !existing.any((b) => b.$5 == roomId && _blocksRoomStatus(b.$4) && _hits(start, end, b.$2, b.$3))) {
          chosen = roomId;
        } else {
          for (final r in allowed) {
            if (!existing.any((b) => b.$5 == r && _blocksRoomStatus(b.$4) && _hits(start, end, b.$2, b.$3))) {
              chosen = r;
              break;
            }
          }
        }
        if (chosen == null) throw StateError('Nessuna stanza libera in questo orario');
        roomId = chosen;
        final nextNew = <String, dynamic>{};
        final curNew = newSnap.data()?['blocks'];
        if (curNew is Map) curNew.forEach((k, v) => nextNew[k.toString()] = v);
        nextNew[a.id] = _blockMap(start, end, a.status.name, roomId, empId);
        tx.set(newLock, {'touched': FieldValue.serverTimestamp(), 'blocks': nextNew}, SetOptions(merge: true));
        if (dayChanged) {
          final nextOld = <String, dynamic>{};
          final curOld = oldSnap?.data()?['blocks'];
          if (curOld is Map) curOld.forEach((k, v) => nextOld[k.toString()] = v);
          nextOld.remove(a.id);
          tx.set(oldLock, {'touched': FieldValue.serverTimestamp(), 'blocks': nextOld}, SetOptions(merge: true));
        }
      }

      final upd = <String, dynamic>{
        if ((a.clienteUid ?? '').isEmpty && customerDoc?.exists == true) 'clienteUid': customer!.id,
        'clienteNome': nome,
        'clienteTel': tel,
        'clienteCodiceFiscale': cf,
        'clienteEmail': mail,
        'servizio': service.id,
        'servizioNome': service.name,
        'durataMin': service.duration.inMinutes,
        'prezzo': service.prezzoFinale,
        'start': Timestamp.fromDate(start),
        'end': Timestamp.fromDate(end),
        'esenzione': esenzione,
        'pagato': paid,
        'metodoPagamento': paid ? metodo : null,
        'employeeId': empId,
        'employeeNome': empNome,
        'roomId': roomId,
        'roomName': Room.registry[roomId]?.nome,
        'deviceId': newUsesDevice ? service.deviceId : null,
        'deviceHoldHours': newUsesDevice ? service.deviceHoldHours : null,
        'updatedBy': _auth.currentUser?.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (esenzione) {
        upd['ricettaNumero'] = ricettaNumero!.trim();
        upd['ricettaNote'] = (ricettaNote == null || ricettaNote.trim().isEmpty) ? null : ricettaNote.trim();
      } else {
        upd['ricettaNumero'] = null;
        upd['ricettaNote'] = null;
      }
      if (deviceHoldChanged) {
        final oldKeys = {for (final d in oldDeviceDays) _dayKey(d)};
        final newKeys = {for (final d in newDeviceDays) _dayKey(d)};
        final holdEnd = service.deviceHoldEnd(start);
        for (final snap in deviceSnaps) {
          if (newUsesDevice && newKeys.contains(snap.id)) {
            _putHold(tx, snap, a.id, service.deviceId, start, holdEnd, a.status.name);
          } else if (oldKeys.contains(snap.id)) {
            _dropHold(tx, snap, a.id);
          }
        }
      }
      tx.update(_appts.doc(a.id), upd);
      if (personChanged && (empId ?? '').isNotEmpty) _writeAssignment(tx, assignment, a.id, service, start, empId!);

      if (customerDoc?.exists == true && corrections.isNotEmpty) {
        tx.update(customer!, {...corrections, 'updatedAt': FieldValue.serverTimestamp()});
      }

      // Aggiorna solo una notifica già presente: non creare documenti incompleti.
      if (notification.exists) {
        tx.update(notification.reference, {
        'appointmentId': a.id,
        'serviceName': service.name,
        'customerName': nome,
        'start': Timestamp.fromDate(start),
        });
      }
    });
    } on _DeviceBusyInTx {
      throw await _deviceUnavailable(service, start, excludeId: a.id);
    }

    var calendarEventId = a.calendarEventId;
    if (scheduleChanged || personChanged) unawaited(_syncCalendar(a.id));
    if (personChanged) unawaited(_notifyAssignment(a.id));

    notifyListeners();
    return Appointment(
      id: a.id,
      service: service,
      start: start,
      end: end,
      customerName: nome,
      phone: tel,
      email: mail,
      status: a.status,
      createdBy: a.createdBy,
      calendarEventId: calendarEventId,
      employeeId: empId,
      employeeNome: empNome,
      esenzione: esenzione,
      ricettaNumero: esenzione ? ricettaNumero?.trim() : null,
      ricettaNote: esenzione && (ricettaNote ?? '').trim().isNotEmpty ? ricettaNote!.trim() : null,
      ricettaFoto: a.ricettaFoto,
      pagato: paid,
      metodoPagamento: paid ? metodo : null,
      clienteUid: a.clienteUid,
      clienteAccount: a.clienteAccount,
      codiceFiscale: cf,
      roomId: roomId,
      deviceId: newUsesDevice ? service.deviceId : null,
      deviceHoldHours: newUsesDevice ? service.deviceHoldHours : null,
    );
  }

  Future<void> freeRoom(Appointment a) async {
    await _appts.doc(a.id).update({'status': AppointmentStatus.completato.name, 'updatedBy': _auth.currentUser?.uid});
    await _setBlockStatus(a, AppointmentStatus.completato.name);
  }

  /// Passata la fine dello slot: inAttesa/confermato → completato (effettuata).
  /// Solo scrittura; non tocca annullate e non crea rimborsi. Staff/employee required by rules.
  Future<void> markExpiredCompleted(Iterable<Appointment> list, [DateTime? now]) async {
    final n = now ?? DateTime.now();
    for (final a in list) {
      if (a.status == AppointmentStatus.annullato || a.status == AppointmentStatus.completato) continue;
      if (!a.blocksRoom || !a.isEnded(n)) continue;
      if (!_markingExpired.add(a.id)) continue;
      try {
        await freeRoom(a);
      } catch (_) {
        // Cliente o rete: UI usa comunque effectiveStatus.
      } finally {
        _markingExpired.remove(a.id);
      }
    }
  }

  /// Prenotazioni del cliente loggato (uid e, per lo storico senza uid, la stessa email).
  Stream<List<Appointment>> watchMine() {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return Stream<List<Appointment>>.value(const []);
    final uid = user.uid;
    final authEmail = user.email;
    final controller = StreamController<List<Appointment>>.broadcast();
    var uidHits = <Appointment>[];
    var mailHits = <Appointment>[];
    void emit() {
      final merged = filterCustomerBookings<Appointment>(
        [...uidHits, ...mailHits],
        uid: uid,
        authEmail: authEmail,
        clienteUid: (a) => a.clienteUid,
        email: (a) => a.email,
        start: (a) => a.start,
        id: (a) => a.id,
      );
      // Tentativo best-effort (rules: solo employee); UI usa effectiveStatus comunque.
      unawaited(markExpiredCompleted(merged));
      if (!controller.isClosed) controller.add(merged);
    }
    final sub1 = _appts.where('clienteUid', isEqualTo: uid).snapshots().listen(
      (q) { uidHits = q.docs.map(Appointment.fromDoc).toList(); emit(); },
      onError: controller.addError,
    );
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub2;
    final mail = authEmail?.trim().toLowerCase() ?? '';
    if (mail.isNotEmpty) {
      sub2 = _appts.where('clienteEmail', isEqualTo: mail).snapshots().listen(
        (q) { mailHits = q.docs.map(Appointment.fromDoc).toList(); emit(); },
        onError: controller.addError,
      );
    }
    controller.onCancel = () async {
      await sub1.cancel();
      await sub2?.cancel();
    };
    return controller.stream;
  }

  /// Foto ricetta (JPEG base64) salvata in `ricette/{appointmentId}`; solo staff.
  Future<String?> ricettaFoto(String id) async => (await _db.doc('ricette/$id').get()).data()?['foto'] as String?;

  /// Servizio attivo per id (per eventi prenotabili).
  Future<ServiceType?> activeServiceById(String id) async {
    await ensureClientAuth();
    final d = await servicesRef.doc(id).get();
    if (!d.exists) return null;
    final s = ServiceType.fromDoc(d);
    ServiceType.registry[s.id] = s;
    return s.attivo ? s : null;
  }

  // ---- Notifiche staff (collection `notifications`) ----
  Stream<List<StaffNotification>> watchNotifications() => _db.collection('notifications')
      .orderBy('createdAt', descending: true).limit(100).snapshots()
      .map((q) => q.docs.map(StaffNotification.fromDoc).where((n) => n.targetEmployeeId == null || n.targetEmployeeId == _auth.currentUser?.uid).toList());

  Future<void> markNotificationRead(String id) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.doc('notifications/$id').update({'readBy.$uid': true});
  }
}

class StaffNotification {
  final String id, appointmentId, serviceName, customerName;
  final DateTime? start, createdAt;
  final Map<String, dynamic> readBy;
  /// `prenotazione` (default) | `rimborso`.
  final String kind;
  final String? targetEmployeeId;
  final String? phone;
  final double? importo;
  final String? metodoPagamento;
  StaffNotification(this.id, this.appointmentId, this.serviceName, this.customerName, this.start, this.createdAt, this.readBy,
      {this.kind = 'prenotazione', this.targetEmployeeId, this.phone, this.importo, this.metodoPagamento});
  bool readByUid(String? uid) => uid != null && readBy[uid] == true;
  bool get isAssegnazione => kind == 'assegnazione';
  bool get isRimborso => kind == 'rimborso';
  factory StaffNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    DateTime? t(dynamic v) => v is Timestamp ? v.toDate() : null;
    final imp = m['importo'];
    return StaffNotification(
      d.id,
      (m['appointmentId'] ?? d.id) as String,
      (m['serviceName'] ?? '') as String,
      (m['customerName'] ?? '') as String,
      t(m['start']),
      t(m['createdAt']),
      Map<String, dynamic>.from((m['readBy'] as Map?) ?? {}),
      kind: (m['type'] as String?) ?? (m['kind'] as String?) ?? 'prenotazione',
      targetEmployeeId: m['targetEmployeeId'] as String?,
      phone: m['phone'] as String?,
      importo: imp is num ? imp.toDouble() : null,
      metodoPagamento: m['metodoPagamento'] as String?,
    );
  }
}
