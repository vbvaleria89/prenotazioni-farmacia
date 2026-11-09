import '../client/reschedule_page.dart';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../models/appointment.dart';
import '../../theme/brand.dart';
import '../client/slot_picker.dart' show hhmm;
import 'ricetta_info.dart';
import 'edit_booking.dart';
import '../../services/open_link.dart';

/// Elenco prenotazioni (tabella con ricerca e azioni su riga).
class StaffBookingList extends StatefulWidget {
  const StaffBookingList({super.key});
  @override
  State<StaffBookingList> createState() => _StaffBookingListState();
}

class _StaffBookingListState extends State<StaffBookingList> {
  String _q = '';
  int _giorniPassati = 7;
  /// Giorno singolo selezionato; null = modalità intervallo.
  DateTime? _giorno = _oggi();
  int _sortCol = 0;
  bool _asc = true;

  static DateTime _oggi() { final n = DateTime.now(); return DateTime(n.year, n.month, n.day); }
  bool _same(DateTime? a, DateTime b) => a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  void _setGiorno(DateTime? d) => setState(() { _giorno = d; _sel.clear(); _load(); });

  Future<void> _pickGiorno() async {
    final d = await showDatePicker(context: context, initialDate: _giorno ?? _oggi(),
        firstDate: DateTime(2024), lastDate: DateTime(2030), helpText: 'Scegli il giorno', cancelText: 'Annulla', confirmText: 'OK');
    if (d != null) _setGiorno(d);
  }

  int _cmp(Appointment a, Appointment b) {
    int r;
    switch (_sortCol) {
      case 2: r = a.customerName.toLowerCase().compareTo(b.customerName.toLowerCase());
      case 3: r = a.phone.compareTo(b.phone);
      case 4: r = a.service.name.toLowerCase().compareTo(b.service.name.toLowerCase());
      case 5: r = a.id.substring(0, 6).toUpperCase().compareTo(b.id.substring(0, 6).toUpperCase());
      case 6: r = a.status.index.compareTo(b.status.index);
      case 7: r = (a.pagato ? 1 : 0).compareTo(b.pagato ? 1 : 0);
      default: r = 0;
    }
    if (r == 0) r = a.start.compareTo(b.start);
    return _asc ? r : -r;
  }

  void _sort(int i, bool asc) => setState(() { _sortCol = i == 1 ? 0 : i; _asc = asc; });
  bool _soloAttive = false;
  late Stream<List<Appointment>> _stream;
  final Set<String> _sel = {};
  bool _bulkBusy = false;

  Future<void> _bulk(List<Appointment> rows, bool pagamento) async {
    final m = ScaffoldMessenger.of(context);
    final target = rows.where((a) => _sel.contains(a.id)).where((a) => pagamento
        ? (!a.pagato && a.status != AppointmentStatus.annullato)
        : (a.blocksRoom && a.status == AppointmentStatus.inAttesa)).toList();
    if (target.isEmpty) { m.showSnackBar(const SnackBar(content: Text('Nessuna prenotazione selezionata idonea'))); return; }
    String? metodo;
    if (pagamento) { metodo = await scegliMetodoPagamento(context); if (metodo == null) return; }
    setState(() => _bulkBusy = true);
    var ok = 0, ko = 0;
    await Future.wait(target.map((a) async {
      try { pagamento ? await bookingService.setPagato(a, true, metodoPagamento: metodo) : await bookingService.confirm(a); ok++; } catch (_) { ko++; }
    }));
    if (!mounted) return;
    setState(() { _bulkBusy = false; _sel.clear(); });
    m.showSnackBar(SnackBar(content: Text('$ok ${pagamento ? 'segnate pagate' : 'confermate'}${ko > 0 ? ' · $ko non riuscite' : ''}')));
  }

  /// WhatsApp di gruppo: una chat alla volta (il browser blocca più finestre insieme;
  /// senza WhatsApp Cloud API l'operatore preme Invio in ciascuna chat).
  Future<void> _waGruppo(List<Appointment> list) async {
    var i = 0;
    await showDialog<void>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) {
      final fine = i >= list.length;
      final a = fine ? null : list[i];
      return AlertDialog(
        title: Text(fine ? 'Fatto: ${list.length} chat aperte' : 'WhatsApp ${i + 1} di ${list.length}'),
        content: Text(fine
            ? 'Controlla di aver premuto Invio in ogni chat WhatsApp.'
            : '${a!.customerName} · ${a.phone}\n${_data(a.start)} ${hhmm(a.start)} · ${a.service.name} · ${a.stanzaLabel}\n\n'
              'Si apre WhatsApp con il messaggio già scritto: premi Invio, poi torna qui per il successivo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(fine ? 'Chiudi' : 'Interrompi')),
          if (!fine) TextButton(onPressed: () => set(() => i++), child: const Text('Salta')),
          if (!fine) FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
              onPressed: () { openExternal(waClienteLink(a!)!); set(() => i++); },
              icon: const Icon(Icons.chat), label: const Text('Apri WhatsApp')),
        ],
      );
    }));
  }

  Widget _barra(List<Appointment> rows) {
    final sel = rows.where((a) => _sel.contains(a.id)).toList();
    if (sel.isEmpty) return const SizedBox.shrink();
    final daConf = sel.where((a) => a.blocksRoom && a.status == AppointmentStatus.inAttesa).length;
    final waSel = sel.where((a) => waClienteLink(a) != null).toList();
    return Material(color: Colors.blue.shade50, child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('${sel.length} selezionate', style: const TextStyle(fontWeight: FontWeight.bold)),
        FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: _bulkBusy || daConf == 0 ? null : () => _bulk(rows, false), icon: const Icon(Icons.check), label: Text('Conferma ($daConf)')),
        FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
            onPressed: waSel.isEmpty ? null : () => _waGruppo(waSel), icon: const Icon(Icons.chat), label: Text('WhatsApp (${waSel.length})')),
        TextButton(onPressed: () => setState(_sel.clear), child: const Text('Deseleziona')),
        if (_bulkBusy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
    ));
  }

  @override
  void initState() { super.initState(); _load(); }

  void _load() {
    if (_giorno != null) { _stream = bookingService.watchDay(_giorno!); return; }
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day).subtract(Duration(days: _giorniPassati));
    _stream = bookingService.watchRange(from, from.add(Duration(days: _giorniPassati + 120)));
  }

  bool _match(Appointment a) {
    if (_soloAttive && !a.blocksRoom) return false;
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return true;
    final code = a.id.substring(0, 6).toLowerCase();
    return [a.phone, code, a.codiceFiscale ?? '']
        .any((s) => s.toLowerCase().contains(q));
  }

  Future<void> _run(Future<void> Function() f) async {
    final m = ScaffoldMessenger.of(context);
    try { await f(); } catch (e) { m.showSnackBar(SnackBar(content: Text('Operazione non riuscita: $e'))); }
  }

  String _data(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  Widget _azioni(Appointment a) => Wrap(spacing: 2, children: [
          IconButton(tooltip: 'Correggi dati cliente', onPressed: () => apriCorrezioneCliente(context, a), icon: const Icon(Icons.person_outline, color: Brand.primary)),
        if (a.status != AppointmentStatus.annullato)
          IconButton(tooltip: 'Modifica', onPressed: () => apriModificaPrenotazione(context, a), icon: const Icon(Icons.edit, color: Color(0xFF32448C))),
        if (a.blocksRoom)
          IconButton(tooltip: 'Riprogramma', onPressed: () => apriRiprogramma(context, a, asStaff: true), icon: const Icon(Icons.event_repeat, color: Color(0xFF32448C))),
        if (a.blocksRoom && a.status == AppointmentStatus.inAttesa)
          IconButton(tooltip: 'Conferma', onPressed: () => _run(() => bookingService.confirm(a)), icon: const Icon(Icons.check, color: Colors.green)),
        if (a.blocksRoom) IconButton(tooltip: 'Annulla', onPressed: () => annullaPrenotazione(context, a), icon: const Icon(Icons.close, color: Colors.red)),
        if (a.rimborsoPending) IconButton(tooltip: 'Segna rimborsato', onPressed: () => segnaRimborsato(context, a), icon: const Icon(Icons.currency_exchange, color: Color(0xFF9B2C2C))),
        if (a.blocksRoom) IconButton(tooltip: 'Libera stanza', onPressed: () => _run(() => bookingService.freeRoom(a)), icon: const Icon(Icons.meeting_room, color: Colors.blue)),
        if (!a.pagato && a.status != AppointmentStatus.annullato)
          TextButton.icon(onPressed: () => segnaPagato(context, a), icon: const Icon(Icons.euro, size: 18, color: Color(0xFF2E9E4F)), label: const Text('Pagato')),
        WhatsAppClienteButton(a),
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandAppBar(subtitle: 'Elenco prenotazioni'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 380, child: TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cerca codice fiscale, codice prenotazione o telefono', border: OutlineInputBorder(), isDense: true),
              onChanged: (v) => setState(() => _q = v),
            )),
            ChoiceChip(label: const Text('Oggi'), selected: _same(_giorno, _oggi()), onSelected: (_) => _setGiorno(_oggi())),
            ChoiceChip(label: const Text('Domani'), selected: _same(_giorno, _oggi().add(const Duration(days: 1))), onSelected: (_) => _setGiorno(_oggi().add(const Duration(days: 1)))),
            ActionChip(avatar: const Icon(Icons.event, size: 18),
                label: Text(_giorno != null && !_same(_giorno, _oggi()) && !_same(_giorno, _oggi().add(const Duration(days: 1)))
                    ? '${_data(_giorno!)}/${_giorno!.year}' : 'Scegli giorno…'),
                onPressed: _pickGiorno),
            ChoiceChip(label: const Text('Intervallo'), selected: _giorno == null, onSelected: (_) => _setGiorno(null)),
            if (_giorno == null) DropdownButton<int>(value: _giorniPassati, items: const [
              DropdownMenuItem(value: 0, child: Text('Da oggi')),
              DropdownMenuItem(value: 7, child: Text('Da 7 giorni fa')),
              DropdownMenuItem(value: 30, child: Text('Da 30 giorni fa')),
              DropdownMenuItem(value: 90, child: Text('Da 90 giorni fa')),
            ], onChanged: (v) => setState(() { _giorniPassati = v ?? 7; _load(); })),
            FilterChip(label: const Text('Solo attive'), selected: _soloAttive, onSelected: (v) => setState(() => _soloAttive = v)),
          ]),
        ),
        Expanded(child: StreamBuilder<List<Appointment>>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Errore: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snap.data!.where(_match).toList()..sort(_cmp);
            if (rows.isEmpty) return const Center(child: Text('Nessuna prenotazione'));
            return Column(children: [_barra(rows), Expanded(child: LayoutBuilder(builder: (context, c) {
              if (c.maxWidth < 800) {
                return ListView(children: [
                  CheckboxListTile(controlAffinity: ListTileControlAffinity.leading, title: const Text('Seleziona tutte'),
                      value: rows.isNotEmpty && rows.every((a) => _sel.contains(a.id)),
                      onChanged: (v) => setState(() => v == true ? _sel.addAll(rows.map((a) => a.id)) : _sel.removeAll(rows.map((a) => a.id)))),
                  for (final a in rows) Card(child: ListTile(
                  leading: Checkbox(value: _sel.contains(a.id), onChanged: (v) => setState(() => v == true ? _sel.add(a.id) : _sel.remove(a.id))),
                  title: Text('${_data(a.start)} ${hhmm(a.start)} · ${a.customerName}'),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${a.service.name} · ${a.stanzaLabel} · Tel. ${a.phone}'),
                    Wrap(spacing: 6, children: [StatoBadge(a.effectiveStatus()), PagatoBadge(a), RimborsoBadge(a)]), _azioni(a)]),
                ))]);
              }
              return SingleChildScrollView(child: SizedBox(width: c.maxWidth, child: DataTable(
                showCheckboxColumn: true,
                sortColumnIndex: _sortCol, sortAscending: _asc,
                onSelectAll: (v) => setState(() => v == true ? _sel.addAll(rows.map((a) => a.id)) : _sel.removeAll(rows.map((a) => a.id))),
                columnSpacing: 16, dataRowMinHeight: 44, dataRowMaxHeight: 56,
                columns: [
                  DataColumn(label: const Text('Data'), onSort: _sort), DataColumn(label: const Text('Ora'), onSort: _sort), DataColumn(label: const Text('Cliente'), onSort: _sort),
                  DataColumn(label: const Text('Telefono'), onSort: _sort), DataColumn(label: const Text('Servizio'), onSort: _sort), DataColumn(label: const Text('Codice'), onSort: _sort),
                  DataColumn(label: const Text('Stato'), onSort: _sort), DataColumn(label: const Text('Pagamento'), onSort: _sort), const DataColumn(label: Text('Azioni')),
                ],
                rows: [for (final a in rows) DataRow(selected: _sel.contains(a.id), onSelectChanged: (v) => setState(() => v == true ? _sel.add(a.id) : _sel.remove(a.id)), cells: [
                  DataCell(Text(_data(a.start))),
                  DataCell(Text(hhmm(a.start))),
                  DataCell(Text(a.customerName)),
                  DataCell(Text(a.phone)),
                  DataCell(Text('${a.service.name} · ${a.stanzaLabel}')),
                  DataCell(Text(a.id.substring(0, 6).toUpperCase())),
                  DataCell(StatoBadge(a.effectiveStatus())),
                  DataCell(Wrap(spacing: 4, children: [PagatoBadge(a), RimborsoBadge(a)])),
                  DataCell(_azioni(a)),
                ])],
              )));
            }))]);
          },
        )),
      ]),
    );
  }
}
