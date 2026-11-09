import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../models/personal_role.dart';
import '../../theme/brand.dart';
import '../staff/staff_hub.dart';
import 'my_bookings.dart';

/// Apre il login oppure, se la sessione c'è già, l'area giusta (cliente o staff).
Future<void> openPersonalArea(BuildContext context) async {
  final user = customerAuth.user;
  if (user == null || user.isAnonymous) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerLogin()));
    return;
  }
  try {
    final session = await customerAuth.sessionForCurrentUser();
    if (!context.mounted) return;
    final page = session.role == PersonalRole.staff && session.employee != null
        ? StaffHub(employee: session.employee!)
        : const MyBookings();
    await Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => page), (route) => false);
  } on StateError catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Accesso non riuscito')));
  }
}

class CustomerLogin extends StatefulWidget {
  const CustomerLogin({super.key});
  @override
  State<CustomerLogin> createState() => _CustomerLoginState();
}

class _CustomerLoginState extends State<CustomerLogin> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _checking = true;
  bool _staySignedIn = true;
  String? _err;
  String? _signedEmail;

  @override
  void initState() {
    super.initState();
    _resumeIfSignedIn();
  }

  Future<void> _resumeIfSignedIn() async {
    try {
      final user = await customerAuth.restoredUser();
      if (!mounted) return;
      if (user != null && !user.isAnonymous) {
        final session = await customerAuth.sessionForCurrentUser();
        if (!mounted) return;
        if (session.role == PersonalRole.staff && session.employee != null) {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => StaffHub(employee: session.employee!)), (route) => false);
          return;
        }
        // Cliente già connesso: mostriamo con quale account, senza intrappolarlo.
        setState(() { _signedEmail = user.email ?? ''; _checking = false; });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _login() async {
    setState(() { _busy = true; _err = null; });
    try {
      final session = await customerAuth.signIn(_email.text.trim(), _pass.text, staySignedIn: _staySignedIn);
      if (!mounted) return;
      final next = session.role == PersonalRole.staff && session.employee != null
          ? StaffHub(employee: session.employee!)
          : const MyBookings();
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => next), (route) => false);
    } on FirebaseAuthException catch (e) {
      setState(() => _err = e.code == 'invalid-credential' || e.code == 'wrong-password' || e.code == 'user-not-found'
          ? 'Email o password errate' : 'Accesso non riuscito (${e.code})');
    } on StateError catch (e) {
      setState(() => _err = e.message);
    } catch (e) {
      setState(() => _err = 'Accesso non riuscito: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Brand.primary)));
    }
    return Scaffold(
      appBar: const BrandAppBar(subtitle: 'Accedi'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
            const Icon(Icons.person_outline, size: 48, color: Brand.primary),
            const SizedBox(height: 8),
            const Text('Accedi al tuo spazio', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Brand.primary)),
            const SizedBox(height: 4),
            const Text('Un solo accesso per tutti. In base al tuo account vedi le prenotazioni (cliente) oppure l\'area farmacia (staff e admin).',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (_signedEmail != null) Card(
              color: const Color(0xFFF1F5F9),
              child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Sei connesso come ${_signedEmail!}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  FilledButton(onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MyBookings()), (r) => false),
                      child: const Text('Continua')),
                  OutlinedButton(onPressed: () async {
                    await customerAuth.signOut();
                    if (mounted) setState(() => _signedEmail = null);
                  }, child: const Text('Esci e cambia account')),
                ]),
              ])),
            ),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: _pass, obscureText: true, autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: 'Password'), onSubmitted: (_) => _login()),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: Brand.primary,
              value: _staySignedIn,
              onChanged: _busy ? null : (v) => setState(() => _staySignedIn = v ?? true),
              title: const Text('Resta connesso', style: TextStyle(fontWeight: FontWeight.w700, color: Brand.primary)),
              subtitle: const Text('Attivo di default: chiudi pure il browser, al ritorno trovi le tue prenotazioni.'),
            ),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 24),
            SizedBox(height: 56, child: FilledButton(onPressed: _busy ? null : _login,
                child: _busy ? const CircularProgressIndicator() : const Text('Entra', style: TextStyle(fontSize: 18)))),
          ]),
        ),
      ),
    );
  }
}
