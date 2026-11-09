import 'package:cloud_firestore/cloud_firestore.dart';

/// Volantino in `notices/{id}`.
class Notice {
  final String id;
  final String titolo;
  final String testo;
  final String tipo; // novita | evento | promo
  final String imageUrl;
  final String periodo; // '' | settimana | mese
  final DateTime? start;
  final DateTime? end;
  final bool attivo;
  final int ordine;
  final String serviceId, serviceName; // solo eventi prenotabili

  const Notice({
    required this.id,
    required this.titolo,
    this.testo = '',
    this.tipo = 'novita',
    this.imageUrl = '',
    this.periodo = '',
    this.start,
    this.end,
    this.attivo = true,
    this.ordine = 0,
    this.serviceId = '',
    this.serviceName = '',
  });

  bool get prenotabile => tipo == 'evento' && serviceId.isNotEmpty;

  static const tipi = ['novita', 'evento', 'promo'];

  String get tipoLabel => switch (tipo) {
        'evento' => 'Evento',
        'promo' => 'Promo',
        _ => 'Novità',
      };

  factory Notice.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    DateTime? date(dynamic v) => v is Timestamp ? v.toDate() : null;
    final tipo = (m['tipo'] ?? 'novita') as String;
    return Notice(
      id: d.id,
      titolo: (m['titolo'] ?? '') as String,
      testo: (m['testo'] ?? '') as String,
      tipo: Notice.tipi.contains(tipo) ? tipo : 'novita',
      imageUrl: (m['imageUrl'] ?? '') as String,
      periodo: (m['periodo'] ?? '') as String,
      start: date(m['start']),
      end: date(m['end']),
      attivo: (m['attivo'] ?? false) as bool,
      ordine: (m['ordine'] as num? ?? 0).toInt(),
      serviceId: tipo == 'evento' ? (m['serviceId'] ?? '') as String : '',
      serviceName: tipo == 'evento' ? (m['serviceName'] ?? '') as String : '',
    );
  }

  Map<String, dynamic> toMap() => {
        'titolo': titolo,
        'testo': testo,
        'tipo': tipo,
        'imageUrl': imageUrl,
        'periodo': periodo,
        'attivo': attivo,
        'ordine': ordine,
        'serviceId': tipo == 'evento' ? serviceId : '',
        'serviceName': tipo == 'evento' ? serviceName : '',
        if (start != null) 'start': Timestamp.fromDate(DateTime(start!.year, start!.month, start!.day)),
        if (end != null) 'end': Timestamp.fromDate(DateTime(end!.year, end!.month, end!.day)),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

/// Visibile in bacheca cliente: attivo e, se ci sono date, dentro l'intervallo (fine inclusa).
bool noticeIsLive(Notice n, DateTime now) {
  if (!n.attivo) return false;
  if (n.start != null && now.isBefore(DateTime(n.start!.year, n.start!.month, n.start!.day))) return false;
  if (n.end != null && now.isAfter(DateTime(n.end!.year, n.end!.month, n.end!.day, 23, 59, 59))) return false;
  return true;
}

List<Notice> liveNotices(Iterable<Notice> all, DateTime now) {
  final list = all.where((n) => noticeIsLive(n, now)).toList()
    ..sort((a, b) => a.ordine != b.ordine ? a.ordine.compareTo(b.ordine) : a.titolo.compareTo(b.titolo));
  return list;
}
