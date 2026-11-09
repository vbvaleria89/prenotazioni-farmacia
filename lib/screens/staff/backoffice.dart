import 'booking_stats.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../models/service_type.dart';
import '../../models/settings.dart';
import '../../models/whatsapp.dart';
import '../../theme/brand.dart';

const _giorni = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];

/// Backoffice: SOLO admin. Guard doppio: ruolo passato dal login + ricontrollo su Firestore `employees/{uid}`.
class Backoffice extends StatelessWidget {
  final Employee? employee;
  const Backoffice({super.key, this.employee});

  Future<bool> _isAdmin() async {
    if (employee != null && !employee!.isAdmin) return false;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous) return false;
    final d = await FirebaseFirestore.instance.doc('employees/${u.uid}').get();
    if (!d.exists) return false;
    final e = Employee.fromDoc(d);
    return e.isAdmin && e.attivo;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _isAdmin(),
        builder: (context, snap) {
          if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          if (snap.data != true) {
            return Scaffold(
              appBar: const BrandAppBar(subtitle: 'Backoffice'),
              body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock, size: 56, color: Brand.primary),
                const SizedBox(height: 12),
                const Text('Accesso riservato all\'amministratore', style: TextStyle(fontSize: 20), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Indietro')),
              ]))),
            );
          }
          return const _BackofficeBody();
        },
      );
}

class _BackofficeBody extends StatefulWidget {
  const _BackofficeBody();
  @override
  State<_BackofficeBody> createState() => _BackofficeState();
}

class _BackofficeState extends State<_BackofficeBody> {
  PharmacySettings? _s;
  final _note = TextEditingController();
  final _wa = TextEditingController();
  final _waMsg = TextEditingController();
  int _open = 9, _close = 19;

  @override
  void initState() {
    super.initState();
    bookingService.seedServicesIfEmpty().catchError((_) {});
    Room.seedIfEmpty().catchError((_) {});
    Device.seedIfEmpty().catchError((_) {});
    bookingService.seedHolterDevice().catchError((_) {});
    bookingService.settings().then((s) => setState(() {
          _s = s;
          _note.text = s.serviziNote;
          _wa.text = s.whatsapp;
          _waMsg.text = s.whatsappClientMessage;
          _open = s.openHour;
          _close = s.closeHour;
        }));
  }

  Future<void> _save() async {
    final m = ScaffoldMessenger.of(context);
    final s = _s!;
    try {
      await bookingService.saveSettings(PharmacySettings(openHour: _open, closeHour: _close, tricologicoDays: s.tricologicoDays,
          tricologoEmployeeId: s.tricologoEmployeeId, tricologoNome: s.tricologoNome, serviziNote: _note.text.trim(),
          whatsapp: _wa.text.trim(), whatsappClientMessage: _waMsg.text.trim().isEmpty ? kDefaultWhatsappClientMessage : _waMsg.text.trim()));
      m.showSnackBar(const SnackBar(content: Text('Impostazioni salvate')));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('Salvataggio non riuscito: $e')));
    }
  }

  Widget _hour(String label, int v, ValueChanged<int> f) => Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
        DropdownButton<int>(value: v, items: [for (var h = 6; h <= 22; h++) DropdownMenuItem(value: h, child: Text('$h:00'))],
            onChanged: (x) => setState(() => f(x!))),
      ]);

  void _edit(ServiceType? s, int nextOrder) => showDialog(context: context, builder: (_) => _ServiceDialog(service: s, nextOrder: nextOrder));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.titleLarge;
    return Scaffold(
      appBar: const BrandAppBar(subtitle: 'Backoffice'),
      body: _s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Expanded(child: Text('Servizi', style: t)),
              ]),
              const Text('Tocca un servizio per modificare nome, durata, prezzo, sconto, giorni, stanze utilizzabili e persona.'),
              StreamBuilder<List<ServiceType>>(
                stream: bookingService.watchServices(),
                builder: (context, snap) {
                  if (snap.hasError) return Text('Errore: ${snap.error}');
                  final list = snap.data ?? const <ServiceType>[];
                  return Column(children: [
                    for (final s in list)
                      Card(child: ListTile(
                        leading: Icon(s.attivo ? Icons.check_circle : Icons.pause_circle, color: s.attivo ? Brand.green : Colors.grey),
                        title: Text(s.name + (s.attivo ? '' : ' (disattivato)')),
                        subtitle: Text([
                          '${s.duration.inMinutes} min',
                          if (s.prezzo != null) s.scontato ? '${euro(s.prezzo!)} → ${euro(s.prezzoScontato!)}' : euro(s.prezzo!),
                          s.giorni.isEmpty ? 'tutti i giorni' : (s.giorni.toList()..sort()).map((d) => _giorni[d - 1]).join(', '),
                          s.stanzeLabel,
                          if (s.usesDevice) '${s.deviceLabel} · ${s.deviceHoldHours} h',
                          if (s.dipendenteNome.isNotEmpty) s.dipendenteNome,
                        ].join(' · ')),
                        trailing: const Icon(Icons.edit),
                        onTap: () => _edit(s, list.length + 1),
                      )),
                    const SizedBox(height: 8),
                    SizedBox(height: 52, width: double.infinity, child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Brand.green),
                      onPressed: () => _edit(null, list.length + 1),
                      icon: const Icon(Icons.add), label: const Text('Aggiungi servizio', style: TextStyle(fontSize: 16)))),
                  ]);
                },
              ),
              const Divider(height: 32),
              Text('Orari stanze servizi', style: t),
              _hour('Apertura', _open, (v) => _open = v),
              _hour('Chiusura', _close, (v) => _close = v),
              TextField(controller: _note, maxLines: 3, decoration: const InputDecoration(labelText: 'Note servizi')),
              TextField(controller: _wa, decoration: const InputDecoration(labelText: 'WhatsApp (es. 081 570 4733)', helperText: 'Vuoto = numero della farmacia')),
              TextField(
                controller: _waMsg,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Messaggio WhatsApp (Area personale cliente)',
                  helperText: 'Usa [Nome] per il nome del cliente. Vuoto = messaggio predefinito.',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(height: 56, child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save),
                  label: const Text('Salva orari e note', style: TextStyle(fontSize: 18)))),
              const Divider(height: 32),
              Text('Stanze', style: t),
              const _RoomsSection(),
              const Divider(height: 32),
              Text('Apparecchi', style: t),
              const _DevicesSection(),
              const Divider(height: 32),
              Text('Dipendenti', style: t),
              ListTile(leading: const Icon(Icons.assignment_ind, color: Color(0xFF32448C)), title: const Text('Assegnazioni'),
                  subtitle: const Text('Prenotazioni create da ogni utenza (oggi / mese)'), trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AssegnazioniPage()))),
              StreamBuilder<List<Employee>>(
                stream: staffAuth.employees(),
                builder: (context, snap) {
                  if (snap.hasError) return Text('Errore: ${snap.error}');
                  final list = snap.data ?? const <Employee>[];
                  return Column(children: [
                    for (final e in list)
                      ListTile(
                        leading: Icon(e.attivo ? Icons.person : Icons.person_off),
                        title: Text(e.nome.isEmpty ? e.email : e.nome),
                        subtitle: Text('${e.email} · ${e.ruolo}${e.attivo ? '' : ' · disattivato'}'),
                      ),
                  ]);
                },
              ),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Aggiungere un dipendente:\n'
                      '1) Firebase Console → Authentication → Aggiungi utente (email + password).\n'
                      '2) Copia l\'UID e crea in Firestore il documento employees/<UID> con: email, nome, ruolo (admin|staff), attivo=true.'),
                ),
              ),
            ]),
    );
  }
}

class _ServiceDialog extends StatefulWidget {
  final ServiceType? service;
  final int nextOrder;
  const _ServiceDialog({this.service, required this.nextOrder});
  @override
  State<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends State<_ServiceDialog> {
  final _form = GlobalKey<FormState>();
  late final _nome = TextEditingController(text: widget.service?.name ?? '');
  late final _desc = TextEditingController(text: widget.service?.description ?? '');
  late final _durata = TextEditingController(text: '${widget.service?.duration.inMinutes ?? 15}');
  late final _prezzo = TextEditingController(text: _fmt(widget.service?.prezzo));
  late final _sconto = TextEditingController(text: _fmt(widget.service?.prezzoScontato));
  late final _persona = TextEditingController(text: widget.service?.dipendenteNome ?? '');
  late bool _attivo = widget.service?.attivo ?? true;
  late bool _dedicati = widget.service?.giorni.isNotEmpty ?? false;
  late final Set<int> _giorniSel = {...?widget.service?.giorni};
  late final Set<int> _stanzeSel = {...(widget.service?.stanzeOrdinate ?? const [kStanza1])};
  late final _deviceNome = TextEditingController(text: () {
    final s = widget.service;
    if (s == null) return '';
    if (s.deviceId.isNotEmpty) return Device.label(s.deviceId);
    final inferred = Device.inferredId(s.name, id: s.id);
    return inferred != null ? Device.label(inferred) : '';
  }());
  late final _deviceQty = TextEditingController(text: '${widget.service != null && widget.service!.deviceId.isNotEmpty ? Device.quantityOf(widget.service!.deviceId) : 1}');
  late final _deviceHours = TextEditingController(text: () {
    final s = widget.service;
    if (s == null) return '';
    if (s.deviceHoldHours > 0) return '${s.deviceHoldHours}';
    final h = Device.inferredHours(s.name, id: s.id);
    return h > 0 ? '$h' : '';
  }());
  late String _dipId = widget.service?.dipendenteId ?? '';

  static String _fmt(double? v) => v == null ? '' : v.toStringAsFixed(2).replaceAll('.', ',');
  static double? _parse(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim().replaceAll('€', '').replaceAll(',', '.'));

  String _slug(String s) {
    final b = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    return b.isEmpty ? 'servizio-${DateTime.now().millisecondsSinceEpoch}' : b;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_dedicati && _giorniSel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seleziona almeno un giorno dedicato')));
      return;
    }
    if (_stanzeSel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seleziona almeno una stanza utilizzabile')));
      return;
    }
    final nav = Navigator.of(context);
    final m = ScaffoldMessenger.of(context);
    final old = widget.service;
    final devName = _deviceNome.text.trim();
    var deviceId = '';
    var deviceHoldHours = 0;
    if (devName.isNotEmpty) {
      deviceHoldHours = int.tryParse(_deviceHours.text.trim()) ?? 0;
      if (deviceHoldHours < 1 || deviceHoldHours > 168) {
        m.showSnackBar(const SnackBar(content: Text('Indica per quante ore resta occupato l\'apparecchio (1–168)')));
        return;
      }
      final qty = int.tryParse(_deviceQty.text.trim()) ?? 0;
      if (qty < 1 || qty > 99) {
        m.showSnackBar(const SnackBar(content: Text('Pezzi disponibili: intero tra 1 e 99')));
        return;
      }
      Device? existing;
      final curId = old?.deviceId ?? '';
      if (curId.isNotEmpty && Device.registry[curId]?.nome.toLowerCase() == devName.toLowerCase()) {
        existing = Device.registry[curId];
      } else {
        for (final d in Device.registry.values) {
          if (d.nome.toLowerCase() == devName.toLowerCase()) { existing = d; break; }
        }
      }
      final dev = Device(id: existing?.id ?? Device.slug(devName), nome: devName, quantita: qty, attivo: existing?.attivo ?? true);
      try {
        await Device.save(dev);
      } catch (e) {
        m.showSnackBar(SnackBar(content: Text('Salvataggio apparecchio non riuscito: $e')));
        return;
      }
      deviceId = dev.id;
    }
    final s = ServiceType(
      id: old?.id ?? _slug(_nome.text),
      name: _nome.text.trim(), description: _desc.text.trim(), duration: Duration(minutes: int.parse(_durata.text.trim())),
      attivo: _attivo, prezzo: _parse(_prezzo.text), prezzoScontato: _parse(_sconto.text),
      giorni: _dedicati ? _giorniSel : const {}, dipendenteId: _dipId, dipendenteNome: _persona.text.trim(), ordine: old?.ordine ?? widget.nextOrder,
      stanze: {..._stanzeSel}, deviceId: deviceId, deviceHoldHours: deviceHoldHours,
    );
    try {
      await bookingService.saveService(s);
      nav.pop();
      m.showSnackBar(SnackBar(content: Text('Servizio "${s.name}" salvato')));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('Salvataggio non riuscito: $e')));
    }
  }

  String? _priceVal(String? v, {bool sconto = false}) {
    if (v == null || v.trim().isEmpty) return null;
    final p = _parse(v);
    if (p == null || p < 0) return 'Importo non valido';
    if (sconto) {
      final full = _parse(_prezzo.text);
      if (full == null) return 'Inserisci prima il prezzo pieno';
      if (p >= full) return 'Deve essere inferiore al prezzo pieno';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.service == null ? 'Nuovo servizio' : 'Modifica servizio'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextFormField(controller: _nome, decoration: const InputDecoration(labelText: 'Nome servizio'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null),
            TextFormField(controller: _desc, decoration: const InputDecoration(labelText: 'Descrizione (opzionale)')),
            TextFormField(controller: _durata, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Durata (minuti)'),
                validator: (v) { final n = int.tryParse(v?.trim() ?? ''); return (n == null || n < 5 || n > 480) ? 'Minuti tra 5 e 480' : null; }),
            Row(children: [
              Expanded(child: TextFormField(controller: _prezzo, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Prezzo (€)', hintText: 'es. 25,00'), validator: _priceVal)),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(controller: _sconto, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Prezzo scontato (€)', hintText: 'vuoto = nessuno sconto'),
                  validator: (v) => _priceVal(v, sconto: true))),
            ]),
            const Padding(padding: EdgeInsets.only(top: 4), child: Text('Con lo sconto il cliente vede il prezzo pieno barrato e quello scontato.',
                style: TextStyle(fontSize: 12, color: Colors.black54))),
            SwitchListTile(contentPadding: EdgeInsets.zero, activeThumbColor: Brand.green, title: const Text('Attivo (prenotabile dai clienti)'),
                value: _attivo, onChanged: (v) => setState(() => _attivo = v)),
            const Padding(padding: EdgeInsets.only(top: 8, bottom: 4), child: Text('Stanze utilizzabili', style: TextStyle(fontWeight: FontWeight.w600))),
            const Text('Seleziona una o più stanze in alternativa. Ogni prenotazione ne occupa una sola: la prima libera per priorità.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              for (final r in Room.ordered)
                FilterChip(label: Text('${r.nome} (P${r.priorita})'), selected: _stanzeSel.contains(r.id),
                    onSelected: (on) => setState(() => on ? _stanzeSel.add(r.id) : _stanzeSel.remove(r.id))),
            ]),
            const Padding(padding: EdgeInsets.only(top: 12, bottom: 4), child: Text('Apparecchio (opzionale)', style: TextStyle(fontWeight: FontWeight.w600))),
            const Text('Se il servizio usa uno strumento che resta addosso al paziente, indica nome, pezzi e per quante ore resta occupato. Holter cardiaco e Holter pressorio sono due apparecchi distinti; altri servizi possono condividere lo stesso apparecchio se hanno lo stesso nome.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            TextFormField(controller: _deviceNome, decoration: const InputDecoration(labelText: 'Apparecchio', hintText: 'es. Holter cardiaco')),
            Row(children: [
              Expanded(child: TextFormField(controller: _deviceQty, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Pezzi disponibili', hintText: '1'))),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(controller: _deviceHours, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Occupato per (ore)', hintText: 'es. 24'))),
            ]),
            SwitchListTile(contentPadding: EdgeInsets.zero, activeThumbColor: Brand.green, title: const Text('Solo in giorni dedicati'),
                value: _dedicati, onChanged: (v) => setState(() => _dedicati = v)),
            if (_dedicati)
              Wrap(spacing: 6, children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(label: Text(_giorni[d - 1]), selected: _giorniSel.contains(d),
                      onSelected: (on) => setState(() => on ? _giorniSel.add(d) : _giorniSel.remove(d))),
              ]),
            TextField(controller: _persona, decoration: const InputDecoration(labelText: 'Persona dedicata (opzionale)')),
            StreamBuilder<List<Employee>>(
              stream: staffAuth.employees(),
              builder: (context, snap) {
                final list = snap.data ?? const <Employee>[];
                return DropdownButtonFormField<String>(
                  initialValue: list.any((e) => e.id == _dipId) ? _dipId : '',
                  decoration: const InputDecoration(labelText: 'Account dipendente dedicato (opzionale)'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('— chiunque di turno —')),
                    for (final e in list) DropdownMenuItem(value: e.id, child: Text(e.nome.isEmpty ? e.email : e.nome)),
                  ],
                  onChanged: (v) => setState(() {
                    _dipId = v ?? '';
                    final e = list.where((e) => e.id == _dipId);
                    if (e.isNotEmpty && _persona.text.trim().isEmpty) _persona.text = e.first.nome;
                  }),
                );
              },
            ),
          ])),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Brand.primary), onPressed: _save, child: const Text('Salva')),
      ],
    );
  }
}


class _RoomsSection extends StatelessWidget {
  const _RoomsSection();

  Future<void> _edit(BuildContext context, Room? r) async {
    final nome = TextEditingController(text: r?.nome ?? '');
    final prio = TextEditingController(text: '${r?.priorita ?? (Room.registry.length + 1)}');
    var attivo = r?.attivo ?? true;
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
      title: Text(r == null ? 'Nuova stanza' : 'Modifica stanza'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome')),
        TextField(controller: prio, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Priorità', helperText: 'numero più basso = scelta preferita')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Attiva'), value: attivo, onChanged: (v) => set(() => attivo = v)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annulla')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salva')),
      ],
    )));
    if (ok != true || nome.text.trim().isEmpty) return;
    if (!context.mounted) return;
    final m = ScaffoldMessenger.of(context);
    try {
      await Room.save(Room(id: r?.id ?? Room.nextId(), nome: nome.text.trim(), priorita: int.tryParse(prio.text.trim()) ?? 99, attivo: attivo));
    } catch (e) { m.showSnackBar(SnackBar(content: Text('Errore: $e'))); }
  }

  Future<void> _delete(BuildContext context, Room r) async {
    final m = ScaffoldMessenger.of(context);
    final users = ServiceType.registry.values.where((s) => s.stanze.contains(r.id)).map((s) => s.name).toList();
    if (users.isNotEmpty) {
      m.showSnackBar(SnackBar(content: Text('Impossibile eliminare: usata da ${users.join(', ')}. Toglila prima dai servizi (o disattivala).')));
      return;
    }
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('Eliminare ${r.nome}?'),
      content: const Text('Le prenotazioni passate mostreranno il nome salvato.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Elimina')),
      ],
    ));
    if (ok == true) {
      try { await Room.delete(r.id); } catch (e) { m.showSnackBar(SnackBar(content: Text('Errore: $e'))); }
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Room>>(
        stream: Room.watch(),
        builder: (context, snap) {
          final list = snap.data ?? (Room.registry.values.toList()..sort((a, b) => a.priorita.compareTo(b.priorita)));
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Priorità: numero più basso = scelta preferita in prenotazione.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            for (final r in list)
              Card(child: ListTile(
                leading: CircleAvatar(child: Text('${r.priorita}')),
                title: Text(r.nome),
                subtitle: Text('Priorità ${r.priorita}${r.attivo ? '' : ' · disattivata'}'),
                onTap: () => _edit(context, r),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context, r)),
              )),
            TextButton.icon(onPressed: () => _edit(context, null), icon: const Icon(Icons.add), label: const Text('Aggiungi stanza')),
          ]);
        },
      );
}


class _DevicesSection extends StatelessWidget {
  const _DevicesSection();

  Future<void> _edit(BuildContext context, Device? d) async {
    final nome = TextEditingController(text: d?.nome ?? '');
    final qty = TextEditingController(text: '${d?.quantita ?? 1}');
    var attivo = d?.attivo ?? true;
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
      title: Text(d == null ? 'Nuovo apparecchio' : 'Modifica apparecchio'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome', hintText: 'es. Holter cardiaco')),
        TextField(controller: qty, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Pezzi disponibili', helperText: 'quanti ne ha la farmacia')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Attivo'), value: attivo, onChanged: (v) => set(() => attivo = v)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annulla')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salva')),
      ],
    )));
    if (ok != true || nome.text.trim().isEmpty) return;
    if (!context.mounted) return;
    final m = ScaffoldMessenger.of(context);
    final n = int.tryParse(qty.text.trim()) ?? 0;
    if (n < 1 || n > 99) {
      m.showSnackBar(const SnackBar(content: Text('Pezzi disponibili: intero tra 1 e 99')));
      return;
    }
    try {
      await Device.save(Device(id: d?.id ?? Device.slug(nome.text.trim()), nome: nome.text.trim(), quantita: n, attivo: attivo));
    } catch (e) { m.showSnackBar(SnackBar(content: Text('Errore: $e'))); }
  }

  Future<void> _delete(BuildContext context, Device d) async {
    final m = ScaffoldMessenger.of(context);
    final users = ServiceType.registry.values.where((s) => s.deviceId == d.id).map((s) => s.name).toList();
    if (users.isNotEmpty) {
      m.showSnackBar(SnackBar(content: Text('Impossibile eliminare: usato da ${users.join(', ')}. Toglilo prima dai servizi.')));
      return;
    }
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('Eliminare ${d.nome}?'),
      content: const Text('I servizi non resteranno collegati a questo apparecchio.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Elimina')),
      ],
    ));
    if (ok == true) {
      try { await Device.delete(d.id); } catch (e) { m.showSnackBar(SnackBar(content: Text('Errore: $e'))); }
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Device>>(
        stream: Device.watch(),
        builder: (context, snap) {
          final list = snap.data ?? (Device.registry.values.toList()..sort((a, b) => a.nome.compareTo(b.nome)));
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Gli apparecchi si possono anche impostare dal singolo servizio. La quantità è condivisa.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            for (final d in list)
              Card(child: ListTile(
                leading: const Icon(Icons.watch),
                title: Text(d.nome),
                subtitle: Text('${d.quantita} ${d.quantita == 1 ? 'pezzo' : 'pezzi'}${d.attivo ? '' : ' · disattivato'}'),
                onTap: () => _edit(context, d),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context, d)),
              )),
            TextButton.icon(onPressed: () => _edit(context, null), icon: const Icon(Icons.add), label: const Text('Aggiungi apparecchio')),
          ]);
        },
      );
}
