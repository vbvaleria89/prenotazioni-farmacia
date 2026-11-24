import 'package:farmacia_prenotazioni/models/device.dart';
import 'package:farmacia_prenotazioni/models/holter_followup.dart';
import 'package:farmacia_prenotazioni/models/service_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const holter = ServiceType(
    id: 'holter',
    name: 'Holter Cardiaco',
    description: 'Applicazione',
    duration: Duration(minutes: 30),
    deviceId: Device.holterId,
    deviceHoldHours: 24,
  );

  test('rimozione il giorno dopo allo stesso orario, per un\'ora', () {
    final fitting = DateTime(2026, 11, 24, 10, 30);
    expect(HolterFollowUp.applies(holter), isTrue);
    expect(HolterFollowUp.removalStart(fitting), DateTime(2026, 11, 25, 10, 30));
    expect(HolterFollowUp.removalEnd(fitting), DateTime(2026, 11, 25, 11, 30));
  });

  test('l\'apparecchio torna libero un\'ora dopo la fine della rimozione', () {
    final fitting = DateTime(2026, 11, 24, 10, 30);
    expect(HolterFollowUp.deviceFreeAt(fitting), DateTime(2026, 11, 25, 12, 30));
    expect(HolterFollowUp.occupiedHours(fitting), 26);
  });

  test('la rimozione non tiene occupato un altro apparecchio', () {
    final removal = HolterFollowUp.removalService(holter);
    expect(removal.name, 'Rimozione Holter Cardiaco');
    expect(removal.duration, const Duration(hours: 1));
    expect(removal.usesDevice, isFalse);
  });
}
