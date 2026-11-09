import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../app.dart';
import '../models/personal_role.dart';
import '../widgets/brand_loader.dart';
import 'client/my_bookings.dart';
import 'role_picker.dart';
import 'staff/staff_hub.dart';

/// Loader con logo finché utente + token + ruolo non sono pronti, poi l'area
/// giusta. Non esce mai finché c'è un utente reale: riprova all'infinito.
class SessionGate extends StatefulWidget {
  const SessionGate({super.key});
  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  Widget? _page;
  String _msg = 'Accesso in corso…';
  bool _leaving = false;
  StreamSubscription<User?>? _sub;

  bool _real(User? u) => u != null && !u.isAnonymous;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseAuth.instance.authStateChanges().listen((u) {
      // Esce solo se l'utente ha davvero fatto logout (dopo un'attesa).
      if (!_real(u) && _page == null) _maybeLeave();
    });
    _resolve();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _maybeLeave() async {
    await Future.delayed(const Duration(seconds: 8));
    if (!mounted || _leaving || _page != null) return;
    if (_real(FirebaseAuth.instance.currentUser)) return;
    _leaving = true;
    final nav = Navigator.of(context);
    nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RolePicker()), (_) => false);
  }

  Future<void> _resolve() async {
    var attempt = 0;
    while (mounted && !_leaving) {
      attempt++;
      try {
        var u = FirebaseAuth.instance.currentUser;
        if (!_real(u)) {
          u = await FirebaseAuth.instance
              .authStateChanges()
              .firstWhere(_real)
              .timeout(const Duration(seconds: 10));
        }
        await u!.getIdToken(attempt > 3 && attempt % 4 == 0);
        if (mounted && _msg != 'Caricamento area personale…') {
          setState(() => _msg = 'Caricamento area personale…');
        }
        final session = await customerAuth.sessionForCurrentUser();
        if (!mounted) return;
        setState(() => _page = session.role == PersonalRole.staff && session.employee != null
            ? StaffHub(employee: session.employee!)
            : const MyBookings());
        return;
      } catch (_) {
        final ms = (500 * attempt).clamp(500, 3000);
        await Future.delayed(Duration(milliseconds: ms));
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      _page ?? Scaffold(body: BrandLoader(text: _msg, barrierColor: Colors.white));
}
