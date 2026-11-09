import '../client/reschedule_page.dart';
import '../../services/open_link.dart';
import 'ricetta_info.dart';
import 'edit_booking.dart';
import '../../theme/brand.dart';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../models/appointment.dart';
import '../../models/settings.dart';
import '../client/slot_picker.dart' show hhmm;

/// Schermata unica per lo staff al banco: tutto "oggi", testo grande, 1 tap per azione.
class StaffToday extends StatefulWidget {
  final Employee employee;
  const StaffToday({super.key, required this.employee});
  @override
  State<StaffToday> createState() => _StaffTodayState();
}

class _StaffTodayState extends State<StaffToday> {
  bool _busy = false;

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      await googleCalendar.connect();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Collegamento non riuscito: $e')));
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _calendarBanner() {
    final ok = googleCalendar.isConnected;
    return Card(
      color: ok ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Icon(ok ? Icons.check_circle : Icons.warning_amber, color: ok ? Colors.green : Colors.orange),
          Text(ok ? 'Google Calendar collegato: conferme/annulli sincronizzati' : 'Calendar non collegato: prenotazioni salvate in app, non nel calendario',
              style: const TextStyle(fontSize: 16)),
          SizedBox(
            height: 52,
            child: ok
                ? OutlinedButton(onPressed: () => setState(googleCalendar.disconnect), child: const Text('Scollega'))
                : FilledButton.icon(
                    onPressed: _busy ? null : _connect,
                    icon: const Icon(Icons.calendar_month),
                    label: const Text('Collega Google Calendar', style: TextStyle(fontSize: 16))),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandAppBar(subtitle: 'Oggi · ${widget.employee.nome}'),
      body: StreamBuilder<List<Appointment>>(
        stream: bookingService.watchDay(DateTime.now()),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Errore: ${snap.error}'));
          final list = snap.data ?? const <Appointment>[];
          return ListView(padding: const EdgeInsets.all(8), children: [
            _calendarBanner(),
            if (!snap.hasData) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            if (list.isEmpty)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Nessun appuntamento oggi', style: TextStyle(fontSize: 22)))),
            for (final a in list) _Tile(a),
          ]);
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final Appointment a;
  const _Tile(this.a);

  @override
  Widget build(BuildContext context) {
    Future<void> run(Future<void> Function() f) async {
      final m = ScaffoldMessenger.of(context);
      try { await f(); } catch (e) { m.showSnackBar(SnackBar(content: Text('Operazione non riuscita: $e'))); }
    }
    final active = a.blocksRoom;
    final actions = <(String, IconData, Color, VoidCallback?)>[
      ('Correggi dati cliente', Icons.person_outline, const Color(0xFF32448C), () => apriCorrezioneCliente(context, a)),
      if (a.status != AppointmentStatus.annullato) ('Modifica', Icons.edit, const Color(0xFF32448C), () => apriModificaPrenotazione(context, a)),
      if (a.blocksRoom) ('Riprogramma', Icons.event_repeat, const Color(0xFF32448C), () => apriRiprogramma(context, a, asStaff: true)),
      ('Conferma', Icons.check, Colors.green, a.status == AppointmentStatus.inAttesa ? () => run(() => bookingService.confirm(a)) : null),
      if (a.blocksRoom) ('Annulla', Icons.close, Colors.red, () => annullaPrenotazione(context, a)),
      if (a.rimborsoPending) ('Segna rimborsato', Icons.currency_exchange, const Color(0xFF9B2C2C), () => segnaRimborsato(context, a)),
      ('Libera stanza', Icons.meeting_room, Colors.blue, () => run(() => bookingService.freeRoom(a))),
      if (!a.pagato) ('Pagato', Icons.euro, const Color(0xFF2E9E4F), () => segnaPagato(context, a)),
      if (waClienteLink(a) != null) ('WhatsApp', Icons.chat, const Color(0xFF25D366), () => openExternal(waClienteLink(a)!)),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('${hhmm(a.start)}–${hhmm(a.end)}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const Spacer(),
            StatoBadge(a.effectiveStatus()),
          ]),
          Text('${a.service.name} · ${a.stanzaLabel} · ${a.customerName}', style: const TextStyle(fontSize: 18)),
          Text('Tel. ${a.phone}${(a.email ?? '').isNotEmpty ? ' · ${a.email}' : ''}${(a.codiceFiscale ?? '').isNotEmpty ? '\nCF ${a.codiceFiscale}' : ''}', style: const TextStyle(fontSize: 15, color: Colors.black87)),
          Padding(padding: const EdgeInsets.only(top: 4), child: Chip(
            visualDensity: VisualDensity.compact,
            backgroundColor: a.esenzione ? const Color(0xFF2E9E4F) : Colors.grey.shade300,
            label: Text(a.esenzione ? 'Con esenzione' : 'Senza esenzione', style: TextStyle(color: a.esenzione ? Colors.white : Colors.black87)))),
          Wrap(spacing: 6, children: [PagatoBadge(a), RimborsoBadge(a)]),
                  RicettaInfo(a),
          if (a.status != AppointmentStatus.annullato || a.rimborsoPending) ...[
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, c) {
              final narrow = c.maxWidth < 480;
              final shown = a.status == AppointmentStatus.annullato
                  ? [for (final x in actions) if (x.$1 == 'Segna rimborsato' || x.$1 == 'Correggi dati cliente' || x.$1 == 'WhatsApp') x]
                  : active
                  ? actions
                  : [for (final x in actions) if (x.$1 == 'Correggi dati cliente' || x.$1 == 'Modifica' || x.$1 == 'WhatsApp' || x.$1 == 'Segna rimborsato') x];
              final btns = [
                for (final (t, i, col, f) in shown)
                  SizedBox(
                    height: 56,
                    width: narrow ? double.infinity : null,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: col, padding: const EdgeInsets.symmetric(horizontal: 16)),
                      onPressed: f,
                      icon: Icon(i),
                      label: Text(t, softWrap: false, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
              ];
              return narrow
                  ? Column(children: [for (final b in btns) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: b)])
                  : Row(children: [for (final b in btns) Expanded(child: Padding(padding: const EdgeInsets.all(4), child: b))]);
            }),
          ],
        ]),
      ),
    );
  }
}
