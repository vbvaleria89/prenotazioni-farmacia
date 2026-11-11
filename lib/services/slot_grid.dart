/// Inizi prenotabili dentro una fascia. Il passo è la durata del servizio:
/// la stanza resta occupata per tutto quel tempo, quindi lo slot successivo
/// non inizia prima della fine.
List<DateTime> roomSlotStarts({
  required DateTime day,
  required int openMinute,
  required int closeMinute,
  required Duration duration,
}) {
  final minutes = duration.inMinutes;
  final pace = Duration(minutes: minutes < 1 ? 15 : minutes);
  final origin = DateTime(day.year, day.month, day.day);
  final close = origin.add(Duration(minutes: closeMinute));
  final out = <DateTime>[];
  for (var t = origin.add(Duration(minutes: openMinute)); !t.add(pace).isAfter(close); t = t.add(pace)) {
    out.add(t);
  }
  return out;
}
