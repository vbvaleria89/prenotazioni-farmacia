import '../client/notice_flyer.dart';
import '../account/edit_account.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../../app.dart';
import '../../models/settings.dart';
import '../../theme/brand.dart';
import '../client/services_home.dart';
import '../role_picker.dart';
import 'backoffice.dart';
import 'availability_page.dart';
import 'booking_stats.dart';
import 'staff_calendar.dart';
import 'staff_list.dart';
import 'staff_notices.dart';
import 'staff_notifications.dart';
import 'staff_today.dart';
import '../../widgets/staff_idle_guard.dart';
import '../../services/auth_persistence.dart';

/// Home staff/admin: griglia di tasti grandi, pensata per il desktop.
class StaffHub extends StatefulWidget {
  final Employee employee;
  const StaffHub({super.key, required this.employee});
  @override
  State<StaffHub> createState() => _StaffHubState();
}

class _StaffHubState extends State<StaffHub> {
  Employee? _updatedEmployee;
  @override
  void initState() {
    super.initState();
    unawaited(bookingService.backfillUpcomingBlocks());
    unawaited(bookingService.backfillDeviceHolds());
    // Anche se un vecchio «Resta connesso» era in localStorage, lo staff resta su SESSION.
    unawaited(applyAuthPersistence(staySignedIn: false));
    StaffIdleWatch.instance.activate();
  }

  Future<void> _logout() async {
    StaffIdleWatch.instance.deactivate();
    final nav = Navigator.of(context);
    await staffAuth.signOut();
    nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const RolePicker()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final e = _updatedEmployee ?? widget.employee;
    final tiles = <_HubTile>[
      _HubTile('Oggi', 'Appuntamenti del giorno', Icons.today, Brand.green, () => StaffToday(employee: e)),
      _HubTile('Notifiche', 'Nuove prenotazioni e rimborsi', Icons.notifications, Brand.green, StaffNotificationsPage.new, badge: true),
      _HubTile('Bacheca', e.isAdmin ? 'Qui aggiungi novità, promo, eventi' : 'Qui aggiungi novità ed eventi', Icons.campaign, Brand.primary, StaffNotices.new),
      const _HubTile('Calendario', 'Stanze e giorni', Icons.calendar_month, Brand.primary, StaffCalendar.new),
      const _HubTile('Elenco prenotazioni', 'Tabella con ricerca e azioni', Icons.view_list, Brand.primary, StaffBookingList.new),
      const _HubTile('Nuova prenotazione', 'Per un cliente al banco', Icons.add_circle, Brand.green, _staffBooking),
      if (e.isAdmin) _HubTile('Servizi e orari', 'Backoffice', Icons.tune, Brand.primary, () => Backoffice(employee: e)),
      if (e.isAdmin) const _HubTile('Disponibilità', 'Giorni e fasce prenotabili', Icons.event_available, Brand.primary, AvailabilityPage.new),
      if (e.isAdmin) const _HubTile('Assegnazioni', 'Chi ha creato le prenotazioni', Icons.assignment_ind, Brand.primary, AssegnazioniPage.new),
      _HubTile('Novità', 'Gestisci e aggiungi', Icons.campaign_outlined, Brand.green, () => const NoticeListScreen(tipo: 'novita', title: 'Novità', canManage: true)),
      if (e.isAdmin) _HubTile('Promo', 'Gestisci e aggiungi', Icons.local_offer_outlined, Brand.green, () => const NoticeListScreen(tipo: 'promo', title: 'Promo', canManage: true)),
      _HubTile('Eventi', 'Gestisci e aggiungi', Icons.celebration_outlined, Brand.green, () => const NoticeListScreen(tipo: 'evento', title: 'Eventi', canManage: true)),
    ];
    return Scaffold(
      appBar: BrandAppBar(subtitle: e.isAdmin ? 'Area amministratore' : 'Area staff', implyLeading: false),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 28), children: [
        Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
          Chip(
            avatar: Icon(e.isAdmin ? Icons.admin_panel_settings : Icons.badge, size: 18, color: Colors.white),
            backgroundColor: e.isAdmin ? Brand.primary : Brand.green,
            label: Text('${e.nome} · ${e.isAdmin ? 'Admin' : 'Staff'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => EditAccountPage(employee: e)));
              try {
                final profile = await staffAuth.profile();
                if (mounted && profile != null) setState(() => _updatedEmployee = profile);
              } catch (_) {}
            },
            icon: const Icon(Icons.manage_accounts_outlined),
            label: const Text('Account'),
          ),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('Esci', style: TextStyle(fontSize: 16)),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Buongiorno', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Brand.primary, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 1100 ? 4 : c.maxWidth >= 760 ? 3 : 2;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: cols >= 3 ? 1.45 : 1.15,
            children: [for (final t in tiles) _HubCard(t)],
          );
        }),
      ]),
    );
  }
}

class _HubTile {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget Function() page;
  final bool badge;
  const _HubTile(this.title, this.subtitle, this.icon, this.color, this.page, {this.badge = false});
}

Widget _staffBooking() => const ServicesHome(fromStaff: true);

class _HubCard extends StatelessWidget {
  final _HubTile tile;
  const _HubCard(this.tile);
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shadowColor: Brand.primary.withValues(alpha: 0.16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => tile.page())),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            tile.badge ? const UnreadBadge(child: Icon(Icons.notifications, size: 40, color: Brand.green)) : Icon(tile.icon, size: 40, color: tile.color),
            const SizedBox(height: 12),
            Text(tile.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Brand.primary, height: 1.1)),
            const SizedBox(height: 6),
            Text(tile.subtitle, style: const TextStyle(fontSize: 15, color: Colors.black54)),
          ]),
        ),
      ),
    );
  }
}
