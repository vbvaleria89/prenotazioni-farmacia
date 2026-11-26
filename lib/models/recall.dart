/// Esito inserito dallo staff. L'app non interpreta il referto.
const recallEsiti = ['norma', 'ricontrollare', 'medico'];

const recallEsitoLabel = {
  'norma': 'Nella norma',
  'ricontrollare': 'Da ricontrollare',
  'medico': 'Da far vedere al medico',
};

enum RecallStato { senzaRisultato, inCorso, daAvvisare, avvisato }

/// Dati clinici del recall, separati dalla prenotazione. Id = id appuntamento.
class RecallRecord {
  final String appointmentId;
  final String esito;
  final String note;
  final DateTime? prossimoControllo;
  final bool contattato;
  final DateTime? contattatoAt;
  final String contattatoDa;

  const RecallRecord({
    required this.appointmentId,
    this.esito = '',
    this.note = '',
    this.prossimoControllo,
    this.contattato = false,
    this.contattatoAt,
    this.contattatoDa = '',
  });

  RecallStato stato(int leadDays, DateTime now) => recallStato(
        prossimoControllo: prossimoControllo,
        contattato: contattato,
        leadDays: leadDays,
        now: now,
      );
}

DateTime recallGiorno(DateTime d) => DateTime(d.year, d.month, d.day);

/// Primo giorno in cui admin e staff vedono l'avviso.
DateTime? recallAvvisoDal(DateTime? prossimo, int leadDays) {
  if (prossimo == null) return null;
  final giorni = leadDays < 1 ? 1 : leadDays;
  return recallGiorno(prossimo).subtract(Duration(days: giorni));
}

bool recallInFinestra(DateTime? prossimo, int leadDays, DateTime now) {
  final dal = recallAvvisoDal(prossimo, leadDays);
  if (dal == null) return false;
  return !recallGiorno(now).isBefore(dal);
}

RecallStato recallStato({
  required DateTime? prossimoControllo,
  required bool contattato,
  required int leadDays,
  required DateTime now,
}) {
  if (prossimoControllo == null) return RecallStato.senzaRisultato;
  if (contattato) return RecallStato.avvisato;
  if (recallInFinestra(prossimoControllo, leadDays, now)) return RecallStato.daAvvisare;
  return RecallStato.inCorso;
}

String recallStatoLabel(RecallStato s) => switch (s) {
      RecallStato.senzaRisultato => 'Senza risultato',
      RecallStato.inCorso => 'In corso',
      RecallStato.daAvvisare => 'Da avvisare',
      RecallStato.avvisato => 'Avvisato',
    };

bool stessoGiornoRecall(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == null && b == null;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
