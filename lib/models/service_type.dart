import 'package:cloud_firestore/cloud_firestore.dart';
import 'room.dart';
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

  const ServiceType({required this.id, required this.name, required this.description, required this.duration,
      this.attivo = true, this.prezzo, this.prezzoScontato, this.giorni = const {}, this.dipendenteId = '', this.dipendenteNome = '', this.ordine = 0,
      this.stanze = const {kStanza1}});

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
      );

  factory ServiceType.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) => ServiceType.fromMap(d.id, d.data() ?? {});

  Map<String, dynamic> toMap() => {
        'nome': name, 'descrizione': description, 'durataMin': duration.inMinutes, 'attivo': attivo,
        'prezzo': prezzo, 'prezzoScontato': prezzoScontato, 'giorni': giorni.toList()..sort(),
        'dipendenteId': dipendenteId, 'dipendenteNome': dipendenteNome, 'ordine': ordine,
        'stanze': stanzeOrdinate,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Cache aggiornata dallo stream `services` (usata per decodificare gli appuntamenti).
  static final Map<String, ServiceType> registry = {for (final s in mockServices) s.id: s};
  static ServiceType lookup(String? id, {String? nome, int? durataMin}) =>
      registry[id] ?? ServiceType(id: id ?? '?', name: nome ?? id ?? 'Servizio', description: '', duration: Duration(minutes: durataMin ?? 15));
}

String euro(double v) => '€ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

// Seed iniziale (usato solo se la collezione `services` è vuota). NO Otopharma. Default Stanza 1.
const mockServices = [
  ServiceType(id: 'tricologico', name: 'Analisi tricologica', description: 'Check-up di capelli e cuoio capelluto', duration: Duration(minutes: 30), giorni: {2, 4}, ordine: 1, stanze: {kStanza1}),
  ServiceType(id: 'holter', name: 'Holter', description: 'Applicazione Holter cardiaco/pressorio', duration: Duration(minutes: 20), ordine: 2, stanze: {kStanza1}),
  ServiceType(id: 'analisi', name: 'Analisi varie', description: 'Glicemia, colesterolo, ecc.', duration: Duration(minutes: 15), ordine: 3, stanze: {kStanza1}),
];
