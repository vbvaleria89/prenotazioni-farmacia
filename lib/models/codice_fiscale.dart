/// Codice fiscale italiano: formato, omocodia e carattere di controllo.
/// Stesse tabelle in `netlify/functions/_shared/codice_fiscale.mjs`.
const _odd = {
  '0': 1, '1': 0, '2': 5, '3': 7, '4': 9, '5': 13, '6': 15, '7': 17, '8': 19, '9': 21,
  'A': 1, 'B': 0, 'C': 5, 'D': 7, 'E': 9, 'F': 13, 'G': 15, 'H': 17, 'I': 19, 'J': 21,
  'K': 2, 'L': 4, 'M': 18, 'N': 20, 'O': 11, 'P': 3, 'Q': 6, 'R': 8, 'S': 12, 'T': 14,
  'U': 16, 'V': 10, 'W': 22, 'X': 25, 'Y': 24, 'Z': 23,
};

const _even = {
  '0': 0, '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9,
  'A': 0, 'B': 1, 'C': 2, 'D': 3, 'E': 4, 'F': 5, 'G': 6, 'H': 7, 'I': 8, 'J': 9,
  'K': 10, 'L': 11, 'M': 12, 'N': 13, 'O': 14, 'P': 15, 'Q': 16, 'R': 17, 'S': 18, 'T': 19,
  'U': 20, 'V': 21, 'W': 22, 'X': 23, 'Y': 24, 'Z': 25,
};

final _shape = RegExp(r'^[A-Z]{6}[0-9LMNPQRSTUV]{2}[ABCDEHLMPRST][0-9LMNPQRSTUV]{2}[A-Z][0-9LMNPQRSTUV]{3}[A-Z]$');

String normalizeCodiceFiscale(String raw) => raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();

String? codiceFiscaleChecksum(String first15) {
  final body = first15.toUpperCase();
  if (body.length != 15) return null;
  var sum = 0;
  for (var i = 0; i < 15; i++) {
    final table = i.isEven ? _odd : _even;
    final value = table[body[i]];
    if (value == null) return null;
    sum += value;
  }
  return String.fromCharCode(65 + (sum % 26));
}

bool isValidCodiceFiscale(String raw) {
  final cf = normalizeCodiceFiscale(raw);
  if (!_shape.hasMatch(cf)) return false;
  return codiceFiscaleChecksum(cf.substring(0, 15)) == cf[15];
}

/// Null se valido. Testo pronto per il form.
String? codiceFiscaleError(String? raw) {
  final cf = normalizeCodiceFiscale(raw ?? '');
  if (cf.isEmpty) return 'Obbligatorio';
  if (!isValidCodiceFiscale(cf)) return 'Codice fiscale non valido';
  return null;
}
