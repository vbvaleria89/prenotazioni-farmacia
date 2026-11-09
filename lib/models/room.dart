import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Documento `rooms/{id}` (id numerico stabile come stringa). priorita: più basso = scelta preferita.
class Room {
  final int id;
  final String nome;
  final int priorita;
  final bool attivo;
  const Room({required this.id, required this.nome, required this.priorita, this.attivo = true});

  factory Room.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final id = int.tryParse(d.id) ?? (m['id'] as num? ?? 0).toInt();
    return Room(id: id, nome: (m['nome'] ?? 'Stanza $id') as String, priorita: (m['priorita'] as num? ?? 99).toInt(), attivo: (m['attivo'] ?? true) as bool);
  }
  Map<String, dynamic> toMap() => {'id': id, 'nome': nome, 'priorita': priorita, 'attivo': attivo, 'updatedAt': FieldValue.serverTimestamp()};

  static const defaults = [
    Room(id: 2, nome: 'Stanza consulenze', priorita: 1),
    Room(id: 1, nome: 'Stanza servizi', priorita: 2),
  ];

  /// Cache globale aggiornata dallo stream `rooms`.
  static final Map<int, Room> registry = {for (final r in defaults) r.id: r};
  static bool _seeded = false;

  static CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore.instance.collection('rooms');

  static String label(int id, {String? fallback}) => registry[id]?.nome ?? (fallback?.isNotEmpty == true ? fallback! : 'Stanza $id');

  /// Stanze attive ordinate per priorità (poi id).
  static List<Room> get ordered => registry.values.where((r) => r.attivo).toList()..sort((a, b) => a.priorita != b.priorita ? a.priorita.compareTo(b.priorita) : a.id.compareTo(b.id));

  static Stream<List<Room>> watch() => _col.snapshots().map((q) {
        final list = q.docs.map(Room.fromDoc).toList();
        if (list.isNotEmpty) {
          registry..clear()..addEntries(list.map((r) => MapEntry(r.id, r)));
        }
        final all = registry.values.toList()..sort((a, b) => a.priorita != b.priorita ? a.priorita.compareTo(b.priorita) : a.id.compareTo(b.id));
        return all;
      });

  static StreamSubscription? _sub;
  static void listen() { _sub ??= watch().listen((_) {}, onError: (_) {}); }

  /// Solo admin: crea i default se la collection è vuota.
  static Future<void> seedIfEmpty() async {
    if (_seeded) return;
    final q = await _col.limit(1).get();
    if (q.docs.isEmpty) {
      for (final r in defaults) { await _col.doc('${r.id}').set(r.toMap()); }
    }
    _seeded = true;
  }

  static Future<void> save(Room r) => _col.doc('${r.id}').set(r.toMap());
  static Future<void> delete(int id) => _col.doc('$id').delete();
  static int nextId() => (registry.keys.isEmpty ? 0 : registry.keys.reduce((a, b) => a > b ? a : b)) + 1;
}
