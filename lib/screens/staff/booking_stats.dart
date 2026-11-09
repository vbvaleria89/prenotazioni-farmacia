import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../app.dart';
import '../../models/appointment.dart';
import '../../models/settings.dart';

/// Solo admin: quante prenotazioni ha creato ciascuna utenza (createdBy == employees/{uid}),
/// oggi e nel mese corrente, esclusi annullati.
class AssegnazioniPage extends StatelessWidget {
  const AssegnazioniPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assegnazioni'), backgroundColor: const Color(0xFF32448C), foregroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(16), children: const [
        Text('Prenotazioni create da ciascuna utenza per i clienti (esclusi annullati).',
            style: TextStyle(fontSize: 15)),
        SizedBox(height: 12),
        Align(alignment: Alignment.centerLeft, child: _AddAccountButton()),
        SizedBox(height: 12),
        BookingStats(),
      ]),
    );
  }
}

class BookingStats extends StatelessWidget {
  const BookingStats({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final m0 = DateTime(now.year, now.month);
    final m1 = DateTime(now.year, now.month + 1);
    final d0 = DateTime(now.year, now.month, now.day);
    final d1 = d0.add(const Duration(days: 1));
    return StreamBuilder<List<Appointment>>(
      stream: bookingService.watchRange(m0, m1),
      builder: (context, snap) {
        if (snap.hasError) return Text('Conteggi non disponibili: ${snap.error}');
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = snap.data!.where((a) => a.status != AppointmentStatus.annullato).toList();
        bool today(Appointment a) => !a.start.isBefore(d0) && a.start.isBefore(d1);
        (int, int) count(bool Function(Appointment) f) {
          final l = all.where(f);
          return (l.where(today).length, l.length);
        }
        Widget row(String name, String? sub, (int, int) c, {bool bold = false}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: TextStyle(fontSize: 16, fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
                  if (sub != null) Text(sub, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                ])),
                SizedBox(width: 70, child: Text('${c.$1}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                SizedBox(width: 70, child: Text('${c.$2}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF32448C)))),
              ]),
            );
        final header = Row(children: const [
          Expanded(child: Text('Utenza', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF32448C)))),
          SizedBox(width: 70, child: Text('Oggi', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
          SizedBox(width: 70, child: Text('Mese', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
        ]);
        return StreamBuilder<List<Employee>>(
          stream: staffAuth.employees(),
          builder: (context, es) {
            final emps = es.data ?? const <Employee>[];
            final known = emps.map((e) => e.id).toSet();
            String ruolo(Employee e) => e.isAdmin ? 'Admin' : (e.ruolo == 'staff' ? 'Staff' : e.ruolo);
            return Card(
              color: const Color(0xFFEFF2FA),
              child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
                header, const Divider(height: 8),
                for (final e in emps)
                  row(e.nome.isEmpty ? e.email : e.nome, '${e.email} · ${ruolo(e)}', count((a) => a.createdBy == e.id)),
                const Divider(height: 8),
                row('Clienti online / altro', 'Prenotazioni non create da un dipendente', count((a) => !known.contains(a.createdBy))),
                row('Totale farmacia', null, count((_) => true), bold: true),
              ])),
            );
          },
        );
      },
    );
  }
}


class _AddAccountButton extends StatelessWidget {
  const _AddAccountButton();
  @override
  Widget build(BuildContext context) => FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF32448C)),
        icon: const Icon(Icons.person_add),
        label: const Text('Aggiungi account'),
        onPressed: () => showDialog(context: context, barrierDismissible: false, builder: (_) => const _AddAccountDialog()),
      );
}

/// Crea utente Auth + employees/{uid} tramite Netlify Function (Admin SDK): la sessione admin resta attiva.
class _AddAccountDialog extends StatefulWidget {
  const _AddAccountDialog();
  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  final _form = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _email = TextEditingController();
  String _ruolo = 'staff';
  bool _attivo = true;
  bool _busy = false;
  String? _error;
  String? _password;

  static const _errors = {
    'email_exists': 'Esiste già un account con questa email.',
    'forbidden': 'Solo un amministratore può creare account.',
    'unauthenticated': 'Sessione scaduta: esci e accedi di nuovo.',
    'bad_request': 'Dati non validi.',
    'not_configured': 'Servizio non configurato sul server.',
  };

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final r = await http.post(Uri.parse('/api/create-employee'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${token ?? ''}'},
          body: jsonEncode({'nome': _nome.text.trim(), 'email': _email.text.trim(), 'ruolo': _ruolo, 'attivo': _attivo}))
          .timeout(const Duration(seconds: 25));
      final b = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode == 200 && b['ok'] == true) {
        setState(() => _password = b['password'] as String);
      } else {
        setState(() => _error = _errors[b['error']] ?? 'Creazione non riuscita (${b['error'] ?? r.statusCode}).');
      }
    } catch (e) {
      setState(() => _error = 'Creazione non riuscita: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_password != null) {
      return AlertDialog(
        title: const Text('Account creato'),
        content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Email: ${_email.text.trim()}'),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Password temporanea: '),
            SelectableText(_password!, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 16)),
            IconButton(tooltip: 'Copia', icon: const Icon(Icons.copy, size: 18),
                onPressed: () => Clipboard.setData(ClipboardData(text: _password!))),
          ]),
          const SizedBox(height: 8),
          const Text('Annotala ora e comunicala al collega: non verrà più mostrata.', style: TextStyle(color: Colors.black54)),
        ])),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Chiudi'))],
      );
    }
    return AlertDialog(
      title: const Text('Nuovo account personale'),
      content: SizedBox(width: 440, child: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: _nome, decoration: const InputDecoration(labelText: 'Nome'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Obbligatorio' : null),
        TextFormField(controller: _email, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress,
            validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Email non valida'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _ruolo,
          decoration: const InputDecoration(labelText: 'Ruolo'),
          items: const [
            DropdownMenuItem(value: 'staff', child: Text('Staff')),
            DropdownMenuItem(value: 'tricologo', child: Text('Tricologo')),
            DropdownMenuItem(value: 'admin', child: Text('Amministratore')),
          ],
          onChanged: (v) => setState(() => _ruolo = v ?? 'staff'),
        ),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Attivo'), value: _attivo,
            onChanged: (v) => setState(() => _attivo = v)),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      ]))),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Annulla')),
        FilledButton(onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Crea account')),
      ],
    );
  }
}
