import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../models/personal_role.dart';
import '../../theme/brand.dart';
import '../staff/staff_hub.dart';
import 'my_bookings.dart';
import '../../widgets/auth_login_form.dart';
import '../../services/password_save.dart';

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
  bool _staySignedIn = false;
  String? _err;
  String? _signedEmail;

  @override
  void initState() {
    super.initState();
    _resumeIfSignedIn();
  }

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _prefillSavedPassword() async {
    final saved = await getSavedBrowserPassword();
    if (!mounted || saved == null) return;
    if (_email.text.trim().isEmpty) _email.text = saved.email;
    if (_pass.text.isEmpty) _pass.text = saved.password;
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
    await _prefillSavedPassword();
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _login() async {
    setState(() { _busy = true; _err = null; });
    try {
      final email = _email.text.trim();
      final password = _pass.text;
      final session = await customerAuth.signIn(email, password, staySignedIn: _staySignedIn);
      await storeBrowserPassword(email, password);
      AuthLoginForm.markSaved();
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
            AuthLoginForm(
              email: _email,
              password: _pass,
              busy: _busy,
              onSubmit: _login,
              footer: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Brand.primary,
                value: _staySignedIn,
                onChanged: _busy ? null : (v) => setState(() => _staySignedIn = v ?? false),
                title: const Text('Resta connesso', style: TextStyle(fontWeight: FontWeight.w700, color: Brand.primary)),
                subtitle: const Text('Solo per i clienti, sul tuo dispositivo. Non usarlo sui computer della farmacia: alla chiusura del browser resti comunque collegato.'),
              ),
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
