import 'package:farmacia_prenotazioni/models/codice_fiscale.dart';
import 'package:farmacia_prenotazioni/models/customer_bookings.dart';
import 'package:farmacia_prenotazioni/models/notice.dart';
import 'package:farmacia_prenotazioni/models/personal_role.dart';
import 'package:farmacia_prenotazioni/models/whatsapp.dart';
import 'package:farmacia_prenotazioni/services/auth_persistence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('codice fiscale: checksum, spazi e valori rifiutati', () {
    expect(codiceFiscaleChecksum('RSSMRA85T10A562'), 'S');
    expect(isValidCodiceFiscale('RSSMRA85T10A562S'), isTrue);
    expect(isValidCodiceFiscale('rss mra85t10a562s'), isTrue);
    expect(normalizeCodiceFiscale(' rss mra85t10a562s '), 'RSSMRA85T10A562S');
    expect(isValidCodiceFiscale('RSSMRA85T10A562A'), isFalse);
    expect(codiceFiscaleError(''), 'Obbligatorio');
    expect(codiceFiscaleError('RSSMRA85T10A562A'), 'Codice fiscale non valido');
    expect(codiceFiscaleError('RSSMRA85T10A562S'), isNull);
  });

  test('filtro prenotazioni: solo uid o email del cliente, senza duplicati', () {
    final mine = _B('1', uid: 'u1', email: 'a@b.c', start: DateTime(2026, 11, 2));
    final legacy = _B('2', email: 'A@B.C', start: DateTime(2026, 11, 1));
    final other = _B('3', uid: 'u2', email: 'altro@b.c', start: DateTime(2026, 11, 3));
    final dup = _B('1', uid: 'u1', email: 'a@b.c', start: DateTime(2026, 11, 2));
    final visible = filterCustomerBookings<_B>(
      [other, mine, legacy, dup],
      uid: 'u1',
      authEmail: 'a@b.c',
      clienteUid: (b) => b.uid,
      email: (b) => b.email,
      start: (b) => b.start,
      id: (b) => b.id,
    );
    expect(visible.map((b) => b.id).toList(), ['2', '1']);
    expect(bookingBelongsToCustomer(clienteUid: 'u2', email: 'altro@b.c', uid: 'u1', authEmail: 'a@b.c'), isFalse);
  });

  test('saluto cliente: nome, poi displayName, poi email', () {
    expect(customerGreeting(nome: 'Maria Rossi', displayName: 'Altro', email: 'x@y.z'), 'Maria');
    expect(customerGreeting(nome: '  ', displayName: 'Luca Bianchi', email: 'a@b.c'), 'Luca');
    expect(customerGreeting(nome: '', displayName: '', email: 'maria@example.com'), 'maria');
    expect(customerGreeting(nome: null, displayName: null, email: ''), 'cliente');
  });

  test('resta connesso: il default è sì, solo 0 lo spegne', () {
    expect(preferLocalPersistence(null), isTrue);
    expect(preferLocalPersistence('1'), isTrue);
    expect(preferLocalPersistence('0'), isFalse);
  });

  test('WhatsApp: 081 570 4733 diventa wa.me italiano', () {
    expect(whatsAppLink('081 570 4733'), 'https://wa.me/390815704733');
    expect(whatsAppLink('+39 081 570 4733'), 'https://wa.me/390815704733');
    expect(whatsAppLink(''), 'https://wa.me/$kFarmaciaWhatsapp');
  });

  test('bacheca: solo attivi e dentro le date', () {
    final now = DateTime(2026, 11, 4, 12);
    final live = Notice(id: 'a', titolo: 'Promo', attivo: true, tipo: 'promo', ordine: 0);
    final off = Notice(id: 'b', titolo: 'Spenta', attivo: false);
    final future = Notice(id: 'c', titolo: 'Dopo', attivo: true, start: DateTime(2026, 12, 1));
    final week = Notice(id: 'd', titolo: 'Ora', attivo: true, ordine: 1, start: DateTime(2026, 11, 2), end: DateTime(2026, 11, 8));
    expect(liveNotices([future, off, week, live], now).map((n) => n.id).toList(), ['a', 'd']);
  });

  test('ruolo: senza employees è cliente, staff solo se attivo', () {
    expect(resolvePersonalRole(employeeExists: false, attivo: false), PersonalRole.customer);
    expect(resolvePersonalRole(employeeExists: true, attivo: true), PersonalRole.staff);
    expect(() => resolvePersonalRole(employeeExists: true, attivo: false), throwsStateError);
  });
}

class _B {
  final String id;
  final String? uid;
  final String? email;
  final DateTime start;
  const _B(this.id, {this.uid, this.email, required this.start});
}
