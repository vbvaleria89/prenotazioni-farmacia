/// Nome da mostrare: profilo, poi displayName, poi la parte prima della chiocciola.
String customerGreeting({String? nome, String? displayName, String? email}) {
  String first(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return '';
    return text.split(RegExp(r'\s+')).first;
  }

  final fromProfile = first(nome);
  if (fromProfile.isNotEmpty) return fromProfile;
  final fromAuth = first(displayName);
  if (fromAuth.isNotEmpty) return fromAuth;
  final mail = (email ?? '').trim();
  final at = mail.indexOf('@');
  if (at > 0) return mail.substring(0, at);
  return 'cliente';
}

/// Prenotazioni visibili al cliente loggato: le sue (uid) e, per lo storico, la stessa email.
bool bookingBelongsToCustomer({String? clienteUid, String? email, required String uid, String? authEmail}) {
  if (uid.isNotEmpty && clienteUid != null && clienteUid.isNotEmpty && clienteUid == uid) return true;
  final stored = (email ?? '').trim().toLowerCase();
  final mine = (authEmail ?? '').trim().toLowerCase();
  return mine.isNotEmpty && stored == mine;
}

List<T> filterCustomerBookings<T>(
  Iterable<T> items, {
  required String uid,
  String? authEmail,
  required String? Function(T item) clienteUid,
  required String? Function(T item) email,
  required DateTime Function(T item) start,
  required String Function(T item) id,
}) {
  final seen = <String>{};
  final out = <T>[];
  for (final item in items) {
    if (!bookingBelongsToCustomer(clienteUid: clienteUid(item), email: email(item), uid: uid, authEmail: authEmail)) continue;
    if (seen.add(id(item))) out.add(item);
  }
  out.sort((a, b) => start(a).compareTo(start(b)));
  return out;
}
