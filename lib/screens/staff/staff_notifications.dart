import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../models/appointment.dart';
import '../../services/booking_service.dart';
import '../../theme/brand.dart';
import 'ricetta_info.dart';

String _fmt(DateTime? t) => t == null ? '' : '${t.day}/${t.month}/${t.year} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Badge con notifiche non lette + rimborsi pending.
class UnreadBadge extends StatelessWidget {
  final Widget child;
  const UnreadBadge({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<List<StaffNotification>>(
      stream: bookingService.watchNotifications(),
      builder: (context, snapN) {
        return StreamBuilder<List<Appointment>>(
          stream: bookingService.watchPendingRefunds(),
          builder: (context, snapR) {
            final unread = (snapN.data ?? const []).where((x) => !x.readByUid(uid)).length;
            final refunds = (snapR.data ?? const []).length;
            final n = unread + refunds;
            return Badge(isLabelVisible: n > 0, label: Text(n > 99 ? '99+' : '$n'), child: child);
          },
        );
      },
    );
  }
}

class StaffNotificationsPage extends StatelessWidget {
  const StaffNotificationsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: const BrandAppBar(subtitle: 'Notifiche'),
      body: StreamBuilder<List<Appointment>>(
        stream: bookingService.watchPendingRefunds(),
        builder: (context, snapR) {
          final refunds = snapR.data ?? const <Appointment>[];
          return StreamBuilder<List<StaffNotification>>(
            stream: bookingService.watchNotifications(),
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Notifiche non disponibili: ${snap.error}')));
              if (!snap.hasData && !snapR.hasData) return const Center(child: CircularProgressIndicator());
              final list = snap.data ?? const <StaffNotification>[];
              if (list.isEmpty && refunds.isEmpty) return const Center(child: Text('Nessuna notifica'));
              final unread = list.where((x) => !x.readByUid(uid)).toList();
              return ListView(padding: const EdgeInsets.all(16), children: [
                if (refunds.isNotEmpty) ...[
                  const Text('Da rimborsare', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF9B2C2C))),
                  const SizedBox(height: 8),
                  for (final a in refunds) Card(
                    color: const Color(0xFFFADBD8).withValues(alpha: 0.45),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Prenotazione ${a.shortCode} annullata — rimborsare / chiamare il cliente',
                            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF9B2C2C))),
                        const SizedBox(height: 6),
                        Text('${a.customerName} · Tel. ${a.phone}${a.service.prezzoFinale != null ? ' · € ${a.service.prezzoFinale!.toStringAsFixed(2)}' : ''}${a.metodoPagamento != null ? ' · ${a.metodoPagamento}' : ''}'),
                        Text('${a.service.name} · appuntamento ${_fmt(a.start)} · annullata da ${a.annullatoDa == 'cliente' ? 'cliente' : 'staff'}'),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF9B2C2C)),
                            onPressed: () => segnaRimborsato(context, a),
                            icon: const Icon(Icons.currency_exchange),
                            label: const Text('Segna rimborsato'),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (list.isNotEmpty) const Text('Prenotazioni e assegnazioni', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Brand.primary)),
                if (unread.isNotEmpty) Align(alignment: Alignment.centerRight, child: TextButton.icon(
                  onPressed: () async { for (final x in unread) { await bookingService.markNotificationRead(x.id); } },
                  icon: const Icon(Icons.done_all), label: const Text('Segna tutte come lette'))),
                for (final x in list)
                  if (!x.isRimborso) Card(
                    color: x.readByUid(uid) ? null : Brand.green.withValues(alpha: 0.08),
                    child: ListTile(
                      leading: Icon(x.readByUid(uid) ? Icons.notifications_none : Icons.notifications_active, color: x.readByUid(uid) ? Colors.black38 : Brand.green),
                      title: Text(x.isAssegnazione ? 'Ti è stato assegnato: ${x.serviceName}' : '${x.serviceName} · ${x.customerName}', style: TextStyle(fontWeight: x.readByUid(uid) ? FontWeight.w500 : FontWeight.w800)),
                      subtitle: Text('Appuntamento: ${_fmt(x.start)}${x.createdAt != null ? '\nRicevuta: ${_fmt(x.createdAt)}' : ''}'),
                      isThreeLine: x.createdAt != null,
                      onTap: x.readByUid(uid) ? null : () => bookingService.markNotificationRead(x.id),
                    ),
                  ),
              ]);
            },
          );
        },
      ),
    );
  }
}
