import 'package:flutter/material.dart';
import '../../app.dart';
import '../../models/appointment.dart';
import '../../models/codice_fiscale.dart';
import '../../models/service_type.dart';
import '../../theme/brand.dart';
import '../client/slot_picker.dart' show hhmm;

/// Dialog/schermata staff per modificare TUTTO della prenotazione (anagrafica,
/// servizio, data/ora, esenzione, pagamento). Codice e stato restano.
Future<bool> apriModificaPrenotazione(BuildContext context, Appointment a) async {
  if (a.status == AppointmentStatus.annullato) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prenotazione annullata: non modificabile')));
    return false;
  }
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => EditBookingPage(appointment: a)));
  return ok == true;
}

class EditBookingPage extends StatefulWidget {
  final Appointment appointment;
  final bool customerOnly;
  const EditBookingPage({super.key, required this.appointment, this.customerOnly = false});
  @override
  State<EditBookingPage> createState() => _EditBookingPageState();
}

class _EditBookingPageState extends State<EditBookingPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _cf;
  late final TextEditingController _ricetta;
  late final TextEditingController _note;
  late ServiceType _service;
  late DateTime _day;
  DateTime? _start;
  late bool _esenzione;
  String? _metodo; // null = non pagato
  bool _busy = false;
  List<ServiceType> _services = const [];
  List<DateTime> _slots = const [];
  bool _loadingSlots = false;

  Appointment get a => widget.appointment;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: a.customerName);
    _phone = TextEditingController(text: a.phone);
    _email = TextEditingController(text: a.email ?? '');
    _cf = TextEditingController(text: a.codiceFiscale ?? '');
    _ricetta = TextEditingController(text: a.ricettaNumero ?? '');
    _note = TextEditingController(text: a.ricettaNote ?? '');
    _service = a.service;
    _day = DateTime(a.start.year, a.start.month, a.start.day);
    _start = a.start;
    _esenzione = a.esenzione;
    _metodo = a.pagato ? (a.metodoPagamento ?? 'carta') : null;
    if (!widget.customerOnly) { _loadServices(); _reloadSlots(); }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _cf.dispose();
    _ricetta.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    await for (final list in bookingService.watchActiveServices()) {
      if (!mounted) return;
      setState(() {
        _services = list;
        if (!_services.any((s) => s.id == _service.id)) {
          _services = [..._services, _service];
        }
      });
      break;
    }
  }

  Future<void> _reloadSlots() async {
    setState(() => _loadingSlots = true);
    try {
      final slots = await bookingService.availableSlots(_service, _day, excludeId: a.id, keepSlot: a.start);
      if (!mounted) return;
      setState(() {
        _slots = slots;
        if (_start != null && !_slots.any((t) => _sameMinute(t, _start!))) {
          // Slot corrente non più disponibile: deseleziona.
          if (!(_sameDay(_start!, _day) && _sameMinute(_start!, a.start) && slots.any((t) => _sameMinute(t, a.start)))) {
            _start = slots.isEmpty ? null : slots.first;
          }
        }
        if (_start == null && slots.isNotEmpty) _start = slots.first;
        _loadingSlots = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _slots = const []; _loadingSlots = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Orari non caricati: $e')));
    }
  }

  bool _sameDay(DateTime x, DateTime y) => x.year == y.year && x.month == y.month && x.day == y.day;
  bool _sameMinute(DateTime x, DateTime y) => _sameDay(x, y) && x.hour == y.hour && x.minute == y.minute;

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 120)),
      helpText: 'Giorno prenotazione',
      cancelText: 'Annulla',
      confirmText: 'OK',
    );
    if (d == null) return;
    setState(() {
      _day = DateTime(d.year, d.month, d.day);
      _start = null;
    });
    await _reloadSlots();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (!widget.customerOnly && _start == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scegli un orario')));
      return;
    }
    if (!widget.customerOnly && _esenzione && _ricetta.text.trim().length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Numero ricetta obbligatorio con esenzione')));
      return;
    }
    setState(() => _busy = true);
    final m = ScaffoldMessenger.of(context);
    try {
      if (widget.customerOnly) {
        await bookingService.updateCustomerDetails(a, name: _name.text, phone: _phone.text, email: _email.text);
      } else {
      await bookingService.updateBooking(
        a,
        name: _name.text,
        phone: _phone.text,
        codiceFiscale: _cf.text,
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        service: _service,
        start: _start!,
        esenzione: _esenzione,
        ricettaNumero: _esenzione ? _ricetta.text.trim() : null,
        ricettaNote: _esenzione && _note.text.trim().isNotEmpty ? _note.text.trim() : null,
        pagato: _metodo != null,
        metodoPagamento: _metodo,
      );
      }
      if (!mounted) return;
      m.showSnackBar(SnackBar(content: Text(widget.customerOnly ? 'Dati cliente aggiornati' : 'Prenotazione aggiornata')));
      Navigator.pop(context, true);
    } on StateError catch (e) {
      m.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('Salvataggio non riuscito: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = a.id.substring(0, 6).toUpperCase();
    return Scaffold(
      appBar: BrandAppBar(subtitle: widget.customerOnly ? 'Correggi dati cliente' : 'Modifica · $code'),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          if (!widget.customerOnly) Text('Codice $code · stato invariato. Puoi correggere dati, servizio, data/ora, esenzione e pagamento.',
              style: const TextStyle(fontSize: 14, color: Colors.black54)),
          const SizedBox(height: 12),
          const Text('Correggi dati cliente', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Brand.primary)),
          const Text('Telefono, email e nome vengono aggiornati anche nel profilo cliente collegato. L’email di accesso resta invariata. Le ricevute già inviate non vengono reinviate.'),
          const SizedBox(height: 12),
          TextFormField(controller: _name, maxLength: 99, textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome e cognome *', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null),
          const SizedBox(height: 10),
          TextFormField(controller: _phone, maxLength: 29, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Telefono *', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().length < 6) ? 'Telefono non valido' : null),
          const SizedBox(height: 10),
          if (!widget.customerOnly) TextFormField(controller: _cf, textCapitalization: TextCapitalization.characters, autocorrect: false,
              decoration: const InputDecoration(labelText: 'Codice fiscale *', border: OutlineInputBorder()),
              validator: codiceFiscaleError),
          const SizedBox(height: 10),
          TextFormField(controller: _email, maxLength: 119, keyboardType: TextInputType.emailAddress, autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email (facoltativa)', border: OutlineInputBorder(),
                  helperText: 'Per le prossime conferme e ricevute; vuota = nessun invio email'),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'Email non valida';
              }),
          if (!widget.customerOnly) ...[
          const SizedBox(height: 16),
          const Text('Servizio e orario', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Brand.primary)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _services.any((s) => s.id == _service.id) ? _service.id : null,
            decoration: const InputDecoration(labelText: 'Servizio', border: OutlineInputBorder()),
            items: [
              for (final s in _services)
                DropdownMenuItem(value: s.id, child: Text('${s.name} (${s.duration.inMinutes} min)')),
            ],
            onChanged: (id) {
              if (id == null) return;
              final s = _services.firstWhere((x) => x.id == id);
              setState(() { _service = s; _start = null; });
              _reloadSlots();
            },
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _busy ? null : _pickDay,
              icon: const Icon(Icons.event),
              label: Text('${_day.day.toString().padLeft(2, '0')}/${_day.month.toString().padLeft(2, '0')}/${_day.year}'))),
            const SizedBox(width: 8),
            Text(_start == null ? 'Scegli ora' : hhmm(_start!), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          if (_loadingSlots) const LinearProgressIndicator()
          else if (_slots.isEmpty)
            const Text('Nessuno slot libero in questo giorno (stanze impegnate).', style: TextStyle(color: Colors.red))
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in _slots)
                ChoiceChip(
                  label: Text(hhmm(t)),
                  selected: _start != null && _sameMinute(t, _start!),
                  onSelected: (_) => setState(() => _start = t),
                ),
            ]),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Stanza attuale: ${a.stanzaLabel} (si ricalcola al salvataggio se cambi servizio/orario)',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          const SizedBox(height: 16),
          Card(
            color: _esenzione ? Brand.green.withValues(alpha: 0.08) : null,
            child: SwitchListTile(
              activeThumbColor: Brand.green,
              title: const Text('Con esenzione', style: TextStyle(fontWeight: FontWeight.w600)),
              value: _esenzione,
              onChanged: (v) => setState(() => _esenzione = v),
            ),
          ),
          if (_esenzione) ...[
            const SizedBox(height: 8),
            TextFormField(controller: _ricetta, textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Numero ricetta (NRE) *', border: OutlineInputBorder()),
                validator: (v) => _esenzione && (v == null || v.trim().length < 4) ? 'Obbligatorio' : null),
            const SizedBox(height: 8),
            TextFormField(controller: _note, maxLines: 2,
                decoration: const InputDecoration(labelText: 'Note / codice esenzione', border: OutlineInputBorder())),
            if (a.ricettaFoto) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Foto ricetta già presente (invariata).', style: TextStyle(fontSize: 12, color: Colors.black54))),
          ],
          const SizedBox(height: 12),
          const Text('Pagamento al banco', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'no', label: Text('No'), icon: Icon(Icons.close, size: 16)),
              ButtonSegment(value: 'carta', label: Text('Carta'), icon: Icon(Icons.credit_card, size: 16)),
              ButtonSegment(value: 'bancomat', label: Text('Bancomat'), icon: Icon(Icons.payment, size: 16)),
            ],
            selected: {_metodo ?? 'no'},
            onSelectionChanged: (s) {
              final v = s.first;
              setState(() => _metodo = v == 'no' ? null : v);
            },
          ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
              label: Text(_busy ? 'Salvataggio…' : 'Salva modifiche', style: const TextStyle(fontSize: 18)),
            ),
          ),
        ]),
      ),
    );
  }
}

Future<bool> apriCorrezioneCliente(BuildContext context, Appointment a) async {
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => EditBookingPage(appointment: a, customerOnly: true)));
  return ok == true;
}
