/// Fascia di disponibilità di un giorno (`availability/{yyyy-mm-dd}.fasce[]`).
/// [employeeId] null = fascia «farmacia» generica (dati vecchi, prima delle fasce per persona):
/// resta valida per qualunque servizio e non è legata a nessuno.
class Fascia {
  final int start, end; // minuti dalla mezzanotte
  final String? employeeId;
  final String? employeeNome;
  /// Servizi per cui vale la fascia. Vuota (fasce vecchie) = tutti i servizi che la persona sa fare.
  final List<String> servizi;
  const Fascia(this.start, this.end, {this.employeeId, this.employeeNome, this.servizi = const []});
  bool vale(String serviceId) => servizi.isEmpty || servizi.contains(serviceId);
  bool get generica => employeeId == null || employeeId!.isEmpty;
  String get chi => generica ? 'Farmacia' : ((employeeNome ?? '').isEmpty ? 'Persona' : employeeNome!);
  bool covers(int a, int b) => a >= start && b <= end;
  bool same(Fascia o) => o.start == start && o.end == end && (o.employeeId ?? '') == (employeeId ?? '')
      && o.servizi.toSet().containsAll(servizi) && servizi.toSet().containsAll(o.servizi);
  Map<String, dynamic> toMap() => {'start': start, 'end': end, if (!generica) 'employeeId': employeeId, if (!generica) 'employeeNome': employeeNome ?? '', if (servizi.isNotEmpty) 'servizi': servizi};
  static Fascia? fromMap(Object? f) {
    if (f is! Map || f['start'] is! num || f['end'] is! num) return null;
    final id = f['employeeId'];
    return Fascia((f['start'] as num).toInt(), (f['end'] as num).toInt(),
        employeeId: id is String && id.isNotEmpty ? id : null, employeeNome: f['employeeNome'] as String?,
        servizi: [for (final x in (f['servizi'] is List ? f['servizi'] as List : const [])) x.toString()]);
  }
}
