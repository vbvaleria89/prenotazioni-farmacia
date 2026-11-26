import 'package:farmacia_prenotazioni/models/recall.dart';
import 'package:farmacia_prenotazioni/models/whatsapp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final oggi = DateTime(2026, 11, 26, 15, 0);
  final controllo = DateTime(2026, 12, 20);

  test('senza data non parte l\'avviso', () {
    expect(recallStato(prossimoControllo: null, contattato: false, leadDays: 15, now: oggi), RecallStato.senzaRisultato);
  });

  test('l\'avviso parte 15 giorni prima e non cambia stato da solo', () {
    expect(recallAvvisoDal(controllo, 15), DateTime(2026, 12, 5));
    expect(recallStato(prossimoControllo: controllo, contattato: false, leadDays: 15, now: DateTime(2026, 12, 4)), RecallStato.inCorso);
    expect(recallStato(prossimoControllo: controllo, contattato: false, leadDays: 15, now: DateTime(2026, 12, 5)), RecallStato.daAvvisare);
    expect(recallStato(prossimoControllo: controllo, contattato: true, leadDays: 15, now: DateTime(2026, 12, 5)), RecallStato.avvisato);
  });

  test('il messaggio recall non contiene note cliniche', () {
    final msg = fillWhatsappRecallMessage(
      nome: 'Mario Rossi',
      servizio: 'Holter Cardiaco',
      prossimo: controllo,
    );
    expect(msg, contains('Mario Rossi'));
    expect(msg, contains('Holter Cardiaco'));
    expect(msg, contains('20 dicembre 2026'));
    expect(msg, isNot(contains('farmaco')));
  });
}
