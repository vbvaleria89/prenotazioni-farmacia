import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../theme/brand.dart';
import 'staff_hub.dart';
import '../../widgets/auth_login_form.dart';
import '../../services/password_save.dart';

class StaffLogin extends StatefulWidget {
  const StaffLogin({super.key});
  @override
  State<StaffLogin> createState() => _StaffLoginState();
}

class _StaffLoginState extends State<StaffLogin> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _prefillSavedPassword();
  }

  Future<void> _prefillSavedPassword() async {
    final saved = await getSavedBrowserPassword();
    if (!mounted || saved == null) return;
    if (_email.text.trim().isEmpty) _email.text = saved.email;
    if (_pass.text.isEmpty) _pass.text = saved.password;
    setState(() {});
  }

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _busy = true; _err = null; });
    try {
      final email = _email.text.trim();
      final password = _pass.text;
      final e = await staffAuth.signIn(email, password);
      await storeBrowserPassword(email, password);
      AuthLoginForm.markSaved();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => StaffHub(employee: e)), (route) => false);
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
    return Scaffold(
      appBar: const BrandAppBar(subtitle: 'Riservato al personale'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
            const Icon(Icons.lock_outline, size: 48, color: Brand.primary),
            const SizedBox(height: 8),
            const Text('Accesso personale farmacia', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Brand.primary)),
            const SizedBox(height: 4),
            const Text('Area riservata a staff e amministrazione.\nPer prenotare non serve accedere.', textAlign: TextAlign.center),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Torna alla prenotazione')),
            const SizedBox(height: 8),
            AuthLoginForm(email: _email, password: _pass, busy: _busy, onSubmit: _login),
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
