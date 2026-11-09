import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../models/codice_fiscale.dart';
import '../../models/settings.dart';
import '../../theme/brand.dart';

/// Stessa posizione e stesso percorso per tutti i ruoli; i permessi restano nelle rules.
class EditAccountPage extends StatefulWidget {
  final Employee? employee;
  const EditAccountPage({super.key, this.employee});

  @override
  State<EditAccountPage> createState() => _EditAccountPageState();
}

class _EditAccountPageState extends State<EditAccountPage> {
  final _form = GlobalKey<FormState>();
  final _passwordForm = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _cf = TextEditingController();
  final _oldPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _loading = true, _saving = false, _passwordBusy = false;
  String? _error;
  String _email = '', _role = '';
  bool get _staff => widget.employee != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (_staff) {
        final p = await staffAuth.profile();
        if (!mounted) return;
        if (p == null) throw StateError('Profilo dipendente non disponibile. Contatta l’amministratore.');
        _name.text = p.nome;
        _email = p.email;
        _role = p.isAdmin ? 'Amministratore' : (p.ruolo == 'tricologo' ? 'Tricologo' : 'Staff');
      } else {
        final p = await customerAuth.profile();
        if (!mounted) return;
        if (p == null) throw StateError('Profilo non disponibile. Riprova.');
        _name.text = p.nome;
        _phone.text = p.telefono;
        _cf.text = p.codiceFiscale;
        _email = p.email;
      }
    } catch (_) {
      _error = 'Impossibile caricare il profilo. Riprova o contatta l’amministratore.';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (_staff) {
        await staffAuth.updateProfile(nome: _name.text);
      } else {
        await customerAuth.updateProfile(nome: _name.text, telefono: _phone.text, codiceFiscale: _cf.text);
      }
      _message('Dati account salvati');
    } catch (_) {
      _message('Salvataggio non riuscito. Controlla la connessione e riprova.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    if (!_passwordForm.currentState!.validate()) return;
    setState(() => _passwordBusy = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.isAnonymous || user.email == null) throw StateError('Accedi al tuo account');
      // Ri-autenticazione obbligatoria: funziona anche per gli account staff con email .local.
      await user.reauthenticateWithCredential(EmailAuthProvider.credential(email: user.email!, password: _oldPassword.text));
      await user.updatePassword(_newPassword.text);
      if (mounted) {
        _oldPassword.clear();
        _newPassword.clear();
        _confirmPassword.clear();
      }
      if (!_staff) {
        // La password è già cambiata: un errore nel promemoria non deve indicare il contrario.
        try { await customerAuth.markPasswordChanged(); } catch (_) {}
      }
      _message('Password cambiata. Al prossimo accesso usa la nuova password.');
    } on FirebaseAuthException catch (e) {
      _message(switch (e.code) {
        'wrong-password' || 'invalid-credential' => 'Password attuale non corretta.',
        'weak-password' || 'password-does-not-meet-requirements' => 'La nuova password non soddisfa i requisiti di sicurezza.',
        'too-many-requests' => 'Troppi tentativi. Attendi qualche minuto e riprova.',
        'network-request-failed' => 'Connessione non disponibile. Riprova.',
        _ => 'Cambio password non riuscito. Accedi di nuovo e riprova.',
      });
    } catch (_) {
      _message('Cambio password non riuscito. Accedi di nuovo e riprova.');
    } finally {
      if (mounted) setState(() => _passwordBusy = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _cf, _oldPassword, _newPassword, _confirmPassword]) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loginEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    final busy = _saving || _passwordBusy;
    return Scaffold(
      appBar: const BrandAppBar(subtitle: 'Il mio account'),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : _error != null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)),
            OutlinedButton(onPressed: _load, child: const Text('Riprova')),
          ]))
        : Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600), child: ListView(
          padding: const EdgeInsets.all(20), children: [
            const Text('Il mio account', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Brand.primary)),
            const SizedBox(height: 20),
            Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(initialValue: _email, readOnly: true,
                decoration: const InputDecoration(labelText: 'Email di contatto', border: OutlineInputBorder(), helperText: 'Per correggere l’email rivolgiti in farmacia.')),
              if (loginEmail != _email) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Email di accesso: $loginEmail (invariata)')),
              if (_staff) ...[
                const SizedBox(height: 16),
                TextFormField(initialValue: _role, readOnly: true, decoration: const InputDecoration(labelText: 'Ruolo', border: OutlineInputBorder())),
              ],
              const SizedBox(height: 16),
              TextFormField(controller: _name, enabled: !busy, maxLength: 99, textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nome e cognome', border: OutlineInputBorder()),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Inserisci nome e cognome' : null),
              if (!_staff) ...[
                const SizedBox(height: 12),
                TextFormField(controller: _phone, enabled: !busy, maxLength: 29, keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Telefono', border: OutlineInputBorder()),
                  validator: (v) => (v ?? '').trim().length < 6 ? 'Telefono non valido' : null),
                const SizedBox(height: 12),
                TextFormField(controller: _cf, enabled: !busy, textCapitalization: TextCapitalization.characters, autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Codice fiscale', border: OutlineInputBorder()), validator: codiceFiscaleError),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: busy ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(_saving ? 'Salvataggio…' : 'Salva dati')),
            ])),
            const SizedBox(height: 28),
            const Divider(),
            const Text('Cambia password', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Brand.primary)),
            const Text('Inserisci la password attuale per confermare la tua identità. Non serve ricevere un’email.'),
            const SizedBox(height: 16),
            Form(key: _passwordForm, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(controller: _oldPassword, enabled: !busy, obscureText: true, autocorrect: false, enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Password attuale', border: OutlineInputBorder()),
                validator: (v) => (v ?? '').isEmpty ? 'Inserisci la password attuale' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _newPassword, enabled: !busy, obscureText: true, autocorrect: false, enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Nuova password', helperText: 'Almeno 8 caratteri', border: OutlineInputBorder()),
                validator: (v) => (v ?? '').length < 8 ? 'Usa almeno 8 caratteri' : v == _oldPassword.text ? 'Scegli una password diversa dall’attuale' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _confirmPassword, enabled: !busy, obscureText: true, autocorrect: false, enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Ripeti nuova password', border: OutlineInputBorder()),
                validator: (v) => v != _newPassword.text ? 'Le password non coincidono' : null),
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: busy ? null : _changePassword, icon: const Icon(Icons.lock_outline), label: Text(_passwordBusy ? 'Aggiornamento…' : 'Cambia password')),
            ])),
          ],
        ))),
    );
  }
}
