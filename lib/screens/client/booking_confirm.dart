import '../../widgets/brand_loader.dart';
import 'dart:async';

import '../../theme/brand.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../app.dart';
import '../../models/codice_fiscale.dart';
import '../../models/service_type.dart';
import '../../models/customer.dart';
import 'client_account_bar.dart';
import 'slot_picker.dart';
import '../../widgets/device_unavailable_dialog.dart';

class BookingConfirm extends StatefulWidget {
  final ServiceType service;
  final DateTime start;
  final bool fromStaff;
  final bool manualTime;
  /// Staff: persona assegnata (fasce per persona). Mai valorizzata dal cliente.
  final String? employeeId;
  final String? employeeNome;
  const BookingConfirm({super.key, required this.service, required this.start, this.fromStaff = false, this.manualTime = false, this.employeeId, this.employeeNome});
  @override
  State<BookingConfirm> createState() => _BookingConfirmState();
}

class _BookingConfirmState extends State<BookingConfirm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _cf = TextEditingController();
  final _emailFocus = FocusNode();
  bool _clienteTrovato = false;
  Timer? _deb;
  bool _esenzione = false;
  /// null = non pagato; `carta` | `contanti` = pagato con quel metodo (tap unico al banco).
  String? _metodoPagamento;
  final _ricetta = TextEditingController();
  final _note = TextEditingController();
  Uint8List? _foto;
  bool _busy = false;
  String? _loading; // testo overlay globale

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfile());
  }

  Future<void> _loadProfile() async {
    if (widget.fromStaff) return;
    final profile = await customerAuth.profile();
    if (!mounted || profile == null) return;
    if (_name.text.isEmpty && profile.nome.isNotEmpty) _name.text = profile.nome;
    if (_phone.text.isEmpty && profile.telefono.isNotEmpty) _phone.text = profile.telefono;
    if (_email.text.isEmpty && profile.email.isNotEmpty) _email.text = profile.email;
    if (_cf.text.isEmpty && profile.codiceFiscale.isNotEmpty) _cf.text = profile.codiceFiscale;
  }

  Future<void> _pick(ImageSource src) async {
    try {
      // Ridimensionamento/compressione fatti dal browser (canvas) o nativamente: veloce e fuori dal Dart main loop.
      final f = await ImagePicker().pickImage(source: src, maxWidth: 1100, maxHeight: 1100, imageQuality: 45);
      if (f == null) return;
      setState(() => _loading = 'Elaborazione foto…');
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final b = await f.readAsBytes();
      if (mounted) setState(() => _loading = null);
      if (b.length > 650000) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Foto troppo grande, riprova con una foto più leggera')));
        return;
      }
      setState(() => _foto = b);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossibile acquisire la foto')));
    } finally {
      if (mounted && _loading != null) setState(() => _loading = null);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    if (_esenzione && _foto == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Aggiungi la foto della ricetta/impegnativa')));
      return;
    }
    if (_busy) return;
    setState(() { _busy = true; _loading = 'Salvataggio prenotazione…'; });
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;
    final nav = Navigator.of(context);
    try {
      final metodo = widget.fromStaff ? _metodoPagamento : null;
      final a = await bookingService.book(widget.service, widget.start, _name.text.trim(), _phone.text.trim(), codiceFiscale: _cf.text, email: _email.text.trim().isEmpty ? null : _email.text.trim(), esenzione: _esenzione,
          ricettaNumero: _esenzione ? _ricetta.text.trim() : null,
          ricettaNote: _esenzione && _note.text.trim().isNotEmpty ? _note.text.trim() : null,
          ricettaFotoB64: _esenzione && _foto != null ? base64Encode(_foto!) : null,
          pagato: metodo != null,
          metodoPagamento: metodo, manualTime: widget.fromStaff && widget.manualTime,
          employeeId: widget.fromStaff ? widget.employeeId : null, employeeNome: widget.fromStaff ? widget.employeeNome : null);
      if (!mounted) return;
      setState(() => _loading = null);
      final code = a.id.substring(0, 6).toUpperCase();
      // La prenotazione è già salvata: un errore di account o di mail non deve annullarla.
      _MailOutcome? mail;
      if (_email.text.trim().isNotEmpty) {
        try {
          if (mounted) setState(() => _loading = widget.fromStaff ? 'Invio email al cliente…' : 'Invio ricevuta…');
          mail = await _sendMail(code, a.id);
        } catch (_) {
          mail = _MailOutcome(sent: false, manual: widget.fromStaff ? _manualMail(code) : null);
        }
        if (!mounted) return;
        setState(() => _loading = null);
      }
      await _showCode(code, mail: mail);
      nav.popUntil((r) => r.isFirst);
    } on DeviceUnavailableException catch (e) {
      if (mounted) await showDeviceUnavailableDialog(context, e);
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Prenotazione non riuscita. Riprova o chiama la farmacia.')));
    } finally {
      if (mounted) setState(() { _busy = false; _loading = null; });
    }
  }

  String get _quando { final s = widget.start; return '${s.day.toString().padLeft(2, '0')}/${s.month.toString().padLeft(2, '0')}/${s.year} alle ${hhmm(s)}'; }

  String _manualMail(String code) {
    final to = _email.text.trim();
    return 'A: $to\nOggetto: Conferma prenotazione $code – Farmacia San Ciro\n\nGentile ${_name.text.trim()},\nla sua prenotazione è confermata.\nServizio: ${widget.service.name}\nData e ora: $_quando\nCodice: $code\nCodice fiscale: ${normalizeCodiceFiscale(_cf.text)}\nMostri il codice in farmacia.';
  }

  /// Non lancia: la prenotazione è già su Firestore.
  Future<_MailOutcome> _sendMail(String code, String appointmentId) async {
    final to = _email.text.trim();
    try {
      final r = await http.post(Uri.parse('/api/send-confirmation'), headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'to': to,
            'nome': _name.text.trim(),
            'codice': code,
            'servizio': widget.service.name,
            'quando': _quando,
            'appointmentId': appointmentId,
          }))
          .timeout(const Duration(seconds: 25));
      String? account;
      try {
        final decoded = jsonDecode(r.body);
        if (decoded is Map && decoded['account'] is String) account = decoded['account'] as String;
      } catch (_) {}
      if (r.statusCode == 200) return _MailOutcome(sent: true, account: account);
      var manual = widget.fromStaff ? _manualMail(code) : null;
      if (manual != null && account == 'created') {
        manual = '$manual\n\nAccount cliente già creato: se reinvii la conferma, la mail avrà il link per scegliere la password.';
      }
      return _MailOutcome(sent: false, account: account, manual: manual);
    } catch (_) {
      return _MailOutcome(sent: false, manual: widget.fromStaff ? _manualMail(code) : null);
    }
  }

  String? _successNote(_MailOutcome? mail) {
    final email = _email.text.trim();
    if (email.isEmpty) {
      return widget.fromStaff ? 'Nessuna email: ricevuta al banco.' : null;
    }
    if (mail == null || !mail.sent) {
      return widget.fromStaff ? null : 'Prenotazione registrata. Non siamo riusciti a inviare la ricevuta: conserva il codice.';
    }
    final base = 'Email di conferma inviata a $email';
    final extra = switch (mail.account) {
      'created' => widget.fromStaff
          ? 'Account cliente creato: nella email c\'è una password casuale, non il codice fiscale.'
          : 'Nella mail trovi la password temporanea per l\'Area personale. Non è il codice fiscale.',
      'existing' => widget.fromStaff
          ? 'Il cliente aveva già un account: prenotazione collegata, istruzioni nella email.'
          : 'Hai già un account: nella mail ci sono le istruzioni per accedere.',
      'staff' => 'Nessuna password è stata modificata (account del personale).',
      'not_configured' when widget.fromStaff => 'Account cliente non creato: impostare FIREBASE_SERVICE_ACCOUNT su Netlify.',
      'error' when widget.fromStaff => 'Account cliente non creato per un errore Firebase. La prenotazione è valida.',
      _ => null,
    };
    return extra == null ? base : '$base. $extra';
  }

  Future<void> _showCode(String code, {_MailOutcome? mail}) {
    final note = _successNote(mail);
    final manual = mail?.manual;
    final sent = mail?.sent == true;
    return showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Color(0xFF2E9E4F), size: 64),
          title: const Text('Prenotazione confermata', textAlign: TextAlign.center),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Il tuo codice', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.black54)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                color: Brand.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SelectableText(code, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, letterSpacing: 4, color: Brand.primary)),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Codice copiato')));
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copia codice'),
            ),
            Card(
              elevation: 0,
              color: const Color(0xFFF4F6FB),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  Text(widget.service.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Brand.primary)),
                  const SizedBox(height: 4),
                  Text('${widget.start.day}/${widget.start.month}/${widget.start.year} alle ${hhmm(widget.start)}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(_esenzione ? 'Con esenzione' : 'Senza esenzione', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            const Text('Conserva questo codice e mostralo in farmacia.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, height: 1.3)),
            if (note != null) ...[
              const SizedBox(height: 8),
              Text(note, textAlign: TextAlign.center, style: TextStyle(color: sent ? const Color(0xFF2E9E4F) : Colors.deepOrange, fontWeight: FontWeight.w600)),
            ],
            if (manual != null) ...[
              const SizedBox(height: 12),
              const Text('⚠️ Email da inviare al cliente (invio automatico non riuscito):', style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Container(padding: const EdgeInsets.all(8), color: Colors.orange.withValues(alpha: 0.08), child: SelectableText(manual, style: const TextStyle(fontSize: 12))),
              TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: manual)), icon: const Icon(Icons.copy, size: 18), label: const Text('Copia testo email')),
            ],
          ])),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF32448C), minimumSize: const Size(160, 48)),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Ho capito'),
            ),
          ],
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.start;
    return Stack(children: [
      Scaffold(
      appBar: const BrandAppBar(subtitle: 'Conferma prenotazione'),
      body: Column(children: [
        if (!widget.fromStaff) const ClientAccountBar(),
        Expanded(child: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          if (!widget.fromStaff) Card(
            elevation: 0,
            color: Brand.primary.withValues(alpha: 0.06),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.service.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Brand.primary)),
                const SizedBox(height: 4),
                Text('${s.day}/${s.month}/${s.year} alle ${hhmm(s)}', style: const TextStyle(fontSize: 16)),
              ]),
            ),
          ) else Text('${widget.service.name}\n${s.day}/${s.month} alle ${hhmm(s)}', style: Theme.of(context).textTheme.titleLarge),
          if (!widget.fromStaff) const Padding(padding: EdgeInsets.only(top: 16, bottom: 4), child: Text('I tuoi dati', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Brand.primary))),
          const SizedBox(height: 8),
          if (widget.fromStaff) ...[
            RawAutocomplete<CustomerProfile>(
              textEditingController: _email,
              focusNode: _emailFocus,
              displayStringForOption: (c) => c.email,
              optionsBuilder: (v) {
                final q = v.text.trim();
                if (q.length < 2) return const <CustomerProfile>[];
                _deb?.cancel();
                final c = Completer<List<CustomerProfile>>();
                _deb = Timer(const Duration(milliseconds: 250), () async {
                  try { c.complete(await bookingService.searchCustomersByEmail(q)); } catch (_) { c.complete(const []); }
                });
                return c.future;
              },
              onSelected: (c) => setState(() {
                _email.text = c.email;
                if (c.nome.isNotEmpty) _name.text = c.nome;
                if (c.telefono.isNotEmpty) _phone.text = c.telefono;
                if (c.codiceFiscale.isNotEmpty) _cf.text = c.codiceFiscale;
                _clienteTrovato = true;
              }),
              fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextFormField(
                controller: ctrl, focusNode: focus, keyboardType: TextInputType.emailAddress, autocorrect: false,
                onChanged: (_) { if (_clienteTrovato) setState(() => _clienteTrovato = false); },
                decoration: InputDecoration(
                  labelText: 'Email del cliente (cerca o inserisci)',
                  prefixIcon: const Icon(Icons.search),
                  helperText: _clienteTrovato
                      ? '✓ Cliente trovato: dati compilati'
                      : 'Scrivi l\'email: se il cliente esiste lo selezioni e si compila tutto. Se è nuovo, alla conferma si crea l\'account. Vuota = ricevuta al banco.',
                  helperMaxLines: 3,
                  helperStyle: _clienteTrovato ? const TextStyle(color: Colors.green, fontWeight: FontWeight.w600) : null,
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return null;
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'Email non valida';
                },
              ),
              optionsViewBuilder: (context, onSel, opts) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280, maxWidth: 520),
                    child: ListView(padding: EdgeInsets.zero, shrinkWrap: true, children: [
                      for (final c in opts)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.person, color: Brand.primary),
                          title: Text(c.email),
                          subtitle: Text([c.nome, c.telefono, c.codiceFiscale].where((x) => x.isNotEmpty).join(' · ')),
                          onTap: () => onSel(c),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          TextFormField(controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: widget.fromStaff ? 'Nome e cognome del cliente *' : 'Nome e cognome *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null),
          TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: widget.fromStaff ? 'Telefono del cliente *' : 'Telefono *'), validator: (v) => (v == null || v.trim().length < 6) ? 'Telefono non valido' : null),
          TextFormField(controller: _cf, textCapitalization: TextCapitalization.characters, autocorrect: false,
              decoration: InputDecoration(
                labelText: widget.fromStaff ? 'Codice fiscale del cliente *' : 'Codice fiscale *',
                helperText: 'Obbligatorio per scontrino e detrazioni. Non è la password.',
                helperMaxLines: 2,
              ),
              validator: codiceFiscaleError),
          if (!widget.fromStaff) ...[
            const SizedBox(height: 10),
            const Text('Per ricevere la ricevuta inserisci l\'email',
                style: TextStyle(fontSize: 13.5, height: 1.3, fontWeight: FontWeight.w600, color: Brand.primary)),
          ],
          if (!widget.fromStaff) TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, autocorrect: false,
              decoration: InputDecoration(
                labelText: widget.fromStaff ? 'Email del cliente (facoltativa)' : 'Email (facoltativa)',
                helperText: widget.fromStaff ? 'Lascia vuota se fate la ricevuta live al banco' : 'Per ricevere la ricevuta inserisci l\'email',
                helperMaxLines: 2,
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'Email non valida';
              }),
          const SizedBox(height: 16),
          Card(
            color: _esenzione ? Brand.green.withValues(alpha: 0.08) : null,
            child: SwitchListTile(
              activeThumbColor: Brand.green,
              title: const Text('Prenotazione con esenzione', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(_esenzione ? 'Sì: inserisci i dati dell\'impegnativa e una foto' : 'No, senza esenzione'),
              value: _esenzione,
              onChanged: (v) => setState(() => _esenzione = v),
            ),
          ),
          if (_esenzione) Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Impegnativa / ricetta', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF32448C))),
                TextFormField(controller: _ricetta, textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Numero ricetta (NRE) / codice impegnativa *'),
                    validator: (v) => _esenzione && (v == null || v.trim().length < 4) ? 'Obbligatorio' : null),
                TextFormField(controller: _note, maxLines: 2, decoration: const InputDecoration(labelText: 'Codice esenzione / note (facoltativo)')),
                const SizedBox(height: 12),
                if (_foto != null) ...[
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_foto!, height: 180, fit: BoxFit.contain)),
                  TextButton.icon(onPressed: () => setState(() => _foto = null), icon: const Icon(Icons.delete_outline), label: const Text('Rimuovi foto')),
                ],
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera), label: const Text('Scatta foto'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(onPressed: () => _pick(ImageSource.gallery), icon: const Icon(Icons.upload_file), label: const Text('Carica'))),
                ]),
                if (_foto == null) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Foto della ricetta obbligatoria', style: TextStyle(fontSize: 12, color: Colors.black54))),
              ]),
            ),
          ),
          if (widget.fromStaff && (widget.employeeNome ?? '').isNotEmpty) Card(
            child: ListTile(leading: const Icon(Icons.person), title: Text('Con: ${widget.employeeNome}'), subtitle: const Text('Persona assegnata alla prenotazione')),
          ),
          if (widget.fromStaff) Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Pagamento al banco', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(_metodoPagamento == null ? 'Non pagato' : (_metodoPagamento == 'carta' ? 'Pagato con carta' : 'Pagato in contanti'),
                    style: const TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'no', label: Text('No'), icon: Icon(Icons.close, size: 16)),
                    ButtonSegment(value: 'carta', label: Text('Carta'), icon: Icon(Icons.credit_card, size: 16)),
                    ButtonSegment(value: 'contanti', label: Text('Contanti'), icon: Icon(Icons.payments, size: 16)),
                  ],
                  selected: {_metodoPagamento ?? 'no'},
                  onSelectionChanged: (s) {
                    final v = s.first;
                    setState(() => _metodoPagamento = v == 'no' ? null : v);
                  },
                ),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Invio…' : 'Conferma')),
        ]),
      )),
      ]),
    ),
      if (_loading != null) Positioned.fill(child: BrandLoader(text: _loading!)),
    ]);
  }
}

class _MailOutcome {
  const _MailOutcome({required this.sent, this.account, this.manual});
  final bool sent;
  final String? account;
  final String? manual;
}

