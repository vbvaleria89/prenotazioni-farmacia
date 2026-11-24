import 'service_type.dart';

/// Holter cardiaco e pressorio: il giorno dopo, allo stesso orario, la rimozione
/// occupa la stanza per un'ora. L'apparecchio torna prenotabile un'ora dopo,
/// per il tempo tecnico.
class HolterFollowUp {
  static const removalLength = Duration(hours: 1);
  static const technicalAfterRemoval = Duration(hours: 1);

  static bool applies(ServiceType service) =>
      service.usesDevice &&
      (service.deviceId == Device.holterId || service.deviceId == Device.holterPressorioId);

  /// Stesso orario del giorno successivo.
  static DateTime removalStart(DateTime fitting) =>
      DateTime(fitting.year, fitting.month, fitting.day + 1, fitting.hour, fitting.minute);

  static DateTime removalEnd(DateTime fitting) => removalStart(fitting).add(removalLength);

  /// Fine occupazione apparecchio: fine rimozione + un'ora tecnica.
  static DateTime deviceFreeAt(DateTime fitting) => removalEnd(fitting).add(technicalAfterRemoval);

  static int occupiedHours(DateTime fitting) {
    final h = deviceFreeAt(fitting).difference(fitting).inHours;
    return h < 1 ? 1 : h;
  }

  static ServiceType removalService(ServiceType fitting) => ServiceType(
        id: fitting.id,
        name: 'Rimozione ${fitting.name}',
        description: 'Rimozione in stanza',
        duration: removalLength,
        stanze: fitting.stanze,
      );
}
