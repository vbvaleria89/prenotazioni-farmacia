import 'package:flutter/material.dart';
import '../../app.dart';
import '../../models/notice.dart';
import 'slot_picker.dart';
import '../../services/notice_service.dart';
import '../../theme/brand.dart';
import 'notice_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../staff/staff_notices.dart';

/// true se l'utente loggato è un admin attivo (employees/{uid}).
Future<bool> _isAdmin() async {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null || u.isAnonymous) return false;
  try {
    final d = await FirebaseFirestore.instance.doc('employees/${u.uid}').get();
    final r = (d.data()?['ruolo'] ?? '').toString().trim().toLowerCase();
    return d.exists && (r == 'admin' || r == 'staff' || r == 'tricologo') && d.data()?['attivo'] != false;
  } catch (e) { debugPrint('_isAdmin: $e'); return false; }
}

/// Volantino in Area personale: solo voci attive e nel periodo.
class NoticeFlyer extends StatelessWidget {
  const NoticeFlyer({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Notice>>(
      stream: noticeBoard.watchActive(),
      builder: (context, snap) {
        if (snap.hasError || !snap.hasData) return const SizedBox.shrink();
        final list = liveNotices(snap.data!, DateTime.now());
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Novità in farmacia', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Brand.primary)),
          const SizedBox(height: 8),
          SizedBox(
            height: 300,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _FlyerCard(list[i]),
            ),
          ),
        ]);
      },
    );
  }
}

class _FlyerCard extends StatelessWidget {
  final Notice notice;
  const _FlyerCard(this.notice);

  @override
  Widget build(BuildContext context) {
    final when = _when(notice);
    return SizedBox(
      width: 280,
      child: Card(
        elevation: 1,
        shadowColor: Brand.primary.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (notice.imageUrl.isNotEmpty) SizedBox(height: 110, child: NoticeImage(notice.imageUrl)),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: notice.tipo == 'promo' ? Brand.green : Brand.primary, borderRadius: BorderRadius.circular(20)),
                child: Text(notice.tipoLabel, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 8),
              Text(notice.titolo, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Brand.primary, height: 1.15)),
              if (notice.testo.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(notice.testo, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.3))),
              if (when.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(when, style: const TextStyle(fontSize: 13, color: Colors.black54))),
              if (notice.prenotabile) ...[
                const Spacer(),
                SizedBox(width: double.infinity, child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Brand.green),
                  onPressed: () => _book(context, notice),
                  icon: const Icon(Icons.event_available, size: 18),
                  label: const Text('Prenota'),
                )),
              ],
            ]),
          )),
        ]),
      ),
    );
  }
}

Future<void> _book(BuildContext context, Notice n) async {
  final nav = Navigator.of(context);
  final msg = ScaffoldMessenger.of(context);
  try {
    final s = await bookingService.activeServiceById(n.serviceId);
    if (s == null) {
      msg.showSnackBar(const SnackBar(content: Text('Prenotazione non più disponibile per questo evento')));
      return;
    }
    nav.push(MaterialPageRoute(builder: (_) => SlotPicker(service: s)));
  } catch (e) {
    msg.showSnackBar(SnackBar(content: Text('Impossibile aprire la prenotazione: $e')));
  }
}

String _when(Notice n) {
  String d(DateTime x) => '${x.day}/${x.month}';
  if (n.start != null && n.end != null) return '${d(n.start!)} – ${d(n.end!)}';
  if (n.periodo == 'settimana') return 'Questa settimana';
  if (n.periodo == 'mese') return 'Questo mese';
  return '';
}

/// Schermata volantini filtrati per tipo (novita | promo | evento).
class NoticeListScreen extends StatelessWidget {
  const NoticeListScreen({super.key, required this.tipo, required this.title, this.canManage = false});
  final String tipo, title;
  final bool canManage;
  void _openEditor(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => NoticeEditor(initialTipo: tipo)));
  }

  @override
  Widget build(BuildContext context) {
    if (canManage) return _buildBody(context, true, false, FirebaseAuth.instance.currentUser?.email);
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, authSnap) {
        final u = authSnap.data;
        final Stream<DocumentSnapshot<Map<String, dynamic>>>? empStream = (u == null || u.isAnonymous)
            ? null
            : FirebaseFirestore.instance.doc('employees/${u.uid}').snapshots();
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: empStream,
          builder: (context, empSnap) {
            if (empSnap.hasError) debugPrint('NoticeList employees: ${empSnap.error}');
            var isEmp = false;
            try {
              final d = empSnap.hasError ? null : empSnap.data;
              final m = d?.data();
              final r = (m?['ruolo'] ?? '').toString().trim().toLowerCase();
              isEmp = d != null && d.exists && (r == 'admin' || r == 'staff' || r == 'tricologo') && m?['attivo'] != false;
            } catch (e) { debugPrint('NoticeList emp parse: $e'); }
            final admin = canManage || isEmp;
            final loading = !canManage && empStream != null && !empSnap.hasData && !empSnap.hasError;
            return _buildBody(context, admin, loading, u?.email);
          },
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, bool admin, bool loading, String? email) {
    return Builder(
      builder: (context) {
        final addLabel = switch (tipo) { 'evento' => 'Aggiungi evento', 'promo' => 'Aggiungi promo', _ => 'Aggiungi novità' };
        return Scaffold(
          appBar: BrandAppBar(subtitle: title, actions: admin ? [IconButton(tooltip: addLabel, icon: const Icon(Icons.add), onPressed: () => _openEditor(context))] : null),
          floatingActionButton: admin
              ? FloatingActionButton.extended(
                  backgroundColor: Brand.primary,
                  foregroundColor: Colors.white,
                  onPressed: () => _openEditor(context),
                  icon: const Icon(Icons.add),
                  label: Text(addLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                )
              : null,
          body: Column(children: [
            if (loading) const LinearProgressIndicator(minHeight: 3),
            if (email != null && email.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Accesso: $email', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            if (admin)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Chip(avatar: const Icon(Icons.admin_panel_settings, size: 18), label: Text('Gestione · ${email ?? 'staff'}')),
              ),
            if (admin)
              Material(
                color: Brand.primary,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Brand.primary),
                        onPressed: () => _openEditor(context),
                        icon: const Icon(Icons.add),
                        label: Text(addLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: StreamBuilder<List<Notice>>(
                stream: admin ? noticeBoard.watchAll() : noticeBoard.watchActive(),
                builder: (context, snap) {
                  if (snap.hasError) return const Center(child: Text('Impossibile caricare i contenuti'));
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final list = (admin ? snap.data! : liveNotices(snap.data!, DateTime.now())).where((n) => n.tipo == tipo).toList();
                  if (list.isEmpty) {
                    return Center(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('Al momento nessun contenuto in «$title».', textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
                        if (admin) ...[
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: Brand.primary, minimumSize: const Size(240, 52)),
                            onPressed: () => _openEditor(context),
                            icon: const Icon(Icons.add),
                            label: Text(addLabel),
                          ),
                        ],
                      ]),
                    ));
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
                        for (final n in list)
                          SizedBox(
                            width: 280,
                            height: n.prenotabile ? 310 : 260,
                            child: admin
                                ? Stack(children: [
                                    Positioned.fill(child: _FlyerCard(n)),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: IconButton.filled(
                                        tooltip: 'Modifica',
                                        icon: const Icon(Icons.edit),
                                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NoticeEditor(notice: n))),
                                      ),
                                    ),
                                  ])
                                : _FlyerCard(n),
                          ),
                      ]),
                    ],
                  );
                },
              ),
            ),
          ]),
        );
      },
    );
  }
}
