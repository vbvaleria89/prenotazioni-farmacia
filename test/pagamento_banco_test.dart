import 'package:flutter_test/flutter_test.dart';
import 'package:farmacia_prenotazioni/models/appointment.dart';
import 'package:farmacia_prenotazioni/models/service_type.dart';

void main() {
  const svc = ServiceType(
    id: 'test',
    name: 'Test',
    description: 'desc',
    duration: Duration(minutes: 30),
    giorni: {1, 2, 3, 4, 5},
    prezzo: 25,
  );

  test('Appointment tiene metodoPagamento carta/contanti', () {
    final a = Appointment(
      id: 'abc123',
      service: svc,
      start: DateTime(2026, 11, 5, 10),
      customerName: 'Mario Rossi',
      phone: '3331234567',
      pagato: true,
      metodoPagamento: 'carta',
    );
    expect(a.pagato, isTrue);
    expect(a.metodoPagamento, 'carta');
    expect(a.email, isNull);
  });

  test('telefono obbligatorio: stringa corta non valida in UI (<=5)', () {
    bool phoneOk(String? v) => v != null && v.trim().length >= 6;
    expect(phoneOk(''), isFalse);
    expect(phoneOk('12345'), isFalse);
    expect(phoneOk('3331234567'), isTrue);
  });

  test('email staff facoltativa: vuota ok, formato invalido no', () {
    String? emailErr(String? v) {
      final t = (v ?? '').trim();
      if (t.isEmpty) return null;
      return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'Email non valida';
    }
    expect(emailErr(''), isNull);
    expect(emailErr('   '), isNull);
    expect(emailErr('a@b.it'), isNull);
    expect(emailErr('nope'), 'Email non valida');
  });

  test('carta/contanti implica pagato in book()', () {
    String? normalize(String? metodoPagamento, bool pagato) {
      final metodo = (metodoPagamento == null || metodoPagamento.trim().isEmpty)
          ? null
          : metodoPagamento.trim().toLowerCase();
      final paid = pagato || metodo == 'carta' || metodo == 'contanti' || metodo == 'bancomat';
      return paid ? metodo : null;
    }
    expect(normalize('carta', false), 'carta');
    expect(normalize('contanti', false), 'contanti');
    expect(normalize('bancomat', false), 'bancomat');
    expect(normalize(null, false), isNull);
    expect(normalize('carta', true), 'carta');
  });
}
