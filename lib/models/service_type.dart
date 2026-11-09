import 'package:cloud_firestore/cloud_firestore.dart';
import 'device.dart';
import 'room.dart';
export 'device.dart';
export 'room.dart';

/// Stanze fisse della farmacia (1 e 2). Una prenotazione ne occupa sempre una sola.
const int kStanza1 = 1;
const int kStanza2 = 2;
String labelStanza(int id) => Room.label(id);

String labelStanze(Iterable<int> ids) {
  final set = {...ids};
  final s = [for (final r in Room.ordered) if (set.contains(r.id)) r.id];
  if (s.isEmpty) return labelStanza(kStanza1);
  return s.map(labelStanza).join(' o ');
}

/// Documento Firestore `services/{id}` (gestito dal backoffice admin).
class ServiceType {
  final String id;
  final String name;
  final String description;
  final Duration duration;
  final bool attivo;
  final double? prezzo; // euro, prezzo pieno
  final double? prezzoScontato; // se valorizzato e < prezzo: prezzo barrato + scontato
  final Set<int> giorni; // giorni dedicati 1=lun..7=dom; vuoto = tutti i giorni
  final String dipendenteId, dipendenteNome; // persona dedicata (opzionale)
  final int ordine;
  /// Stanze utilizzabili in alternativa (1 e/o 2). Una prenotazione ne prende una sola.
  /// Default migrazione: solo Stanza 1 (comportamento stanza unica precedente).
  final Set<int> stanze;
  /// Apparecchio condiviso (collection `devices`). Vuoto = nessuno.
  final String deviceId;
  /// Ore in cui l'apparecchio resta occupato dopo l'inizio (es. 24 per l'Holter).
  final int deviceHoldHours;

  const ServiceType({required this.id, required this.name, required this.description, required this.duration,
      this.attivo = true, this.prezzo, this.prezzoScontato, this.giorni = const {}, this.dipendenteId = '', this.dipendenteNome = '', this.ordine = 0,
      this.stanze = const {kStanza1}, this.deviceId = '', this.deviceHoldHours = 0});

  bool get scontato => prezzo != null && prezzoScontato != null && prezzoScontato! < prezzo!;
  double? get prezzoFinale => scontato ? prezzoScontato : prezzo;
  bool availableOn(int weekday) => giorni.isEmpty || giorni.contains(weekday);

  /// Stanze ammesse ordinate (sempre almeno Stanza 1 se il set fosse vuoto).
  List<int> get stanzeOrdinate {
    final s = [for (final r in Room.ordered) if (stanze.contains(r.id)) r.id];
    if (s.isNotEmpty) return s;
    final act = Room.ordered;
    return act.isEmpty ? const [kStanza1] : [act.last.id];
  }

  String get stanzeLabel => labelStanze(stanzeOrdinate);

  bool get usesDevice => deviceId.isNotEmpty && deviceHoldHours > 0;
  DateTime deviceHoldEnd(DateTime start) => start.add(Duration(hours: deviceHoldHours));
  String get deviceLabel => usesDevice ? Device.label(deviceId) : '';

  static String _parseDeviceId(Map<String, dynamic> m, String name, String id) {
    final raw = (m['deviceId'] ?? '').toString().trim();
    final inferred = Device.inferredId(name, id: id);
    // Corregge il seed precedente che collegava il pressorio all'apparecchio cardiaco.
    if (inferred == Device.holterPressorioId && (raw.isEmpty || raw == Device.holterId)) return Device.holterPressorioId;
    if (raw.isNotEmpty) return raw;
    return inferred ?? '';
  }

  static int _parseHoldHours(Map<String, dynamic> m, String name, String id) {
    final n = (m['deviceHoldHours'] as num?)?.toInt() ?? 0;
    if (n > 0) return n;
    if ((m['deviceId'] ?? '').toString().trim().isNotEmpty) return Device.holterDefaultHours;
    return Device.inferredHours(name, id: id);
  }

  static double? _num(dynamic v) => v is num ? v.toDouble() : null;

  static Set<int> _parseStanze(dynamic raw) {
    if (raw is! List || raw.isEmpty) return const {kStanza1}; // migrazione: senza campo → Stanza 1
    final out = <int>{};
    for (final d in raw) {
      final n = (d as num).toInt();
      out.add(n);
    }
    return out.isEmpty ? const {kStanza1} : out;
  }

  factory ServiceType.fromMap(String id, Map<String, dynamic> m) => ServiceType(
        id: id,
        name: (m['nome'] ?? id) as String,
        description: (m['descrizione'] ?? '') as String,
        duration: Duration(minutes: (m['durataMin'] as num? ?? 15).toInt()),
        attivo: (m['attivo'] ?? true) as bool,
        prezzo: _num(m['prezzo']),
        prezzoScontato: _num(m['prezzoScontato']),
        giorni: {for (final d in (m['giorni'] as List? ?? const [])) (d as num).toInt()},
        dipendenteId: (m['dipendenteId'] ?? '') as String,
        dipendenteNome: (m['dipendenteNome'] ?? '') as String,
        ordine: (m['ordine'] as num? ?? 0).toInt(),
        stanze: _parseStanze(m['stanze']),
        deviceId: _parseDeviceId(m, (m['nome'] ?? id) as String, id),
        deviceHoldHours: _parseHoldHours(m, (m['nome'] ?? id) as String, id),
      );

  factory ServiceType.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) => ServiceType.fromMap(d.id, d.data() ?? {});

  Map<String, dynamic> toMap() => {
        'nome': name, 'descrizione': description, 'durataMin': duration.inMinutes, 'attivo': attivo,
        'prezzo': prezzo, 'prezzoScontato': prezzoScontato, 'giorni': giorni.toList()..sort(),
        'dipendenteId': dipendenteId, 'dipendenteNome': dipendenteNome, 'ordine': ordine,
        'stanze': stanzeOrdinate,
        'deviceId': deviceId,
        'deviceHoldHours': deviceHoldHours,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Cache aggiornata dallo stream `services` (usata per decodificare gli appuntamenti).
  static final Map<String, ServiceType> registry = {for (final s in mockServices) s.id: s};
  static ServiceType lookup(String? id, {String? nome, int? durataMin}) {
    final cached = registry[id];
    if (cached != null) return cached;
    final name = nome ?? id ?? 'Servizio';
    return ServiceType(
      id: id ?? '?',
      name: name,
      description: '',
      duration: Duration(minutes: durataMin ?? 15),
      deviceId: Device.inferredId(name, id: id) ?? '',
      deviceHoldHours: Device.inferredHours(name, id: id),
    );
  }
}

String euro(double v) => '€ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

// Seed iniziale (usato solo se la collezione `services` è vuota). NO Otopharma. Default Stanza 1.
const mockServices = [
  ServiceType(id: 'tricologico', name: 'Analisi tricologica', description: 'Check-up di capelli e cuoio capelluto', duration: Duration(minutes: 30), giorni: {2, 4}, ordine: 1, stanze: {kStanza1}),
  ServiceType(id: 'holter', name: 'Holter Cardiaco', description: 'Applicazione Holter cardiaco', duration: Duration(minutes: 20), ordine: 2, stanze: {kStanza1}, deviceId: Device.holterId, deviceHoldHours: Device.holterDefaultHours),
  ServiceType(id: 'holter-pressorio', name: 'Holter Pressorio', description: 'Applicazione Holter pressorio', duration: Duration(minutes: 20), ordine: 3, stanze: {kStanza1}, deviceId: Device.holterPressorioId, deviceHoldHours: Device.holterDefaultHours),
  ServiceType(id: 'analisi', name: 'Analisi varie', description: 'Glicemia, colesterolo, ecc.', duration: Duration(minutes: 15), ordine: 4, stanze: {kStanza1}),
];
