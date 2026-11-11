import 'dart:convert';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../models/appointment.dart';
import '../../services/open_link.dart';

/// Dati impegnativa + pulsante foto, per viste staff.
class RicettaInfo extends StatelessWidget {
  final Appointment a;
  const RicettaInfo(this.a, {super.key});

  Future<void> _show(BuildContext context) async {
    final b64 = await bookingService.ricettaFoto(a.id);
    if (!context.mounted) return;
    await showDialog<void>(context: context, builder: (ctx) => Dialog(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (b64 == null) const Padding(padding: EdgeInsets.all(24), child: Text('Foto non disponibile'))
        else Flexible(child: InteractiveViewer(child: Image.memory(base64Decode(b64)))),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Chiudi')),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!a.esenzione) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
        Text('Ricetta: ${a.ricettaNumero ?? '—'}${(a.ricettaNote ?? '').isNotEmpty ? ' · ${a.ricettaNote}' : ''}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF32448C))),
        if (a.ricettaFoto)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF2E9E4F), visualDensity: VisualDensity.compact),
            onPressed: () => _show(context), icon: const Icon(Icons.image, size: 18), label: const Text('Vedi foto')),
      ]),
    );
  }
}


/// Badge Pagato / Non pagato.
class PagatoBadge extends StatelessWidget {
  final Appointment a;
  const PagatoBadge(this.a, {super.key});
  @override
  Widget build(BuildContext context) {
    final ok = a.pagato;
    final metodo = switch (a.metodoPagamento) {
      'carta' => ' · Carta',
      'contanti' => ' · Contanti',
      'bancomat' => ' · Bancomat',
      _ => '',
    };
    return Pill(ok ? 'Pagato$metodo' : 'Non pagato',
        bg: ok ? const Color(0xFFD9F2E3) : const Color(0xFFFDE1D3),
        fg: ok ? const Color(0xFF1E6B3A) : const Color(0xFF9A4A26),
        icon: ok ? Icons.check_circle_outline : Icons.schedule);
  }
}

/// Pill pastello con bordo morbido.
class Pill extends StatelessWidget {
  final String text; final Color bg, fg; final IconData? icon;
  const Pill(this.text, {super.key, required this.bg, required this.fg, this.icon});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20), border: Border.all(color: fg.withValues(alpha: 0.25))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Stato prenotazione come pill pastello.
class StatoBadge extends StatelessWidget {
  final AppointmentStatus s;
  const StatoBadge(this.s, {super.key});
  @override
  Widget build(BuildContext context) => switch (s) {
        AppointmentStatus.inAttesa => const Pill('Da confermare', bg: Color(0xFFFFF1CC), fg: Color(0xFF8A6100), icon: Icons.hourglass_top),
        AppointmentStatus.confermato => const Pill('Confermato', bg: Color(0xFFD9F2E3), fg: Color(0xFF1E6B3A), icon: Icons.check_circle),
        AppointmentStatus.annullato => const Pill('Annullato', bg: Color(0xFFFADBD8), fg: Color(0xFF9B2C2C), icon: Icons.cancel),
        AppointmentStatus.completato => const Pill('Effettuata', bg: Color(0xFFDCE8F5), fg: Color(0xFF2B4C70), icon: Icons.check_circle_outline),
      };
}

/// Tap «Pagato» al banco: mini scelta Carta | Contanti, poi salva.
Future<String?> scegliMetodoPagamento(BuildContext context) => showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Expanded(child: SizedBox(height: 64, child: FilledButton.icon(onPressed: () => Navigator.pop(c, 'carta'), icon: const Icon(Icons.credit_card), label: const Text('Carta', style: TextStyle(fontSize: 20))))),
        const SizedBox(width: 12),
        Expanded(child: SizedBox(height: 64, child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E9E4F)), onPressed: () => Navigator.pop(c, 'contanti'), icon: const Icon(Icons.payments), label: const Text('Contanti', style: TextStyle(fontSize: 20))))),
      ]),
    )),
  );

Future<void> segnaPagato(BuildContext context, Appointment a) async {
  final m = ScaffoldMessenger.of(context);
  final metodo = await scegliMetodoPagamento(context);
  if (metodo == null) return;
  try { await bookingService.setPagato(a, true, metodoPagamento: metodo); }
  catch (e) { m.showSnackBar(SnackBar(content: Text('Operazione non riuscita: $e'))); }
}

/// Link wa.me verso il telefono del cliente; null se il numero non è valido.
String? waClienteLink(Appointment a) {
  var d = a.phone.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.length == 10 && d.startsWith('3')) d = '39$d';
  if (d.length < 11 || d.length > 15) return null;
  const mesi = ['gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre'];
  final s = a.start;
  final ora = '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}';
  final nome = a.customerName.trim().isEmpty ? '' : ' ${a.customerName.trim()}';
  final msg = 'Buongiorno$nome, le ricordiamo la prenotazione presso Farmacia San Ciro: '
      '${a.service.name} il ${s.day} ${mesi[s.month - 1]} alle ore $ora. '
      'Codice prenotazione: ${a.id.substring(0, 6).toUpperCase()}. '
      'Per modifiche o disdette risponda a questo messaggio. Grazie!';
  return 'https://wa.me/$d?text=${Uri.encodeComponent(msg)}';
}

/// Bottone WhatsApp verso il cliente (nascosto se manca il telefono).
class WhatsAppClienteButton extends StatelessWidget {
  final Appointment a;
  final bool big;
  const WhatsAppClienteButton(this.a, {super.key, this.big = false});
  @override
  Widget build(BuildContext context) {
    final link = waClienteLink(a);
    if (link == null) return const SizedBox.shrink();
    const green = Color(0xFF25D366);
    if (big) {
      return SizedBox(height: 56, child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: green),
        onPressed: () => openExternal(link), icon: const Icon(Icons.chat), label: const Text('WhatsApp', style: TextStyle(fontSize: 18))));
    }
    return TextButton.icon(onPressed: () => openExternal(link), icon: const Icon(Icons.chat, size: 16, color: green), label: const Text('WhatsApp'));
  }
}

/// Conferma e annulla (staff/admin). Se pagata, avvisa dello storno al POS.
Future<bool> annullaPrenotazione(BuildContext context, Appointment a) async {
  if (a.status == AppointmentStatus.annullato) return false;
  final m = ScaffoldMessenger.of(context);
  final paid = a.pagato;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(paid ? 'Annulla e rimborsa?' : 'Annullare la prenotazione?'),
      content: Text(paid
          ? 'Prenotazione pagata (codice ${a.shortCode}). Ricordati di stornare al POS / chiamare il cliente (${a.customerName}, tel. ${a.phone}).'
          : 'Confermi l\'annullamento di ${a.service.name} per ${a.customerName}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Indietro')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(c, true), child: const Text('Annulla prenotazione')),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await bookingService.cancel(a, asStaff: true);
    m.showSnackBar(SnackBar(content: Text(paid ? 'Annullata. In Notifiche trovi il rimborso da gestire.' : 'Prenotazione annullata.')));
    return true;
  } catch (e) {
    m.showSnackBar(SnackBar(content: Text('Annullamento non riuscito: $e')));
    return false;
  }
}

/// Dialog Segna rimborsato (+ opzionale «ho chiamato il cliente»).
Future<bool> segnaRimborsato(BuildContext context, Appointment a) async {
  final m = ScaffoldMessenger.of(context);
  var chiamato = a.clienteChiamato;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setLocal) => AlertDialog(
      title: const Text('Segna rimborsato'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Prenotazione ${a.shortCode} · ${a.customerName}\nTel. ${a.phone}${a.metodoPagamento != null ? '\nMetodo: ${a.metodoPagamento}' : ''}${a.service.prezzoFinale != null ? '\nImporto: € ${a.service.prezzoFinale!.toStringAsFixed(2)}' : ''}'),
        const SizedBox(height: 12),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: chiamato,
          onChanged: (v) => setLocal(() => chiamato = v ?? false),
          title: const Text('Ho chiamato / contattato il cliente'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Indietro')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Conferma rimborsato')),
      ],
    )),
  );
  if (ok != true) return false;
  try {
    await bookingService.markRimborsato(a, chiamatoCliente: chiamato);
    m.showSnackBar(const SnackBar(content: Text('Rimborso segnato come effettuato')));
    return true;
  } catch (e) {
    m.showSnackBar(SnackBar(content: Text('Salvataggio non riuscito: $e')));
    return false;
  }
}

/// Badge rimborso pending / done.
class RimborsoBadge extends StatelessWidget {
  final Appointment a;
  const RimborsoBadge(this.a, {super.key});
  @override
  Widget build(BuildContext context) {
    if (a.rimborsoPending) {
      return const Pill('Da rimborsare', bg: Color(0xFFFADBD8), fg: Color(0xFF9B2C2C), icon: Icons.currency_exchange);
    }
    if (a.rimborsoDone) {
      return const Pill('Rimborsato', bg: Color(0xFFDCE8F5), fg: Color(0xFF2B4C70), icon: Icons.done_all);
    }
    return const SizedBox.shrink();
  }
}

