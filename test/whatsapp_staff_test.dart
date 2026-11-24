import 'package:farmacia_prenotazioni/models/whatsapp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final applicazione = DateTime(2026, 11, 24, 10, 30);
  final rimozione = DateTime(2026, 11, 25, 10, 30);

  test('promemoria normale usa i segnaposto della prenotazione', () {
    final msg = fillWhatsappStaffMessage(
      nome: 'Mario Rossi',
      servizio: 'ECG',
      quando: applicazione,
      codice: 'AB12CD',
    );
    expect(msg, contains('Mario Rossi'));
    expect(msg, contains('ECG il 24 novembre alle ore 10:30'));
    expect(msg, contains('AB12CD'));
    expect(msg, isNot(contains('rimozione')));
  });

  test('promemoria Holter cita applicazione e rimozione', () {
    final msg = fillWhatsappStaffMessage(
      nome: 'Mario Rossi',
      servizio: 'Holter Cardiaco',
      quando: applicazione,
      codice: 'AB12CD',
      rimozione: rimozione,
    );
    expect(msg, contains('Holter Cardiaco per il 24 novembre alle ore 10:30'));
    expect(msg, contains('la rimozione il 25 novembre alle ore 10:30'));
  });

  test('un testo personalizzato sostituisce i segnaposto', () {
    final msg = fillWhatsappStaffMessage(
      holterTemplate: 'Holter [Giorno] ore [Ora], rimozione [RimozioneGiorno] ore [RimozioneOra].',
      nome: 'Anna',
      servizio: 'Holter',
      quando: applicazione,
      codice: 'X',
      rimozione: rimozione,
    );
    expect(msg, 'Holter 24 novembre ore 10:30, rimozione 25 novembre ore 10:30.');
  });
}
