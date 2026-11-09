import 'package:flutter_test/flutter_test.dart';
import 'package:farmacia_prenotazioni/models/device.dart';

void main() {
  // Holter prenotato il 9/11/2026 alle 16:00, occupato 24 ore: [9/11 16:00, 10/11 16:00).
  final booked = DateTime(2026, 11, 9, 16);
  final hold = DeviceHold(
    appointmentId: 'h1',
    deviceId: Device.holterId,
    start: booked,
    holdEnd: booked.add(const Duration(hours: 24)),
  );
  const qty = 1;
  const hours = 24;

  bool freeAt(DateTime t) {
    final n = countOverlappingDeviceHolds(
      deviceId: Device.holterId,
      windowStart: t,
      windowEnd: t.add(const Duration(hours: hours)),
      holds: [hold],
    );
    return isDeviceQuantityFree(quantity: qty, overlapping: n);
  }

  DateTime? next(DateTime t) => nextFreeDeviceStart(
        deviceId: Device.holterId,
        holdHours: hours,
        quantity: qty,
        requested: t,
        holds: [hold],
      );

  test('Holter 9/11 16:00: 8/11 16:00 e 10/11 16:00 liberi, 16:30 e 15:30 bloccati', () {
    final freeStart = DateTime(2026, 11, 8, 16, 0);
    final blockedEarly = DateTime(2026, 11, 8, 16, 30);
    final blockedLate = DateTime(2026, 11, 10, 15, 30);
    final freeEnd = DateTime(2026, 11, 10, 16, 0);

    expect(freeAt(freeStart), isTrue, reason: '8/11 16:00: [8 16, 9 16) non sovrappone [9 16, 10 16)');
    expect(freeAt(blockedEarly), isFalse, reason: '8/11 16:30: [8 16:30, 9 16:30) sovrappone');
    expect(freeAt(booked), isFalse);
    expect(freeAt(blockedLate), isFalse, reason: '10/11 15:30: [10 15:30, 11 15:30) sovrappone');
    expect(freeAt(freeEnd), isTrue, reason: '10/11 16:00 torna prenotabile (holdEnd escluso)');

    expect(next(freeStart), freeStart);
    expect(next(blockedEarly), freeEnd);
    expect(next(booked), freeEnd);
    expect(next(blockedLate), freeEnd);
    expect(next(freeEnd), freeEnd);
  });

  test('inizio > 8/11 16:00 e < 10/11 16:00 non prenotabile; estremi sì', () {
    expect(freeAt(DateTime(2026, 11, 8, 16, 15)), isFalse);
    expect(freeAt(DateTime(2026, 11, 9, 9)), isFalse);
    expect(freeAt(DateTime(2026, 11, 8, 15, 45)), isTrue);
    expect(freeAt(DateTime(2026, 11, 10, 16, 15)), isTrue);
  });

  test('messaggio popup con prossima data prenotabile', () {
    final e = DeviceUnavailableException('Holter', nextFree: DateTime(2026, 11, 10, 16));
    expect(e.message, 'Holter non disponibile. Prossima data prenotabile: 10/11/2026 alle 16:00');
  });

  test('due pezzi: un solo Holter non satura la quantità', () {
    final n = countOverlappingDeviceHolds(
      deviceId: Device.holterId,
      windowStart: booked,
      windowEnd: booked.add(const Duration(hours: 24)),
      holds: [hold],
    );
    expect(isDeviceQuantityFree(quantity: 2, overlapping: n), isTrue);
    expect(isDeviceQuantityFree(quantity: 1, overlapping: n), isFalse);
  });

  test('annullata non occupa; excludeId ignora se stessa', () {
    final cancelled = DeviceHold(
      appointmentId: 'h2',
      deviceId: Device.holterId,
      start: booked,
      holdEnd: booked.add(const Duration(hours: 24)),
      status: 'annullato',
    );
    expect(
      countOverlappingDeviceHolds(
        deviceId: Device.holterId,
        windowStart: booked,
        windowEnd: booked.add(const Duration(hours: 24)),
        holds: [cancelled],
      ),
      0,
    );
    expect(
      countOverlappingDeviceHolds(
        deviceId: Device.holterId,
        windowStart: booked,
        windowEnd: booked.add(const Duration(hours: 24)),
        holds: [hold],
        excludeId: 'h1',
      ),
      0,
    );
  });

  test('daysOverlappingHold copre entrambi i giorni di un Holter 24h', () {
    final days = daysOverlappingHold(booked, booked.add(const Duration(hours: 24)));
    expect(days, [DateTime(2026, 11, 9), DateTime(2026, 11, 10)]);
  });

  test('inferenza: cardiaco e pressorio sono apparecchi distinti', () {
    expect(Device.inferredId('Holter Cardiaco', id: 'holter'), Device.holterId);
    expect(Device.inferredId('Holter', id: 'holter'), Device.holterId);
    expect(Device.inferredId('Holter Pressorio', id: 'holter-pressorio'), Device.holterPressorioId);
    expect(Device.inferredId('Holter pressorio', id: 'altro'), Device.holterPressorioId);
    expect(Device.inferredId('Holter', id: 'holter-pressorio'), Device.holterPressorioId);
    expect(Device.inferredId('Analisi'), isNull);
  });

  test('prenotare il cardiaco non blocca il pressorio (e viceversa)', () {
    final cardioStart = DateTime(2026, 11, 9, 16);
    final cardio = DeviceHold(
      appointmentId: 'c1',
      deviceId: Device.holterId,
      start: cardioStart,
      holdEnd: cardioStart.add(const Duration(hours: 24)),
    );
    final pressorioStart = DateTime(2026, 11, 9, 16, 30);
    final nPressorio = countOverlappingDeviceHolds(
      deviceId: Device.holterPressorioId,
      windowStart: pressorioStart,
      windowEnd: pressorioStart.add(const Duration(hours: 24)),
      holds: [cardio],
    );
    expect(nPressorio, 0);
    expect(isDeviceQuantityFree(quantity: 1, overlapping: nPressorio), isTrue);

    final pressorio = DeviceHold(
      appointmentId: 'p1',
      deviceId: Device.holterPressorioId,
      start: pressorioStart,
      holdEnd: pressorioStart.add(const Duration(hours: 24)),
    );
    final nCardio = countOverlappingDeviceHolds(
      deviceId: Device.holterId,
      windowStart: cardioStart,
      windowEnd: cardioStart.add(const Duration(hours: 24)),
      holds: [pressorio],
    );
    expect(nCardio, 0);
  });
}
