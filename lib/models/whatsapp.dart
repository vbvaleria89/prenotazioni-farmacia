/// Numero fisso della farmacia, senza zero iniziale: 345 070 9730 → 39 345 070 9730.
const kFarmaciaWhatsapp = '393450709730';

/// Template predefinito messaggio cliente → farmacia (`[Nome]` = nome del cliente).
const kDefaultWhatsappClientMessage =
    'Buongiorno, sono [Nome], vorrei informazioni su una prenotazione';

/// Link wa.me. Accetta 081…, +39…, 39… o il numero già internazionale.
/// Se [text] non è vuoto, aggiunge `?text=` URL-encoded.
String whatsAppLink(String? raw, {String? text}) {
  var digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.startsWith('0')) digits = '39${digits.substring(1)}';
  if (digits.length < 8 || digits.length > 15) digits = kFarmaciaWhatsapp;
  else if (!digits.startsWith('39')) digits = '39$digits';
  final base = 'https://wa.me/$digits';
  final t = (text ?? '').trim();
  if (t.isEmpty) return base;
  return '$base?text=${Uri.encodeComponent(t)}';
}

/// Compila il template WhatsApp cliente: sostituisce `[Nome]` con [nomeCliente].
/// Se il nome manca, rimuove «sono [Nome], » e lascia «Buongiorno, vorrei…».
String fillWhatsappClientMessage(String template, String? nomeCliente) {
  final t = template.trim().isEmpty ? kDefaultWhatsappClientMessage : template.trim();
  final nome = (nomeCliente ?? '').trim();
  if (nome.isEmpty) {
    return t
        .replaceAll(RegExp(r'sono\s*\[Nome\]\s*,?\s*', caseSensitive: false), '')
        .replaceAll('[Nome]', '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r',\s*,'), ',')
        .trim();
  }
  return t.replaceAll('[Nome]', nome);
}
