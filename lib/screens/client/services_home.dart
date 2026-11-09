import '../account/edit_account.dart';
import '../../theme/brand.dart';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../models/service_type.dart';
import 'slot_picker.dart';
import 'customer_login.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/personal_role.dart';

class ServicesHome extends StatefulWidget {
  final bool fromStaff;
  const ServicesHome({super.key, this.fromStaff = false});
  @override
  State<ServicesHome> createState() => _ServicesHomeState();
}

class _ServicesHomeState extends State<ServicesHome> {
  StreamSubscription<User?>? _sub;
  var _isCustomer = false;
  var _name = '';
  var _email = '';
  var _gen = 0;

  bool get fromStaff => widget.fromStaff;

  @override
  void initState() {
    super.initState();
    if (!fromStaff) _sub = FirebaseAuth.instance.authStateChanges().listen(_onUser);
  }

  Future<void> _onUser(User? user) async {
    final g = ++_gen;
    if (user == null || user.isAnonymous) {
      if (mounted) setState(() { _isCustomer = false; _name = ''; _email = ''; });
      return;
    }
    try {
      final session = await customerAuth.sessionForCurrentUser();
      if (!mounted || g != _gen) return;
      if (session.role != PersonalRole.customer) { setState(() => _isCustomer = false); return; }
      final profile = await customerAuth.profile();
      if (!mounted || g != _gen) return;
      final n = (profile?.nome ?? '').trim();
      setState(() {
        _isCustomer = true;
        _name = n.isNotEmpty ? n.split(' ').first : (user.displayName ?? '');
        _email = user.email ?? '';
      });
    } catch (_) {
      if (mounted && g == _gen) setState(() => _isCustomer = false);
    }
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandAppBar(subtitle: 'Prenota un servizio', actions: [
        if (!fromStaff && _isCustomer)
          IconButton(tooltip: 'Il mio account', icon: const Icon(Icons.manage_accounts_outlined), onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const EditAccountPage()));
            if (mounted) await _onUser(FirebaseAuth.instance.currentUser);
          }),
        if (!fromStaff && _isCustomer)
          IconButton(tooltip: 'Esci', onPressed: () async { await customerAuth.signOut(); }, icon: const Icon(Icons.logout, color: Colors.white)),
        if (!fromStaff && !_isCustomer) TextButton.icon(
          onPressed: () => openPersonalArea(context),
          icon: const Icon(Icons.person_outline, size: 22),
          label: const Text('Accedi'),
          style: TextButton.styleFrom(foregroundColor: Colors.white),
        ),
      ]),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (!fromStaff && _isCustomer) Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_name.isEmpty ? 'Ciao!' : 'Ciao, $_name', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Brand.primary)),
              if (_email.isNotEmpty) Text(_email, style: const TextStyle(fontSize: 13, color: Colors.black54)),
            ]),
          ),
          if (!fromStaff) const _Hero(),
          const Padding(padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Text('Scegli il servizio', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Brand.primary))),
          StreamBuilder<List<ServiceType>>(
            stream: bookingService.watchActiveServices(),
            builder: (context, snap) {
              if (snap.hasError) return Padding(padding: const EdgeInsets.all(24), child: Text('Errore nel caricamento dei servizi: ${snap.error}'));
              if (!snap.hasData) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
              final list = snap.data!;
              if (list.isEmpty) return const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Nessun servizio prenotabile al momento')));
              return Column(children: [for (final s in list) _ServiceCard(s, fromStaff: fromStaff)]);
            },
          ),
        ],
      ),
    );
  }
}

const _gg = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];

class _Hero extends StatelessWidget {
  const _Hero();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Brand.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset(Brand.logo, width: 32, height: 32, fit: BoxFit.cover)),
        const SizedBox(width: 10),
        const Expanded(child: Text(Brand.motto, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Brand.primary, fontSize: 14, fontWeight: FontWeight.w600, height: 1.25))),
      ]),
    );
  }
}

IconData _serviceIcon(ServiceType s) {
  final key = '${s.id} ${s.name}'.toLowerCase();
  if (key.contains('trico') || key.contains('capell')) return Icons.spa_outlined;
  if (key.contains('holter') || key.contains('cardio') || key.contains('pressor')) return Icons.monitor_heart_outlined;
  if (key.contains('analisi') || key.contains('glic') || key.contains('sang')) return Icons.biotech_outlined;
  return Icons.medical_services_outlined;
}

class _ServiceCard extends StatelessWidget {
  final ServiceType s;
  final bool fromStaff;
  const _ServiceCard(this.s, {this.fromStaff = false});
  @override
  Widget build(BuildContext context) {
    final days = s.giorni.isEmpty ? '' : ' · ${(s.giorni.toList()..sort()).map((d) => _gg[d - 1]).join(', ')}';
    Widget? price;
    if (s.prezzo != null) {
      price = Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (s.scontato)
          Text(euro(s.prezzo!), style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey, fontSize: 13)),
        Text(euro(s.prezzoFinale!), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: s.scontato ? Brand.green : Brand.primary)),
      ]);
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      elevation: 1,
      shadowColor: Brand.primary.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SlotPicker(service: s, fromStaff: fromStaff))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: Brand.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
              child: Icon(_serviceIcon(s), color: Brand.primary, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(s.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Brand.primary, height: 1.2))),
                if (s.scontato) Padding(padding: const EdgeInsets.only(left: 8), child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Brand.green, borderRadius: BorderRadius.circular(20)),
                  child: const Text('PROMO', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                )),
              ]),
              if (s.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(s.description, style: const TextStyle(fontSize: 15, height: 1.3))),
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('${s.duration.inMinutes} min$days', style: const TextStyle(fontSize: 14, color: Colors.black54))),
            ])),
            if (price != null) Padding(padding: const EdgeInsets.only(left: 8), child: price),
            const Icon(Icons.chevron_right, color: Brand.primary),
          ]),
        ),
      ),
    );
  }
}
