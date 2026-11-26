import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/appointment.dart';
import '../../models/recall.dart';
import '../../models/settings.dart';
import '../../models/whatsapp.dart';
import '../../services/open_link.dart';
import '../../theme/brand.dart';

String fmtRecallData(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class RecallVoce {
  final Appointment appointment;
  final RecallRecord? record;
  final RecallStato stato;
  const RecallVoce(this.appointment, this.record, this.stato);
}

List<RecallVoce> recallVoci(List<Appointment> appuntamenti, List<RecallRecord> recalls, int leadDays, DateTime now) {
  final byId = {for (final r in recalls) r.appointmentId: r};
  final list = <RecallVoce>[
    for (final a in appuntamenti)
      RecallVoce(a, byId[a.id], (byId[a.id] ?? RecallRecord(appointmentId: a.id)).stato(leadDays, now)),
  ];
  int rank(RecallStato s) => switch (s) {
        RecallStato.daAvvisare => 0,
        RecallStato.senzaRisultato => 1,
        RecallStato.inCorso => 2,
        RecallStato.avvisato => 3,
      };
  list.sort((a, b) {
    final r = rank(a.stato).compareTo(rank(b.stato));
    if (r != 0) return r;
    if (a.stato == RecallStato.daAvvisare || a.stato == RecallStato.inCorso) {
      final da = a.record?.prossimoControllo;
      final db = b.record?.prossimoControllo;
      if (da != null && db != null) return da.compareTo(db);
    }
    return b.appointment.start.compareTo(a.appointment.start);
  });
  return list;
}

List<RecallVoce> recallDaNotificare(List<RecallVoce> voci) =>
    [for (final v in voci) if (v.stato == RecallStato.daAvvisare) v];

/// Elenco Recall: tutte le prenotazioni non annullate, con il risultato.
class RecallPage extends StatefulWidget {
  const RecallPage({super.key});
  @override
  State<RecallPage> createState() => _RecallPageState();
}

class _RecallPageState extends State<RecallPage> {
  String _q = '';
  RecallStato? _filtro;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandAppBar(subtitle: 'Recall'),
      body: StreamBuilder<PharmacySettings>(
        stream: bookingService.settingsStream(),
        builder: (context, snapS) {
          final lead = snapS.data?.recallLeadDays ?? 15;
          return StreamBuilder<List<Appointment>>(
            stream: bookingService.watchRecallAppointments(),
            builder: (context, snapA) {
              return StreamBuilder<List<RecallRecord>>(
                stream: bookingService.watchRecalls(),
                builder: (context, snapR) {
                  if (snapA.hasError) return Center(child: Text('Elenco non disponibile: ${snapA.error}'));
                  if (snapR.hasError) return Center(child: Text('Recall non disponibili: ${snapR.error}'));
                  if (!snapA.hasData || !snapR.hasData) return const Center(child: CircularProgressIndicator());
                  final now = DateTime.now();
                  final tutte = recallVoci(snapA.data!, snapR.data!, lead, now);
                  final q = _q.trim().toLowerCase();
                  final viste = [
                    for (final v in tutte)
                      if (_filtro == null || v.stato == _filtro)
                        if (q.isEmpty ||
                            v.appointment.customerName.toLowerCase().contains(q) ||
                            v.appointment.phone.toLowerCase().contains(q) ||
                            v.appointment.service.name.toLowerCase().contains(q) ||
                            v.appointment.shortCode.toLowerCase().contains(q))
                          v,
                  ];
                  return Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Cerca nome, telefono, servizio o codice',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _q = v),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Row(children: [
                        _chip('Tutte', null, tutte.length),
                        _chip('Da avvisare', RecallStato.daAvvisare, tutte.where((v) => v.stato == RecallStato.daAvvisare).length),
                        _chip('Senza risultato', RecallStato.senzaRisultato, tutte.where((v) => v.stato == RecallStato.senzaRisultato).length),
                        _chip('In corso', RecallStato.inCorso, tutte.where((v) => v.stato == RecallStato.inCorso).length),
                        _chip('Avvisati', RecallStato.avvisato, tutte.where((v) => v.stato == RecallStato.avvisato).length),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Avviso $lead giorni prima del prossimo controllo', style: const TextStyle(color: Colors.black54)),
                      ),
                    ),
                    Expanded(
                      child: viste.isEmpty
                          ? const Center(child: Text('Nessuna prenotazione in questo elenco'))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                              itemCount: viste.length,
                              itemBuilder: (context, i) {
                                final v = viste[i];
                                final a = v.appointment;
                                final esito = recallEsitoLabel[v.record?.esito ?? ''] ?? '';
                                return Card(
                                  child: ListTile(
                                    onTap: () => apriSchedaRecall(context, a.id),
                                    title: Text(a.customerName.isEmpty ? 'Senza nome' : a.customerName, style: const TextStyle(fontWeight: FontWeight.w800)),
                                    subtitle: Text([
                                      '${a.service.name} · ${fmtRecallData(a.start)} ${a.start.hour.toString().padLeft(2, '0')}:${a.start.minute.toString().padLeft(2, '0')}',
                                      if (esito.isNotEmpty) esito,
                                      if (v.record?.prossimoControllo != null) 'Prossimo controllo ${fmtRecallData(v.record!.prossimoControllo!)}',
                                    ].join('\n')),
                                    isThreeLine: true,
                                    trailing: _StatoPill(v.stato),
                                  ),
                                );
                              },
                            ),
                    ),
                  ]);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _chip(String label, RecallStato? stato, int n) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text('$label ($n)'),
        selected: _filtro == stato,
        onSelected: (_) => setState(() => _filtro = stato),
      ),
    );
  }
}

class _StatoPill extends StatelessWidget {
  final RecallStato stato;
  const _StatoPill(this.stato);
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (stato) {
      RecallStato.daAvvisare => (const Color(0xFFFFF1CC), const Color(0xFF8A6100)),
      RecallStato.avvisato => (const Color(0xFFD9F2E3), const Color(0xFF1E6B3A)),
      RecallStato.inCorso => (const Color(0xFFDCE8F5), const Color(0xFF2B4C70)),
      RecallStato.senzaRisultato => (Colors.grey.shade200, Colors.black54),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(recallStatoLabel(stato), style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

Future<void> apriSchedaRecall(BuildContext context, String appointmentId) {
  return Navigator.push(context, MaterialPageRoute(builder: (_) => RecallScheda(appointmentId: appointmentId)));
}

class RecallScheda extends StatefulWidget {
  final String appointmentId;
  const RecallScheda({super.key, required this.appointmentId});
  @override
  State<RecallScheda> createState() => _RecallSchedaState();
}

class _RecallSchedaState extends State<RecallScheda> {
  Appointment? _a;
  RecallRecord? _salvato;
  PharmacySettings? _settings;
  String _esito = '';
  DateTime? _data;
  final _note = TextEditingController();
  bool _loading = true;
  String? _errore;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _carica() async {
    try {
      final a = await bookingService.appointmentById(widget.appointmentId);
      final r = await bookingService.recallById(widget.appointmentId);
      final s = await bookingService.settings();
      if (!mounted) return;
      if (a == null || a.status == AppointmentStatus.annullato) {
        setState(() { _loading = false; _errore = 'Prenotazione non disponibile'; });
        return;
      }
      _note.text = r?.note ?? '';
      setState(() {
        _a = a;
        _salvato = r;
        _settings = s;
        _esito = r?.esito ?? '';
        _data = r?.prossimoControllo;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _errore = '$e'; });
    }
  }

  Future<void> _salva() async {
    if (_busy) return;
    final m = ScaffoldMessenger.of(context);
    final prima = _salvato?.prossimoControllo;
    setState(() => _busy = true);
    try {
      await bookingService.saveRecall(
        appointmentId: widget.appointmentId,
        esito: _esito,
        note: _note.text,
        prossimoControllo: _data,
      );
      final dopo = await bookingService.recallById(widget.appointmentId);
      if (!mounted) return;
      setState(() { _salvato = dopo; _busy = false; });
      final cambiata = !stessoGiornoRecall(prima, _data) && prima != null;
      m.showSnackBar(SnackBar(content: Text(cambiata && (dopo?.contattato == false)
          ? 'Risultato salvato. Con la nuova data il cliente torna da contattare.'
          : 'Risultato salvato')));
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      m.showSnackBar(SnackBar(content: Text('Salvataggio non riuscito: $e')));
    }
  }

  Future<void> _whatsapp() async {
    final a = _a;
    if (a == null) return;
    final digits = whatsAppClientDigits(a.phone);
    if (digits == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Telefono del cliente non valido')));
      return;
    }
    final msg = fillWhatsappRecallMessage(
      template: _settings?.whatsappRecallMessage,
      nome: a.customerName,
      servizio: a.service.name,
      prossimo: _data,
    );
    openExternal('https://wa.me/$digits?text=${Uri.encodeComponent(msg)}');
  }

  Future<void> _contattato() async {
    if (_salvato?.prossimoControllo == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Salva prima la data del prossimo controllo')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Segna contattato'),
        content: Text('Confermi di aver contattato ${_a?.customerName ?? 'il cliente'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Indietro')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Segna contattato')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final m = ScaffoldMessenger.of(context);
    try {
      await bookingService.segnaRecallContattato(widget.appointmentId);
      final dopo = await bookingService.recallById(widget.appointmentId);
      if (mounted) setState(() => _salvato = dopo);
      m.showSnackBar(const SnackBar(content: Text('Cliente segnato come contattato')));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('Operazione non riuscita: $e')));
    }
  }

  Future<void> _riapri() async {
    final m = ScaffoldMessenger.of(context);
    try {
      await bookingService.riapriRecall(widget.appointmentId);
      final dopo = await bookingService.recallById(widget.appointmentId);
      if (mounted) setState(() => _salvato = dopo);
      m.showSnackBar(const SnackBar(content: Text('Recall di nuovo da avvisare')));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('Operazione non riuscita: $e')));
    }
  }

  Future<void> _scegliData() async {
    final initial = _data ?? DateTime.now().add(const Duration(days: 30));
    final picked = await showDatePicker(
      context: context,
      helpText: 'Prossimo controllo',
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _data = DateTime(picked.year, picked.month, picked.day));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_errore != null || _a == null) {
      return Scaffold(
        appBar: const BrandAppBar(subtitle: 'Recall'),
        body: Center(child: Text(_errore ?? 'Prenotazione non disponibile')),
      );
    }
    final a = _a!;
    final lead = _settings?.recallLeadDays ?? 15;
    final stato = (_salvato ?? RecallRecord(appointmentId: a.id)).stato(lead, DateTime.now());
    final avviso = recallAvvisoDal(_data, lead);
    final ora = '${a.start.hour.toString().padLeft(2, '0')}:${a.start.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: const BrandAppBar(subtitle: 'Scheda recall'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(a.customerName.isEmpty ? 'Senza nome' : a.customerName, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Brand.primary)),
        const SizedBox(height: 4),
        Text('${a.service.name}\n${fmtRecallData(a.start)} ore $ora · Tel. ${a.phone}\nCodice ${a.shortCode}'),
        const SizedBox(height: 8),
        _StatoPill(stato),
        const SizedBox(height: 20),
        const Text('Esito', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final id in recallEsiti)
            ChoiceChip(
              label: Text(recallEsitoLabel[id]!),
              selected: _esito == id,
              selectedColor: switch (id) {
                'norma' => const Color(0xFFD9F2E3),
                'ricontrollare' => const Color(0xFFFFF1CC),
                _ => const Color(0xFFFADBD8),
              },
              onSelected: (on) => setState(() => _esito = on ? id : ''),
            ),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _note,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Note',
            hintText: 'Consiglio o farmaco indicato',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Prossimo controllo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(_data == null ? 'Data non inserita' : fmtRecallData(_data!), style: const TextStyle(fontSize: 18))),
          TextButton(onPressed: _scegliData, child: const Text('Scegli data')),
          if (_data != null) TextButton(onPressed: () => setState(() => _data = null), child: const Text('Togli')),
        ]),
        if (avviso != null)
          Text('Notifica ad admin e staff dal ${fmtRecallData(avviso)}', style: const TextStyle(color: Colors.black54)),
        const SizedBox(height: 16),
        SizedBox(
          height: 52,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _salva,
            icon: const Icon(Icons.save),
            label: const Text('Salva risultato', style: TextStyle(fontSize: 18)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
            onPressed: _whatsapp,
            icon: const Icon(Icons.chat),
            label: const Text('WhatsApp', style: TextStyle(fontSize: 18)),
          ),
        ),
        const SizedBox(height: 8),
        const Text('WhatsApp apre la chat e lascia questa scheda aperta. Lo stato non cambia da solo.', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 12),
        if (_salvato?.contattato == true) ...[
          Text('Contattato${_salvato?.contattatoAt != null ? ' il ${fmtRecallData(_salvato!.contattatoAt!)}' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E6B3A))),
          Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _riapri, child: const Text('Segna di nuovo da contattare'))),
        ] else
          SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _contattato,
              icon: const Icon(Icons.how_to_reg),
              label: const Text('Segna contattato', style: TextStyle(fontSize: 18)),
            ),
          ),
      ]),
    );
  }
}
