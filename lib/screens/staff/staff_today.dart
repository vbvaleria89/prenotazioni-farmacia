import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
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
  bool _statusLoading = true;
  bool _serverConnected = false;
  String? _connectedEmail;
  String? _reason;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<String?> _idToken() async => FirebaseAuth.instance.currentUser?.getIdToken();

  Future<void> _refreshStatus() async {
    try {
      final token = await _idToken();
      if (token == null) return;
      final r = await http.get(Uri.base.resolve('/api/gcal-status'),
        headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200 && mounted) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() {
          _serverConnected = j['connected'] == true;
          _connectedEmail = j['email'] as String?;
          _reason = j['reason'] as String?;
          _statusLoading = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _statusLoading = false);
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      final token = await _idToken();
      if (token == null) throw StateError('non autenticato');
      final r = await http.post(Uri.base.resolve('/api/gcal-oauth-start'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        throw StateError('HTTP ${r.statusCode}');
      }
      final url = (jsonDecode(r.body) as Map)['url'] as String?;
      if (url == null || url.isEmpty) throw StateError('url assente');
      openExternal(url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Completa il consenso Google con l\'account della farmacia, poi torna qui.')));
      }
      // Dopo il consenso il callback allinea da solo le prenotazioni; ricontrollo lo stato.
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(seconds: 5));
        if (!mounted) return;
        await _refreshStatus();
        if (_serverConnected) break;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Collegamento non riuscito: $e')));
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _calendarBanner() {
    final ok = _serverConnected;
    final admin = widget.employee.isAdmin;
    final text = _statusLoading
        ? 'Verifico il collegamento a Google Calendar…'
        : ok
            ? 'Google Calendar collegato come ${_connectedEmail ?? 'account farmacia'}: le prenotazioni si sincronizzano da sole.'
            : _reason == 'expired'
                ? (admin
                    ? 'Google Calendar scollegato: il collegamento è scaduto o revocato. Premi «Ricollega Google Calendar» e accedi con farmaciasanciro.servizi@gmail.com.'
                    : 'Google Calendar scollegato: il collegamento è scaduto. Chiedi a un amministratore di ricollegarlo.')
            : admin
                ? 'Google Calendar non collegato. Premi il pulsante e accedi con farmaciasanciro.servizi@gmail.com.'
                : 'Google Calendar non collegato. Chiedi a un amministratore di collegarlo una volta sola.';
    return Card(
      color: ok ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Icon(ok ? Icons.check_circle : Icons.warning_amber, color: ok ? Colors.green : Colors.orange),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: Text(text, style: const TextStyle(fontSize: 16))),
          if (admin) SizedBox(
            height: 52,
            child: FilledButton.icon(
                onPressed: _busy ? null : _connect,
                icon: const Icon(Icons.calendar_month),
                label: Text(ok || _reason == 'expired' ? 'Ricollega Google Calendar' : 'Collega Google Calendar', style: const TextStyle(fontSize: 16))),
          ),
          if (admin || ok) TextButton(onPressed: _statusLoading ? null : _refreshStatus, child: const Text('Aggiorna stato')),
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
    // secondarie = dati/organizzazione; principali = stato/pagamento/contatto
    final secondary = <(String, IconData, VoidCallback)>[
      ('Cliente', Icons.person_outline, () => apriCorrezioneCliente(context, a)),
      if (a.status != AppointmentStatus.annullato) ('Modifica', Icons.edit, () => apriModificaPrenotazione(context, a)),
      if (a.status != AppointmentStatus.annullato) ('Ricetta', Icons.medication_outlined, () => apriRicetta(context, a)),
      if (a.blocksRoom) ('Riprogramma', Icons.event_repeat, () => apriRiprogramma(context, a, asStaff: true)),
      if (a.blocksRoom) ('Libera', Icons.meeting_room, () => run(() => bookingService.freeRoom(a))),
    ];
    final primary = <(String, IconData, Color, VoidCallback?)>[
      if (a.status == AppointmentStatus.inAttesa) ('Conferma', Icons.check, const Color(0xFF2E9E4F), () => run(() => bookingService.confirm(a))),
      if (a.blocksRoom) ('Annulla', Icons.close, const Color(0xFFC62828), () => annullaPrenotazione(context, a)),
      if (a.rimborsoPending) ('Rimborsato', Icons.currency_exchange, const Color(0xFF9B2C2C), () => segnaRimborsato(context, a)),
      if (!a.pagato && a.status != AppointmentStatus.annullato) ('Pagato', Icons.euro, const Color(0xFF2E9E4F), () => segnaPagato(context, a)),
      if (waClienteDigits(a) != null) ('WhatsApp', Icons.chat, const Color(0xFF1B7A3D), () => apriWhatsAppCliente(a)),
    ];
    final showSecondary = a.status != AppointmentStatus.annullato
        ? (active ? secondary : [for (final x in secondary) if (x.$1 != 'Riprogramma' && x.$1 != 'Libera') x])
        : [for (final x in secondary) if (x.$1 == 'Cliente') x];
    final showPrimary = a.status == AppointmentStatus.annullato
        ? [for (final x in primary) if (x.$1 == 'Rimborsato' || x.$1 == 'WhatsApp') x]
        : primary;
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
          if (showSecondary.isNotEmpty || showPrimary.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ResponsiveActions(primary: showPrimary, secondary: showSecondary),
          ],
        ]),
      ),
    );
  }
}

/// Azioni card: a larghezza piena mostra tutto; restringendo nasconde nel menu ☰.
class _ResponsiveActions extends StatelessWidget {
  final List<(String, IconData, Color, VoidCallback?)> primary;
  final List<(String, IconData, VoidCallback)> secondary;
  const _ResponsiveActions({required this.primary, required this.secondary});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      // <520: secondarie nel menu · <400: resta 1–2 principali + menu
      final hideSecondary = w < 520;
      final tight = w < 400;
      final visiblePrimary = tight
          ? [
              for (final x in primary)
                if (x.$1 == 'Conferma' || x.$1 == 'Pagato' || x.$1 == 'Rimborsato' || x.$1 == 'WhatsApp') x,
            ].take(2).toList()
          : primary;
      final menuPrimary = [
        for (final x in primary)
          if (!visiblePrimary.any((v) => v.$1 == x.$1)) x,
      ];
      final menuSecondary = hideSecondary ? secondary : const <(String, IconData, VoidCallback)>[];
      final showSecondaryInline = hideSecondary ? const <(String, IconData, VoidCallback)>[] : secondary;
      final hasMenu = menuSecondary.isNotEmpty || menuPrimary.isNotEmpty;

      Widget primaryBtn((String, IconData, Color, VoidCallback?) x) => FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: x.$3,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: x.$4,
            icon: Icon(x.$2, size: 18),
            label: Text(x.$1, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          );
      Widget secondaryBtn((String, IconData, VoidCallback) x) => OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Brand.primary,
              side: BorderSide(color: Brand.primary.withValues(alpha: 0.35)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: x.$3,
            icon: Icon(x.$2, size: 18),
            label: Text(x.$1, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          );

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showSecondaryInline.isNotEmpty) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [for (final x in showSecondaryInline) secondaryBtn(x)]),
          if (visiblePrimary.isNotEmpty || hasMenu) const SizedBox(height: 8),
        ],
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final x in visiblePrimary) primaryBtn(x),
          if (hasMenu)
            PopupMenuButton<VoidCallback>(
              tooltip: 'Altre azioni',
              position: PopupMenuPosition.under,
              offset: const Offset(0, 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (fn) => fn(),
              itemBuilder: (ctx) => [
                for (final x in menuPrimary)
                  if (x.$4 != null)
                    PopupMenuItem(
                      value: x.$4,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(x.$2, color: x.$3),
                        title: Text(x.$1, style: TextStyle(fontWeight: FontWeight.w600, color: x.$3)),
                      ),
                    ),
                if (menuPrimary.any((x) => x.$4 != null) && menuSecondary.isNotEmpty) const PopupMenuDivider(),
                for (final x in menuSecondary)
                  PopupMenuItem(
                    value: x.$3,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(x.$2, color: Brand.primary),
                      title: Text(x.$1, style: const TextStyle(fontWeight: FontWeight.w600, color: Brand.primary)),
                    ),
                  ),
              ],
              child: Material(
                color: Brand.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.menu, color: Brand.primary, size: 20),
                    SizedBox(width: 6),
                    Text('Altro', style: TextStyle(color: Brand.primary, fontWeight: FontWeight.w700, fontSize: 14)),
                  ]),
                ),
              ),
            ),
        ]),
      ]);
    });
  }
}
