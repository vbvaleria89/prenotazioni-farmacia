import 'package:farmacia_prenotazioni/services/slot_grid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 11, 11);

  test('servizio da 30 min: slot ogni 30, non ogni 15', () {
    final slots = roomSlotStarts(day: day, openMinute: 9 * 60, closeMinute: 11 * 60, duration: const Duration(minutes: 30));
    expect(slots, [
      DateTime(2026, 11, 11, 9, 0),
      DateTime(2026, 11, 11, 9, 30),
      DateTime(2026, 11, 11, 10, 0),
      DateTime(2026, 11, 11, 10, 30),
    ]);
  });

  test('l ultimo slot deve finire entro la chiusura', () {
    final slots = roomSlotStarts(day: day, openMinute: 9 * 60, closeMinute: 10 * 60, duration: const Duration(minutes: 45));
    expect(slots, [DateTime(2026, 11, 11, 9, 0)]);
  });

  test('servizio da 15 min resta ogni 15 minuti', () {
    final slots = roomSlotStarts(day: day, openMinute: 9 * 60, closeMinute: 10 * 60, duration: const Duration(minutes: 15));
    expect(slots, [
      DateTime(2026, 11, 11, 9, 0),
      DateTime(2026, 11, 11, 9, 15),
      DateTime(2026, 11, 11, 9, 30),
      DateTime(2026, 11, 11, 9, 45),
    ]);
  });
}
