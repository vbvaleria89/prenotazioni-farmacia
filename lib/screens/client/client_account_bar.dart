import 'dart:async';
import '../account/edit_account.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../models/customer_bookings.dart';
import '../../models/personal_role.dart';
import '../../theme/brand.dart';
import 'customer_login.dart';
import 'my_bookings.dart';

/// In cima alle schermate cliente: pulsante di accesso se sei fuori, «Ciao, nome» se sei dentro.
class ClientAccountBar extends StatefulWidget {
  /// Solo la home pubblica offre il pulsante «Area personale». Slot e conferma no.
  final bool offerLogin;
  const ClientAccountBar({super.key, this.offerLogin = false});

  @override
  State<ClientAccountBar> createState() => _ClientAccountBarState();
}

class _ClientAccountBarState extends State<ClientAccountBar> {
  StreamSubscription<User?>? _sub;
  var _ready = false;
  var _isCustomer = false;
  var _name = '';
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    final current = customerAuth.user;
    _ready = current == null || current.isAnonymous;
    _sub = FirebaseAuth.instance.authStateChanges().listen(_onUser);
  }

  Future<void> _onUser(User? user) async {
    final generation = ++_generation;
    if (!mounted) return;
    if (user == null || user.isAnonymous) {
      setState(() {
        _isCustomer = false;
        _name = '';
        _ready = true;
      });
      return;
    }
    setState(() => _ready = false);
    try {
      final session = await customerAuth.sessionForCurrentUser();
      if (!mounted || generation != _generation) return;
      if (session.role != PersonalRole.customer) {
        setState(() {
          _isCustomer = false;
          _ready = true;
        });
        return;
      }
      final profile = await customerAuth.profile();
      if (!mounted || generation != _generation) return;
      setState(() {
        _isCustomer = true;
        _name = customerGreeting(nome: profile?.nome, displayName: user.displayName, email: user.email);
        _ready = true;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _isCustomer = false;
        _ready = true;
      });
    }
  }

  Future<void> _account() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const EditAccountPage()));
    if (mounted) await _onUser(customerAuth.user);
  }

  Future<void> _logout() async {
    await customerAuth.signOut();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Brand.primary))),
      );
    }
    if (_isCustomer) return _signedIn();
    if (widget.offerLogin) return _loginCta();
    return const SizedBox.shrink();
  }

  Widget _signedIn() {
    final initial = _name.isEmpty ? '?' : _name[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(children: [
        Expanded(
          child: Material(
            color: Colors.white,
            elevation: 1,
            shadowColor: Brand.primary.withValues(alpha: 0.2),
            shape: const StadiumBorder(side: BorderSide(color: Color(0x2232448C))),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBookings())),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
                child: Row(children: [
                  CircleAvatar(radius: 18, backgroundColor: Brand.primary, child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
                  const SizedBox(width: 10),
                  Flexible(child: Text('Ciao, $_name', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Brand.primary, fontWeight: FontWeight.w800, fontSize: 17))),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: _account,
          child: const Text('Account'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: _logout,
          style: OutlinedButton.styleFrom(
            foregroundColor: Brand.primary,
            side: BorderSide(color: Brand.primary.withValues(alpha: 0.35)),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: const Text('Esci', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _loginCta() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 60,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Brand.primary,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            onPressed: () => openPersonalArea(context),
            icon: const Icon(Icons.person, size: 26),
            label: const Text('Area personale'),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Entra per vedere le tue prenotazioni. Se resti connesso, al ritorno non devi rifare il login.',
            style: TextStyle(fontSize: 15, height: 1.35, color: Brand.primary)),
      ]),
    );
  }
}
