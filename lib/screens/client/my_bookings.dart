import 'package:firebase_auth/firebase_auth.dart';
import '../account/edit_account.dart';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../models/appointment.dart';
import '../../models/whatsapp.dart';
import '../../services/open_link.dart';
import '../../theme/brand.dart';
import '../role_picker.dart';
import '../staff/staff_hub.dart';
import '../../models/personal_role.dart';
import 'notice_flyer.dart';
import 'services_home.dart';
import 'slot_picker.dart' show hhmm;
import 'reschedule_page.dart';

/// Area personale cliente: hub a tessere.
class MyBookings extends StatefulWidget {
  const MyBookings({super.key});
  @override
  State<MyBookings> createState() => _MyBookingsState();
}

class _MyBookingsState extends State<MyBookings> {
  bool _checkingStaff = true;
  bool _showHint = false;
  bool _resetBusy = false;
  String _nome = '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  bool _real(User? u) => u != null && !u.isAnonymous && (u.email ?? '').isNotEmpty;

  /// Non esce mai da solo: attende utente + email (loader). Solo se dopo 15 s non c'è
  /// alcun utente reale torna alla home, SENZA cancellare la sessione.
  Future<void> _start() async {
    if (!_real(customerAuth.user)) {
      try {
        await FirebaseAuth.instance.authStateChanges().firstWhere(_real).timeout(const Duration(seconds: 15));
      } catch (_) {
        if (!mounted) return;
        final cu = FirebaseAuth.instance.currentUser;
        if (cu != null && !cu.isAnonymous) {
          if (await _tryStaffHub()) return;
        } else {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const RolePicker()), (_) => false);
          return;
        }
      }
    }
    if (!mounted) return;
    _ensureStaffHub();
    customerAuth.profile().then((p) {
      if (mounted && p != null) setState(() => _nome = p.nome);
    });
    customerAuth.passwordChanged().then((done) {
      if (mounted) setState(() => _showHint = !done);
    });
  }

  Future<void> _ensureStaffHub() async {
    if (CustomerAuth.isKnownStaffEmail(customerAuth.user?.email)) {
      final s = await customerAuth.sessionForCurrentUser().catchError((_) => const PersonalSession.customer());
      if (!mounted) return;
      if (s.employee != null) {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => StaffHub(employee: s.employee!)), (route) => false);
        return;
      }
    }
    for (var i = 0; i < 3 && mounted; i++) {
      if (await _tryStaffHub()) return;
      await Future.delayed(const Duration(milliseconds: 800));
    }
    if (mounted) setState(() => _checkingStaff = false);
  }

  Future<bool> _tryStaffHub() async {
    try {
      final session = await customerAuth.sessionForCurrentUser();
      if (!mounted) return true;
      if (session.role == PersonalRole.staff && session.employee != null) {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => StaffHub(employee: session.employee!)), (route) => false);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _logout() async {
    final nav = Navigator.of(context);
    await customerAuth.signOut();
    nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const RolePicker()), (_) => false);
  }

  Future<void> _markDone() async {
    setState(() => _showHint = false);
    try { await customerAuth.markPasswordChanged(); } catch (_) {}
  }

  Future<void> _resetPassword() async {
    setState(() => _resetBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await customerAuth.sendPasswordReset();
      messenger.showSnackBar(const SnackBar(content: Text('Ti abbiamo inviato un link per scegliere una nuova password')));
      await _markDone();
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Invio del link non riuscito. Usa quello nella mail di conferma.')));
    }
    if (mounted) setState(() => _resetBusy = false);
  }

  void _go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    if (_checkingStaff) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final email = customerAuth.user?.email ?? '';
    final nome = _nome.isNotEmpty ? _nome.split(' ').first : (customerAuth.user?.displayName ?? '');
    final tiles = <_HubTile>[
      _HubTile(Icons.event_note, 'Le mie prenotazioni', 'Prossime e precedenti', Brand.primary, () => _go(const MyBookingsList())),
      _HubTile(Icons.add_circle_outline, 'Nuova prenotazione', 'Scegli servizio e orario', Brand.primary, () => _go(const ServicesHome())),
      _HubTile(Icons.campaign_outlined, 'Novità', 'Dalla farmacia', Brand.primary, () => _go(const NoticeListScreen(tipo: 'novita', title: 'Novità'))),
      _HubTile(Icons.local_offer_outlined, 'Promo', 'Offerte attive', Brand.green, () => _go(const NoticeListScreen(tipo: 'promo', title: 'Promo'))),
      _HubTile(Icons.celebration_outlined, 'Eventi', 'Giornate e iniziative', Brand.primary, () => _go(const NoticeListScreen(tipo: 'evento', title: 'Eventi'))),
      _HubTile(Icons.chat, 'WhatsApp', 'Scrivici', const Color(0xFF128C7E), () async {
        var raw = '';
        var template = kDefaultWhatsappClientMessage;
        try {
          final s = await bookingService.settings();
          raw = s.whatsapp;
          template = s.whatsappClientMessage;
        } catch (_) {}
        final fullName = _nome.trim().isNotEmpty
            ? _nome.trim()
            : (customerAuth.user?.displayName ?? '').trim();
        final msg = fillWhatsappClientMessage(template, fullName);
        openExternal(whatsAppLink(raw, text: msg));
      }),
    ];
    return Scaffold(
      appBar: BrandAppBar(subtitle: 'Area personale', implyLeading: false, actions: [
        IconButton(tooltip: 'Il mio account', onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const EditAccountPage()));
          final profile = await customerAuth.profile();
          final done = await customerAuth.passwordChanged();
          if (mounted) setState(() { _nome = profile?.nome ?? _nome; _showHint = !done; });
        }, icon: const Icon(Icons.manage_accounts_outlined)),
        IconButton(tooltip: 'Esci', onPressed: _logout, icon: const Icon(Icons.logout)),
      ]),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text(nome.isEmpty ? 'Ciao!' : 'Ciao, $nome', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Brand.primary)),
          if (email.isNotEmpty) Text('Accesso: $email', style: const TextStyle(fontSize: 13, color: Colors.black54)),
          if (_showHint) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
              const Icon(Icons.info_outline, size: 16, color: Colors.black45),
              const Text('Password iniziale: quella temporanea nella mail.', style: TextStyle(fontSize: 13, color: Colors.black54)),
              TextButton(onPressed: _resetBusy ? null : _resetPassword, child: const Text('Cambia password')),
              TextButton(onPressed: _markDone, child: const Text('Ho già una password mia')),
            ]),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 900 ? 3 : 2;
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: c.maxWidth >= 600 ? 1.6 : 1.05,
              children: [for (final t in tiles) _HubCard(t)],
            );
          }),
        ]),
      )),
    );
  }
}

class _HubTile {
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _HubTile(this.icon, this.title, this.subtitle, this.color, this.onTap);
}

class _HubCard extends StatelessWidget {
  const _HubCard(this.t);
  final _HubTile t;
  @override
  Widget build(BuildContext context) => Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: t.onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(t.icon, size: 36, color: t.color),
              const SizedBox(height: 10),
              Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: t.color)),
              Text(t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Colors.black54)),
            ]),
          ),
        ),
      );
}

/// Lista prenotazioni del cliente.
class MyBookingsList extends StatelessWidget {
  const MyBookingsList({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandAppBar(subtitle: 'Le mie prenotazioni'),
      body: StreamBuilder<List<Appointment>>(
        stream: bookingService.watchMine(),
        builder: (context, snap) {
          final list = snap.data ?? const <Appointment>[];
          final now = DateTime.now();
          final upcoming = list.where((a) => !a.end.isBefore(now) && a.status != AppointmentStatus.annullato).toList();
          final past = list.where((a) => !upcoming.contains(a)).toList().reversed.toList();
          return Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (snap.hasError) Text('Impossibile caricare le prenotazioni: ${snap.error}', style: const TextStyle(color: Colors.red)),
              if (!snap.hasData && !snap.hasError) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              if (snap.hasData && list.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text(
                  'Nessuna prenotazione collegata a questo account. Se hai prenotato senza email, in farmacia vale il codice che ti è stato mostrato.',
                  textAlign: TextAlign.center)),
              if (upcoming.isNotEmpty) ...[
                const Text('Prossime', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Brand.primary)),
                for (final a in upcoming) _BookingTile(a),
              ],
              if (past.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Precedenti', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Brand.primary)),
                for (final a in past) _BookingTile(a),
              ],
            ]),
          ));
        },
      ),
    );
  }
}

class _BookingTile extends StatelessWidget {
  const _BookingTile(this.a);
  final Appointment a;

  Future<void> _cancel(BuildContext context) async {
    final m = ScaffoldMessenger.of(context);
    if (!a.clientMayCancel()) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Annullamento non consentito'),
          content: const Text(
            'Non è possibile annullare la prenotazione a meno di 24 ore dall\'inizio. Contatta la farmacia.',
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Ho capito'))],
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Annullare la prenotazione?'),
        content: Text(
          a.pagato
              ? 'Confermi l\'annullamento di ${a.service.name}? Essendo pagata, la farmacia gestirà il rimborso.'
              : 'Confermi l\'annullamento di ${a.service.name} del ${a.start.day.toString().padLeft(2, '0')}/${a.start.month.toString().padLeft(2, '0')} alle ${hhmm(a.start)}?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Indietro')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(c, true), child: const Text('Annulla prenotazione')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await bookingService.cancel(a, asStaff: false);
      m.showSnackBar(SnackBar(content: Text(a.pagato ? 'Prenotazione annullata. La farmacia provvederà al rimborso.' : 'Prenotazione annullata.')));
    } on StateError catch (e) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Annullamento non consentito'),
          content: Text(e.message),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Ho capito'))],
        ),
      );
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('Annullamento non riuscito: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = a.shortCode;
    final when = '${a.start.day.toString().padLeft(2, '0')}/${a.start.month.toString().padLeft(2, '0')}/${a.start.year} · ${hhmm(a.start)}';
    final status = switch (a.effectiveStatus()) {
      AppointmentStatus.inAttesa => 'In attesa',
      AppointmentStatus.confermato => 'Confermata',
      AppointmentStatus.annullato => 'Annullata',
      AppointmentStatus.completato => 'Completata',
    };
    final canCancel = a.clientShowsCancel();
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(
            title: Text(a.service.name, style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.primary)),
            subtitle: Text('$when\nCodice $code · $status${a.pagato ? ' · Pagato' : ''}${a.esenzione ? ' · Con esenzione' : ''}'),
            isThreeLine: true,
          ),
          if (canCancel)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () => apriRiprogramma(context, a),
                  icon: const Icon(Icons.event_repeat),
                  label: const Text('Riprogramma'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () => _cancel(context),
                  icon: const Icon(Icons.close),
                  label: const Text('Annulla'),
                ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
