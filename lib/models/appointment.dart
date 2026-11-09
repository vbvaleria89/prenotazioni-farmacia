import 'package:cloud_firestore/cloud_firestore.dart';
import 'service_type.dart';

enum AppointmentStatus { inAttesa, confermato, annullato, completato }

/// Documento Firestore `appointments/{id}`.
class Appointment {
  final String id;
  final ServiceType service;
  final DateTime start;
  final DateTime end;
  final String customerName;
  final String phone;
  final String? email;
  final AppointmentStatus status;
  final String? createdBy;
  final String? calendarEventId;
  final String? employeeId;
  /// Nome della persona assegnata (fasce per persona).
  final String? employeeNome;
  final bool esenzione;
  final String? ricettaNumero;
  final String? ricettaNote;
  final bool ricettaFoto;
  final bool pagato;
  /// `carta` | `bancomat` se pagato al banco; null se non pagato / non indicato.
  final String? metodoPagamento;
  /// UID Firebase Auth email/password collegato dalla function (non dall'app).
  final String? clienteUid;
  final String? clienteAccount;
  final String? codiceFiscale;
  /// Stanza effettivamente occupata da questa prenotazione (1 o 2). Sempre una sola.
  final int roomId;
  /// Nome stanza salvato alla prenotazione (fallback se la stanza viene eliminata).
  final String? roomName;
  /// Annullamento: `cliente` | `staff` | null.
  final String? annullatoDa;
  final DateTime? annullatoAt;
  /// Rimborso manuale al POS dopo annullamento di una prenotazione pagata.
  final bool rimborsoRichiesto;
  /// `pending` | `done` | null.
  final String? rimborsoStato;
  final DateTime? rimborsoAt;
  final bool clienteChiamato;

  Appointment({required this.id, required this.service, required this.start, DateTime? end, required this.customerName, required this.phone, this.email,
      this.status = AppointmentStatus.inAttesa, this.createdBy, this.calendarEventId, this.employeeId, this.employeeNome, this.esenzione = false, this.ricettaNumero, this.ricettaNote, this.ricettaFoto = false, this.pagato = false, this.metodoPagamento, this.clienteUid, this.clienteAccount, this.codiceFiscale,
      this.roomId = kStanza1, this.roomName, this.annullatoDa, this.annullatoAt, this.rimborsoRichiesto = false, this.rimborsoStato, this.rimborsoAt, this.clienteChiamato = false})
      : end = end ?? start.add(service.duration);

  bool get blocksRoom => status == AppointmentStatus.inAttesa || status == AppointmentStatus.confermato;
  bool overlaps(DateTime s, DateTime e) => start.isBefore(e) && s.isBefore(end);
  String get stanzaLabel => Room.label(roomId, fallback: roomName);
  bool get rimborsoPending => rimborsoRichiesto && rimborsoStato == 'pending';
  bool get rimborsoDone => rimborsoStato == 'done';

  /// Fine slot già passata (end ≤ now).
  bool isEnded([DateTime? now]) {
    final n = now ?? DateTime.now();
    return !end.isAfter(n);
  }

  /// Stato UI: scadute ancora inAttesa/confermato si mostrano come effettuate
  /// anche prima che lo staff (o il watch) scriva `completato` su Firestore.
  AppointmentStatus effectiveStatus([DateTime? now]) {
    if (status == AppointmentStatus.annullato || status == AppointmentStatus.completato) return status;
    if (isEnded(now) && blocksRoom) return AppointmentStatus.completato;
    return status;
  }

  /// Cliente: annullabile solo se restano almeno 24 ore all'inizio (e non è già finita).
  static const clientCancelLead = Duration(hours: 24);
  bool clientMayCancel([DateTime? now]) {
    if (!blocksRoom) return false;
    final n = now ?? DateTime.now();
    if (isEnded(n)) return false;
    return !start.difference(n).isNegative && start.difference(n) >= clientCancelLead;
  }

  /// Mostra il bottone Annulla al cliente: nascosto se già finita o non attiva.
  bool clientShowsCancel([DateTime? now]) {
    if (!blocksRoom) return false;
    return !isEnded(now);
  }

  String get shortCode => id.length >= 6 ? id.substring(0, 6).toUpperCase() : id.toUpperCase();

  factory Appointment.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    final svc = ServiceType.lookup(m['servizio'] as String?, nome: m['servizioNome'] as String?, durataMin: (m['durataMin'] as num?)?.toInt());
    final rawRoom = (m['roomId'] as num?)?.toInt();
    final room = rawRoom ?? kStanza1; // migrazione: senza campo → Stanza 1
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    return Appointment(
      id: d.id,
      service: svc,
      start: (m['start'] as Timestamp).toDate(),
      end: (m['end'] as Timestamp?)?.toDate(),
      customerName: (m['clienteNome'] ?? '') as String,
      phone: (m['clienteTel'] ?? '') as String,
      email: m['clienteEmail'] as String?,
      status: AppointmentStatus.values.firstWhere((s) => s.name == m['status'], orElse: () => AppointmentStatus.inAttesa),
      createdBy: m['createdBy'] as String?,
      calendarEventId: m['calendarEventId'] as String?,
      employeeId: m['employeeId'] as String?,
      employeeNome: m['employeeNome'] as String?,
      esenzione: (m['esenzione'] ?? false) as bool,
      ricettaNumero: m['ricettaNumero'] as String?,
      ricettaNote: m['ricettaNote'] as String?,
      ricettaFoto: (m['ricettaFoto'] ?? false) as bool,
      pagato: (m['pagato'] ?? false) as bool,
      metodoPagamento: m['metodoPagamento'] as String?,
      clienteUid: m['clienteUid'] as String?,
      clienteAccount: m['clienteAccount'] as String?,
      codiceFiscale: m['clienteCodiceFiscale'] as String?,
      roomId: room,
      roomName: m['roomName'] as String?,
      annullatoDa: m['annullatoDa'] as String?,
      annullatoAt: ts(m['annullatoAt']),
      rimborsoRichiesto: (m['rimborsoRichiesto'] ?? false) as bool,
      rimborsoStato: m['rimborsoStato'] as String?,
      rimborsoAt: ts(m['rimborsoAt']),
      clienteChiamato: (m['clienteChiamato'] ?? false) as bool,
    );
  }

  Map<String, dynamic> toMap() => {
        'servizio': service.id,
        'servizioNome': service.name,
        'durataMin': service.duration.inMinutes,
        'esenzione': esenzione,
        if (esenzione) 'ricettaNumero': ricettaNumero,
        if (esenzione) 'ricettaNote': ricettaNote,
        if (esenzione) 'ricettaFoto': ricettaFoto,
        'pagato': pagato,
        if (metodoPagamento != null && metodoPagamento!.isNotEmpty) 'metodoPagamento': metodoPagamento,
        'prezzo': service.prezzoFinale,
        'start': Timestamp.fromDate(start),
        'end': Timestamp.fromDate(end),
        'clienteNome': customerName,
        'clienteTel': phone,
        if (codiceFiscale != null && codiceFiscale!.isNotEmpty) 'clienteCodiceFiscale': codiceFiscale,
        if (clienteUid != null && clienteUid!.isNotEmpty) 'clienteUid': clienteUid,
        if (email != null && email!.isNotEmpty) 'clienteEmail': email,
        'status': status.name,
        'createdBy': createdBy,
        'calendarEventId': calendarEventId,
        'employeeId': employeeId,
        if (employeeNome != null) 'employeeNome': employeeNome,
        'roomId': roomId,
        'roomName': Room.registry[roomId]?.nome ?? roomName,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
