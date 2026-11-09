import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Occupazione di un apparecchio: intervallo semiaperto [start, holdEnd).
class DeviceHold {
  final String appointmentId;
  final String deviceId;
  final DateTime start;
  final DateTime holdEnd;
  final String status;
  const DeviceHold({
    required this.appointmentId,
    required this.deviceId,
    required this.start,
    required this.holdEnd,
    this.status = 'inAttesa',
  });

  bool get active => status != 'annullato';
}

/// Giorni di calendario la cui mezzanotte..+1 sovrappone [start, holdEnd) (semiaperto).
List<DateTime> daysOverlappingHold(DateTime start, DateTime holdEnd) {
  if (!start.isBefore(holdEnd)) return const [];
  final out = <DateTime>[];
  var d = DateTime(start.year, start.month, start.day);
  final lastMidnight = DateTime(holdEnd.year, holdEnd.month, holdEnd.day);
  final last = holdEnd == lastMidnight ? lastMidnight.subtract(const Duration(days: 1)) : lastMidnight;
  while (!d.isAfter(last)) {
    out.add(d);
    d = d.add(const Duration(days: 1));
  }
  return out;
}

bool deviceIntervalsOverlap(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) =>
    aStart.isBefore(bEnd) && bStart.isBefore(aEnd);

/// Conteggio distinti per appointmentId (lo stesso hold è ripetuto su più giorni).
int countOverlappingDeviceHolds({
  required String deviceId,
  required DateTime windowStart,
  required DateTime windowEnd,
  required Iterable<DeviceHold> holds,
  String? excludeId,
}) {
  if (deviceId.isEmpty || !windowStart.isBefore(windowEnd)) return 0;
  final ids = <String>{};
  for (final h in holds) {
    if (h.deviceId != deviceId || !h.active) continue;
    if (excludeId != null && h.appointmentId == excludeId) continue;
    if (deviceIntervalsOverlap(h.start, h.holdEnd, windowStart, windowEnd)) {
      ids.add(h.appointmentId);
    }
  }
  return ids.length;
}

bool isDeviceQuantityFree({required int quantity, required int overlapping}) =>
    overlapping < (quantity < 1 ? 1 : quantity);

/// Primo inizio >= [requested] in cui il conteggio di hold sovrapposti a [T, T+holdHours) è sotto [quantity].
/// A ogni conflitto salta a `holdEnd` (es. Holter il 9/11 alle 16 → primo libero 10/11 alle 16:00).
DateTime? nextFreeDeviceStart({
  required String deviceId,
  required int holdHours,
  required int quantity,
  required DateTime requested,
  required Iterable<DeviceHold> holds,
  String? excludeId,
  DateTime? searchUntil,
  int maxIter = 200,
}) {
  if (deviceId.isEmpty || holdHours <= 0) return requested;
  var t = requested;
  final limit = searchUntil ?? requested.add(const Duration(days: 90));
  for (var i = 0; i < maxIter; i++) {
    if (t.isAfter(limit)) return null;
    final windowEnd = t.add(Duration(hours: holdHours));
    final n = countOverlappingDeviceHolds(
      deviceId: deviceId,
      windowStart: t,
      windowEnd: windowEnd,
      holds: holds,
      excludeId: excludeId,
    );
    if (isDeviceQuantityFree(quantity: quantity, overlapping: n)) return t;
    DateTime? jump;
    for (final h in holds) {
      if (h.deviceId != deviceId || !h.active) continue;
      if (excludeId != null && h.appointmentId == excludeId) continue;
      if (!deviceIntervalsOverlap(h.start, h.holdEnd, t, windowEnd)) continue;
      if (h.holdEnd.isAfter(t) && (jump == null || h.holdEnd.isBefore(jump))) jump = h.holdEnd;
    }
    if (jump == null) return null;
    t = jump;
  }
  return null;
}

String formatDeviceNextFree(DateTime t) {
  final dd = t.day.toString().padLeft(2, '0');
  final mm = t.month.toString().padLeft(2, '0');
  final hh = t.hour.toString().padLeft(2, '0');
  final min = t.minute.toString().padLeft(2, '0');
  return '$dd/$mm/${t.year} alle $hh:$min';
}

/// Lanciata al salvataggio se l'apparecchio è occupato: la UI mostra un AlertDialog con [message].
class DeviceUnavailableException implements Exception {
  final String deviceName;
  final DateTime? nextFree;
  const DeviceUnavailableException(this.deviceName, {this.nextFree});

  String get message {
    final name = deviceName.trim().isEmpty ? 'Apparecchio' : deviceName.trim();
    if (nextFree == null) return '$name non disponibile.';
    return '$name non disponibile. Prossima data prenotabile: ${formatDeviceNextFree(nextFree!)}';
  }

  @override
  String toString() => message;
}

/// Documento `devices/{id}` (id slug, es. `holter`). quantita = pezzi disponibili.
class Device {
  final String id;
  final String nome;
  final int quantita;
  final bool attivo;
  const Device({required this.id, required this.nome, this.quantita = 1, this.attivo = true});

  static const holterId = 'holter';
  static const holterPressorioId = 'holter-pressorio';
  static const holterDefaultHours = 24;
  static const holterDefaultQty = 1;

  factory Device.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Device(
      id: d.id,
      nome: (m['nome'] ?? d.id) as String,
      quantita: ((m['quantita'] as num?)?.toInt() ?? 1).clamp(1, 99),
      attivo: (m['attivo'] ?? true) as bool,
    );
  }

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'quantita': quantita < 1 ? 1 : quantita,
        'attivo': attivo,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static String slug(String name) {
    final b = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    return b.isEmpty ? 'apparecchio-${DateTime.now().millisecondsSinceEpoch}' : b;
  }

  /// Holter cardiaco e pressorio sono due apparecchi distinti (id/nome del servizio).
  static String? inferredId(String name, {String? id}) {
    final hay = '${id ?? ''} $name'.toLowerCase();
    if (!hay.contains('holter')) return null;
    if (hay.contains('pressor')) return holterPressorioId;
    return holterId;
  }

  static int inferredHours(String name, {String? id}) => inferredId(name, id: id) == null ? 0 : holterDefaultHours;

  static const defaults = [
    Device(id: holterId, nome: 'Holter cardiaco', quantita: holterDefaultQty),
    Device(id: holterPressorioId, nome: 'Holter pressorio', quantita: holterDefaultQty),
  ];

  static final Map<String, Device> registry = {for (final d in defaults) d.id: d};
  static bool _seeded = false;

  static CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore.instance.collection('devices');

  static String label(String id, {String? fallback}) =>
      registry[id]?.nome ?? (fallback?.isNotEmpty == true ? fallback! : id);

  static int quantityOf(String id) {
    final q = registry[id]?.quantita ?? ((id == holterId || id == holterPressorioId) ? holterDefaultQty : 1);
    return q < 1 ? 1 : q;
  }

  static List<Device> get ordered =>
      registry.values.where((d) => d.attivo).toList()..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));

  static Stream<List<Device>> watch() => _col.snapshots().map((q) {
        final list = q.docs.map(Device.fromDoc).toList();
        if (list.isNotEmpty) {
          registry
            ..clear()
            ..addEntries(list.map((d) => MapEntry(d.id, d)));
        }
        return registry.values.toList()..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
      });

  static StreamSubscription? _sub;
  static void listen() {
    _sub ??= watch().listen((_) {}, onError: (_) {});
  }

  /// Assicura i due Holter distinti; rinomina il vecchio documento generico «Holter» in «Holter cardiaco».
  static Future<void> seedIfEmpty() async {
    if (_seeded) return;
    for (final d in defaults) {
      final doc = await _col.doc(d.id).get();
      if (!doc.exists) {
        await _col.doc(d.id).set(d.toMap());
      } else if (d.id == holterId) {
        final nome = (doc.data()?['nome'] ?? '').toString().trim();
        if (nome.isEmpty || nome.toLowerCase() == 'holter') {
          await _col.doc(d.id).set({'nome': d.nome, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        }
      }
    }
    _seeded = true;
  }

  static Future<void> save(Device d) => _col.doc(d.id).set(d.toMap());
  static Future<void> delete(String id) => _col.doc(id).delete();
}
