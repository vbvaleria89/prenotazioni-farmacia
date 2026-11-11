/// Unisce le fasce (anche di persone diverse) in un solo intervallo di apertura.
/// La stanza è una: gli slot non si ricalcolano da ogni inizio sfalsato.
List<(int, int)> mergeOpenMinutes(Iterable<(int, int)> ranges) {
  final sorted = [for (final r in ranges) if (r.$2 > r.$1) r]..sort((a, b) => a.$1.compareTo(b.$1));
  final out = <(int, int)>[];
  for (final r in sorted) {
    if (out.isEmpty || r.$1 > out.last.$2) {
      out.add(r);
    } else if (r.$2 > out.last.$2) {
      final last = out.removeLast();
      out.add((last.$1, r.$2));
    }
  }
  return out;
}

/// Il cliente non vede uno slot che inizia prima che sia passata la durata del servizio.
List<DateTime> slotsForClient(List<DateTime> slots, DateTime now, Duration duration) {
  final earliest = now.add(duration);
  return [for (final t in slots) if (!t.isBefore(earliest)) t];
}

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
