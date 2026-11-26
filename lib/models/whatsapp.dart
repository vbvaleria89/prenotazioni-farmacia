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

/// Promemoria staff → cliente, una prenotazione.
const kDefaultWhatsappStaffMessage =
    'Buongiorno [Nome], le ricordiamo la prenotazione presso Farmacia San Ciro: '
    '[Servizio] il [Giorno] alle ore [Ora]. '
    'Codice prenotazione: [Codice]. '
    'Per modifiche o disdette risponda a questo messaggio. Grazie!';

/// Promemoria staff → cliente quando c'è anche la rimozione Holter.
const kDefaultWhatsappStaffHolterMessage =
    'Buongiorno [Nome], le ricordiamo che ha prenotato [Servizio] per il [Giorno] alle ore [Ora], '
    'e la rimozione il [RimozioneGiorno] alle ore [RimozioneOra]. '
    'Codice prenotazione: [Codice]. '
    'Per modifiche o disdette risponda a questo messaggio. Grazie!';

const _mesiLunghi = [
  'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno',
  'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre',
];

String whatsappGiorno(DateTime d) => '${d.day} ${_mesiLunghi[d.month - 1]}';

String whatsappOra(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Compila il promemoria dello staff. Se [rimozione] è valorizzata usa il testo Holter.
String fillWhatsappStaffMessage({
  String? template,
  String? holterTemplate,
  required String nome,
  required String servizio,
  required DateTime quando,
  required String codice,
  DateTime? rimozione,
}) {
  final conRimozione = rimozione != null;
  final raw = conRimozione
      ? ((holterTemplate ?? '').trim().isEmpty ? kDefaultWhatsappStaffHolterMessage : holterTemplate!.trim())
      : ((template ?? '').trim().isEmpty ? kDefaultWhatsappStaffMessage : template!.trim());
  final chi = nome.trim();
  var t = chi.isEmpty ? raw.replaceAll('[Nome]', '') : raw.replaceAll('[Nome]', chi);
  t = t
      .replaceAll('[Servizio]', servizio.trim())
      .replaceAll('[Giorno]', whatsappGiorno(quando))
      .replaceAll('[Ora]', whatsappOra(quando))
      .replaceAll('[Codice]', codice.trim());
  if (conRimozione) {
    t = t
        .replaceAll('[RimozioneGiorno]', whatsappGiorno(rimozione))
        .replaceAll('[RimozioneOra]', whatsappOra(rimozione));
  }
  return t.replaceAll(RegExp(r'[ \t]{2,}'), ' ').replaceAll(RegExp(r'\s+,'), ',').trim();
}

/// Promemoria recall: niente esito e niente note cliniche.
const kDefaultWhatsappRecallMessage =
    'Buongiorno [Nome], le ricordiamo che è il momento di ripetere il controllo [Servizio]. '
    'Il prossimo controllo è previsto per il [ProssimoControllo]. '
    'Può passare in farmacia o prenotare un appuntamento. Grazie, Farmacia San Ciro.';

/// Compila il remind del recall. [prossimo] vuoto toglie la frase sulla data se il testo è quello predefinito.
String fillWhatsappRecallMessage({
  String? template,
  required String nome,
  required String servizio,
  DateTime? prossimo,
}) {
  final raw = (template ?? '').trim().isEmpty ? kDefaultWhatsappRecallMessage : template!.trim();
  final chi = nome.trim();
  var t = chi.isEmpty ? raw.replaceAll('[Nome]', '') : raw.replaceAll('[Nome]', chi);
  t = t.replaceAll('[Servizio]', servizio.trim());
  if (prossimo == null) {
    t = t.replaceAll(RegExp(r'Il prossimo controllo è previsto per il \[ProssimoControllo\]\.\s*'), '');
    t = t.replaceAll('[ProssimoControllo]', '');
  } else {
    t = t.replaceAll('[ProssimoControllo]', '${whatsappGiorno(prossimo)} ${prossimo.year}');
  }
  return t.replaceAll(RegExp(r'[ \t]{2,}'), ' ').replaceAll(RegExp(r'\s+,'), ',').trim();
}

/// Cifre internazionali di un cellulare cliente. Null se il numero non è usabile.
String? whatsAppClientDigits(String? raw) {
  var d = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.length == 10 && d.startsWith('3')) d = '39$d';
  if (d.length < 11 || d.length > 15) return null;
  return d;
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
