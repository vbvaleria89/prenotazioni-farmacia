import 'dart:convert';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../services/booking_service.dart';
import '../../models/fascia.dart';
import '../../models/settings.dart';
import '../../models/service_type.dart';
import '../../theme/brand.dart';

/// Disponibilità giornaliere: fasce in cui si può prenotare (solo admin).
class AvailabilityPage extends StatefulWidget {
  const AvailabilityPage({super.key});
  @override
  State<AvailabilityPage> createState() => _AvailabilityPageState();
}

String _hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
const _mesi = ['Gennaio', 'Febbraio', 'Marzo', 'Aprile', 'Maggio', 'Giugno', 'Luglio', 'Agosto', 'Settembre', 'Ottobre', 'Novembre', 'Dicembre'];
const _dowShort = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];
String _df(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class _AvailabilityPageState extends State<AvailabilityPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, List<Fascia>> _data = {};
  List<Employee> _emps = const [];
  late final _empSub = staffAuth.employees().listen((l) { if (mounted) setState(() => _emps = l.where((e) => e.attivo).toList()); });

  Map<String, String> _svcNames = {};
  /// Desktop (≥1000 px): calendario a sinistra, dettaglio del giorno a destra.
  bool _split = false;
  /// 'month' = griglia mensile, 'day' = dettaglio giorno pieno, 'list' = elenco del mese.
  String _view = 'month';
  /// Filtro persona (tutte le viste): null = tutte, '' = solo fasce «Farmacia».
  String? _filterEmp;

  final Set<String> _selected = {};
  bool _deleting = false;
  String _rowKey(DateTime d, Fascia f) => jsonEncode([
    BookingService.availKey(d), f.start, f.end, f.employeeId ?? '',
    (f.servizi.toSet().toList()..sort()),
  ]);
  void _filter(String? id) => setState(() { _filterEmp = id; _selected.clear(); });
  bool get _hasGeneric => _data.values.any((l) => l.any((f) => f.generica));
  List<Fascia> _applyPersonFilter(List<Fascia> list) {
    if (_filterEmp == null) return list;
    if (_filterEmp!.isEmpty) return [for (final f in list) if (f.generica) f];
    return [for (final f in list) if (f.employeeId == _filterEmp) f];
  }
  /// Dropdown ricercabile (tipo Excel) al posto della riga di chip.
  Widget _personFilterDropdown() {
    final entries = <DropdownMenuEntry<String>>[
      const DropdownMenuEntry(value: '__all__', label: 'Tutte', leadingIcon: Icon(Icons.people_outline, size: 18)),
      for (final e in _emps) DropdownMenuEntry(
        value: e.id,
        label: e.nome.isEmpty ? e.email : e.nome,
        leadingIcon: Icon(Icons.circle, size: 12, color: _colorOf(Fascia(0, 0, employeeId: e.id))),
      ),
      if (_hasGeneric) const DropdownMenuEntry(
        value: '__farmacia__',
        label: 'Farmacia (vecchie)',
        leadingIcon: Icon(Icons.storefront_outlined, size: 18),
      ),
    ];
    final current = _filterEmp == null ? '__all__' : (_filterEmp!.isEmpty ? '__farmacia__' : _filterEmp!);
    // Se il valore salvato non è più tra le opzioni (persona disattivata), torna a Tutte.
    final safe = entries.any((e) => e.value == current) ? current : '__all__';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Persona', style: TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 6),
      LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth.clamp(220.0, 420.0);
        return Align(
          alignment: Alignment.centerLeft,
          child: DropdownMenu<String>(
            key: ValueKey('pf-$safe-${_emps.length}-$_hasGeneric'),
            width: w,
            initialSelection: safe,
            enableFilter: true,
            requestFocusOnTap: true,
            leadingIcon: const Icon(Icons.search),
            hintText: 'Cerca o scegli persona',
            inputDecorationTheme: const InputDecorationTheme(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            dropdownMenuEntries: entries,
            onSelected: (v) {
              if (v == null || v == '__all__') {
                _filter(null);
              } else if (v == '__farmacia__') {
                _filter('');
              } else {
                _filter(v);
              }
            },
          ),
        );
      }),
    ]);
  }

  String get _monthLabel => '${_mesi[_month.month - 1]} ${_month.year}';
  bool get _isCurrentMonth {
    final n = DateTime.now();
    return _month.year == n.year && _month.month == n.month;
  }
  void _goMonth(DateTime m) => setState(() {
    _selected.clear();
    _month = DateTime(m.year, m.month);
    // Se il giorno selezionato non è in questo mese, ancoralo al 1° (o a oggi se mese corrente).
    if (_selDay.year != _month.year || _selDay.month != _month.month) {
      final n = DateTime.now();
      if (_month.year == n.year && _month.month == n.month) {
        _selDay = DateUtils.dateOnly(n);
      } else {
        _selDay = DateTime(_month.year, _month.month, 1);
      }
    }
  });
  void _goThisMonth() => _goMonth(DateTime.now());
  void _goPrevMonth() => _goMonth(DateTime(_month.year, _month.month - 1));
  void _shiftDay(int delta) => setState(() {
    _selDay = _selDay.add(Duration(days: delta));
    _month = DateTime(_selDay.year, _selDay.month);
    _selected.clear();
  });

  void _toggle(DateTime d, Fascia f, bool value) => setState(() {
    if (value) { _selected.add(_rowKey(d, f)); } else { _selected.remove(_rowKey(d, f)); }
  });
  Future<void> _deleteSelected(List<(DateTime, Fascia)> rows) async {
    if (_deleting) return;
    final chosen = rows.where((r) => _selected.contains(_rowKey(r.$1, r.$2))).toList();
    if (chosen.isEmpty) return;
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('Eliminare ${chosen.length} fasce?'),
      content: const Text('Verranno eliminate solo le fasce selezionate nel mese e nel filtro attuali. Le prenotazioni esistenti non saranno cancellate. L’operazione non è annullabile.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annulla')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Elimina fasce'))],
    ));
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      final count = await bookingService.deleteFasce(chosen);
      if (!mounted) return;
      setState(() => _selected.clear());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count fasce eliminate')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eliminazione non riuscita: $e')));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  String _svcText(Fascia f) => f.servizi.isEmpty ? 'Tutti i servizi' : f.servizi.map((x) => _svcNames[x] ?? x).join(', ');

  Future<void> _deleteFascia(DateTime d, Fascia x) async {
    final msg = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Eliminare la fascia?'),
      content: Text('${d.day}/${d.month}/${d.year} · ${x.chi} · ${_hm(x.start)}–${_hm(x.end)}'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annulla')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Elimina'))],
    ));
    if (ok != true) return;
    try {
      final cur = await bookingService.fasce(d);
      await bookingService.saveFasce(d, cur.where((y) => !y.same(x)).toList());
      msg.showSnackBar(const SnackBar(content: Text('Fascia eliminata')));
    } catch (e) { msg.showSnackBar(SnackBar(content: Text('Errore: $e'))); }
  }

  Widget _listView() {
    final rows = <(DateTime, Fascia)>[];
    final last = DateTime(_month.year, _month.month + 1, 0).day;
    for (var i = 1; i <= last; i++) {
      final d = DateTime(_month.year, _month.month, i);
      for (final f in _data[BookingService.availKey(d)] ?? const <Fascia>[]) {
        if (_filterEmp == null || (_filterEmp!.isEmpty ? f.generica : f.employeeId == _filterEmp)) rows.add((d, f));
      }
    }
    final visibleKeys = rows.map((r) => _rowKey(r.$1, r.$2)).toSet();
    _selected.retainAll(visibleKeys);
    final allSelected = rows.isNotEmpty && visibleKeys.every(_selected.contains);
    void selectAll(bool value) => setState(() { _selected.clear(); if (value) _selected.addAll(visibleKeys); });
    String dl(DateTime d) => '${_dowShort[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    Widget actions(DateTime d, Fascia f) => Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(tooltip: 'Modifica fascia', icon: const Icon(Icons.edit_outlined), onPressed: () => _openFasciaForm(seedDay: d, edit: f)),
      IconButton(tooltip: 'Elimina fascia', icon: const Icon(Icons.delete_outline), onPressed: () => _deleteFascia(d, f)),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('Elenco · $_monthLabel', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Brand.primary)),
      ),
      const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text('Si vedono solo le fasce del mese selezionato (usa le frecce o i tasti rapidi sopra).', style: TextStyle(fontSize: 12, color: Colors.black54)),
      ),
      if (rows.isNotEmpty) Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Checkbox(tristate: true, value: allSelected ? true : (_selected.isEmpty ? false : null),
            onChanged: _deleting ? null : (v) => selectAll(v ?? false)),
          const Text('Seleziona tutte filtrate'),
        ]),
        if (_selected.isNotEmpty) ...[
          FilledButton.icon(onPressed: _deleting ? null : () => _deleteSelected(rows),
            icon: const Icon(Icons.delete_outline), label: Text('Elimina selezionate (${_selected.length})')),
          TextButton(onPressed: _deleting ? null : () => selectAll(false), child: const Text('Deseleziona')),
        ],
      ]),
      if (_deleting) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
      if (rows.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text('Nessuna fascia in $_monthLabel.', textAlign: TextAlign.center))
      else LayoutBuilder(builder: (context, box) {
        if (box.maxWidth >= 700) {
          return SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box.maxWidth),
            child: DataTable(
              onSelectAll: _deleting ? null : (v) => selectAll(v ?? false),
              headingTextStyle: const TextStyle(fontWeight: FontWeight.w800, color: Brand.primary),
              dataRowMinHeight: 48, dataRowMaxHeight: 72,
              columns: const [DataColumn(label: Text('Data')), DataColumn(label: Text('Persona')), DataColumn(label: Text('Orario')), DataColumn(label: Text('Servizi')), DataColumn(label: Text('Azioni'))],
              rows: [for (final r in rows) DataRow(selected: _selected.contains(_rowKey(r.$1, r.$2)),
                onSelectChanged: _deleting ? null : (v) => _toggle(r.$1, r.$2, v ?? false), cells: [
                DataCell(Text(dl(r.$1), style: const TextStyle(fontWeight: FontWeight.w600))),
                DataCell(Text(r.$2.chi, style: TextStyle(color: _colorOf(r.$2), fontWeight: FontWeight.w800))),
                DataCell(Text('${_hm(r.$2.start)}–${_hm(r.$2.end)}')),
                DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: Text(_svcText(r.$2)))),
                DataCell(actions(r.$1, r.$2)),
              ])],
            ),
          ));
        }
        return Column(children: [for (final r in rows) Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Container(
            decoration: BoxDecoration(border: Border(left: BorderSide(color: _colorOf(r.$2), width: 4))),
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(children: [
              Checkbox(value: _selected.contains(_rowKey(r.$1, r.$2)), onChanged: _deleting ? null : (v) => _toggle(r.$1, r.$2, v ?? false)),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${dl(r.$1)} · ${_hm(r.$2.start)}–${_hm(r.$2.end)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(r.$2.chi, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _colorOf(r.$2))),
                const SizedBox(height: 2),
                Text(_svcText(r.$2), style: const TextStyle(fontSize: 13)),
              ])),
              actions(r.$1, r.$2),
            ]),
          ),
        )]);
      }),
    ]);
  }
  /// Telefono: celle con solo numero + pallini colorati per persona; il tap apre il dettaglio pieno.
  bool _narrow = false;
  DateTime _selDay = DateUtils.dateOnly(DateTime.now());
  static const _dowLong = ['Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica'];

  Widget _dayPanel() {
    final d = _selDay;
    final f = _applyPersonFilter(_data[BookingService.availKey(d)] ?? const <Fascia>[]);
    return Card(
      margin: EdgeInsets.only(top: _split ? 22 : 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_view == 'day') Row(children: [
            IconButton(tooltip: 'Giorno precedente', icon: const Icon(Icons.chevron_left), onPressed: () => _shiftDay(-1)),
            Expanded(child: Text('${_dowLong[d.weekday - 1]} ${d.day} ${_mesi[d.month - 1]} ${d.year}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Brand.primary))),
            IconButton(tooltip: 'Giorno successivo', icon: const Icon(Icons.chevron_right), onPressed: () => _shiftDay(1)),
          ]) else Text('${_dowLong[d.weekday - 1]} ${d.day} ${_mesi[d.month - 1]} ${d.year}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Brand.primary)),
          const SizedBox(height: 4),
          Text(f.isEmpty ? 'Nessuna fascia: giorno chiuso.' : '${f.length} ${f.length == 1 ? 'fascia' : 'fasce'}', style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 12),
          for (var i = 0; i < f.length; i++) Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(color: _colorOf(f[i]).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: _colorOf(f[i]), width: 4))),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f[i].chi, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _colorOf(f[i]))),
                const SizedBox(height: 2),
                Text('${_hm(f[i].start)} – ${_hm(f[i].end)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(f[i].servizi.isEmpty ? 'Tutti i servizi' : f[i].servizi.map((x) => _svcNames[x] ?? x).join(', '), style: const TextStyle(fontSize: 13)),
              ])),
              IconButton(tooltip: 'Modifica fascia', icon: const Icon(Icons.edit_outlined), onPressed: () => _openFasciaForm(seedDay: d, edit: f[i])),
              IconButton(tooltip: 'Elimina fascia', icon: const Icon(Icons.delete_outline), onPressed: () => _deleteFascia(d, f[i])),
            ]),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: () => _openFasciaForm(seedDay: d), icon: const Icon(Icons.add), label: const Text('Aggiungi fascia')),
          ]),
        ]),
      ),
    );
  }
  late final _svcSub = bookingService.watchServices().listen((l) { if (mounted) setState(() => _svcNames = {for (final s in l) s.id: s.name}); });
  @override
  void initState() { super.initState(); _empSub; _svcSub; }
  @override
  void dispose() { _empSub.cancel(); _svcSub.cancel(); super.dispose(); }

  static const _palette = [Color(0xFF1565C0), Color(0xFFC62828), Color(0xFF6A1B9A), Color(0xFFEF6C00), Color(0xFF00838F), Color(0xFF2E7D32), Color(0xFFAD1457)];
  Color _colorOf(Fascia f) {
    if (f.generica) return Colors.black54;
    final i = _emps.indexWhere((e) => e.id == f.employeeId);
    return _palette[(i < 0 ? f.employeeId.hashCode.abs() : i) % _palette.length];
  }

  /// Admin: quali servizi può fare ciascuna persona (nessuna selezione = tutti).
  Future<void> _openServizi() async {
    final msg = ScaffoldMessenger.of(context);
    final services = (await bookingService.watchServices().first).where((s) => s.attivo).toList();
    final current = await bookingService.staffServices();
    final sel = {for (final e in _emps) e.id: {...(current[e.id] ?? const <String>[])}};
    if (!mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      titlePadding: const EdgeInsets.fromLTRB(20, 8, 4, 0),
      title: Row(children: [
        const Expanded(child: Text('Persone e servizi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        IconButton(tooltip: 'Chiudi', icon: const Icon(Icons.close, size: 28), onPressed: () => Navigator.pop(c, false)),
      ]),
      content: SizedBox(width: MediaQuery.of(c).size.width < 600 ? MediaQuery.of(c).size.width : 640, height: MediaQuery.of(c).size.height * 0.75, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Text('Scegli quali servizi può fare ogni persona. Nessun servizio selezionato = può fare tutti i servizi attivi.', style: TextStyle(fontSize: 12, color: Colors.black54)),
        for (final e in _emps) ...[
          const SizedBox(height: 12),
          Text('${e.nome.isEmpty ? e.email : e.nome}${sel[e.id]!.isEmpty ? ' · tutti i servizi' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final sv in services) FilterChip(
              label: Text(sv.name, style: const TextStyle(fontSize: 12)),
              selected: sel[e.id]!.contains(sv.id),
              onSelected: (v) => set(() => v ? sel[e.id]!.add(sv.id) : sel[e.id]!.remove(sv.id)),
            ),
          ]),
        ],
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annulla')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salva')),
      ],
    )));
    if (ok != true) return;
    try {
      for (final e in _emps) {
        await bookingService.saveStaffServices(e.id, sel[e.id]!.toList());
      }
      msg.showSnackBar(const SnackBar(content: Text('Servizi per persona salvati')));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('Errore: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(_month.year, _month.month, 1);
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday - 1;
    return Scaffold(
      appBar: AppBar(title: const Text('Disponibilità')),
      body: StreamBuilder<Map<String, List<Fascia>>>(
        stream: bookingService.watchFasceMonth(_month),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Errore: ${snap.error}'));
          _data = snap.data ?? {};
          return AbsorbPointer(absorbing: _deleting, child: ListView(padding: const EdgeInsets.all(12), children: [
            const Text(
              'Tocca un giorno: imposti persona, fascia oraria, i giorni della settimana e il periodo Da–A.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () => _openFasciaForm(seedDay: _selDay),
                icon: const Icon(Icons.playlist_add, size: 20),
                label: const Text('Nuova fascia'),
              ),
              OutlinedButton.icon(
                onPressed: _emps.isEmpty ? null : _openServizi,
                icon: const Icon(Icons.medical_services_outlined, size: 20),
                label: const Text('Persone e servizi'),
              ),
            ]),
            if (_emps.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 10, runSpacing: 4, children: [
                for (final e in _emps) Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: _colorOf(Fascia(0, 0, employeeId: e.id)), shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(e.nome.isEmpty ? e.email : e.nome, style: const TextStyle(fontSize: 12)),
                ]),
              ]),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'month', label: Text('Mese'), icon: Icon(Icons.calendar_month)),
                ButtonSegment(value: 'day', label: Text('Giorno'), icon: Icon(Icons.today)),
                ButtonSegment(value: 'list', label: Text('Elenco'), icon: Icon(Icons.table_rows)),
              ],
              selected: {_view == 'cal' ? 'month' : _view},
              onSelectionChanged: (v) => setState(() {
                _view = v.first;
                if (_view == 'day' && (_selDay.year != _month.year || _selDay.month != _month.month)) {
                  final n = DateTime.now();
                  _selDay = (_month.year == n.year && _month.month == n.month)
                      ? DateUtils.dateOnly(n)
                      : DateTime(_month.year, _month.month, 1);
                }
              }),
            ),
            const SizedBox(height: 8),
            // Navigazione periodo: sempre legata al mese caricato da Firestore (niente «tutti i mesi»).
            if (_view != 'day') Row(children: [
              IconButton(tooltip: 'Mese precedente', icon: const Icon(Icons.chevron_left), onPressed: _goPrevMonth),
              Expanded(child: Text(_monthLabel, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              IconButton(tooltip: 'Mese successivo', icon: const Icon(Icons.chevron_right), onPressed: () => _goMonth(DateTime(_month.year, _month.month + 1))),
            ]),
            if (_view != 'day') Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: [
                FilterChip(
                  label: const Text('Questo mese'),
                  selected: _isCurrentMonth,
                  onSelected: (_) => _goThisMonth(),
                ),
                ActionChip(
                  avatar: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Mese precedente'),
                  onPressed: _goPrevMonth,
                ),
                if (_view == 'list') Text('Periodo elenco: $_monthLabel', style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ]),
            ),
            _personFilterDropdown(),
            const SizedBox(height: 12),
            if (_view == 'list') _listView()
            else if (_view == 'day') _dayPanel()
            else LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth >= 700;
              _split = box.maxWidth >= 1000;
              _narrow = !wide;
              final calW = _split ? box.maxWidth * 0.62 : box.maxWidth.clamp(0, 1100).toDouble();
              final ratio = wide ? 0.95 : 0.85;
              final Widget cal = Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: calW,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [for (final d in _dowShort)
                      Expanded(child: Center(child: Text(d, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black54))))]),
                    const SizedBox(height: 2),
                    GridView.count(
                      crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 2, crossAxisSpacing: 2, childAspectRatio: ratio,
                      children: [
                        for (var i = 0; i < lead; i++) const SizedBox(),
                        for (var d = 1; d <= days; d++) _cell(DateTime(_month.year, _month.month, d)),
                      ],
                    ),
                  ]),
                ),
              );
              if (!_split) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [cal, _dayPanel()]);
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                cal,
                const SizedBox(width: 16),
                Expanded(child: _dayPanel()),
              ]);
            }),
          ]));
        },
      ),
    );
  }

  Widget _cell(DateTime day) {
    final f = _applyPersonFilter(_data[BookingService.availKey(day)] ?? const []);
    final today = DateUtils.isSameDay(day, DateTime.now());
    const maxLines = 4;
    return InkWell(
      onTap: () => setState(() => _selDay = day),
      child: Container(
        margin: const EdgeInsets.all(1), padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: f.isEmpty ? Colors.grey.shade100 : Brand.green.withValues(alpha: 0.15),
          border: Border.all(color: DateUtils.isSameDay(day, _selDay) ? Brand.green : (today ? Brand.primary : Colors.grey.shade300), width: DateUtils.isSameDay(day, _selDay) ? 3 : (today ? 2 : 1)),
          borderRadius: BorderRadius.circular(5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${day.day}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          if (_narrow) Expanded(child: Wrap(spacing: 3, runSpacing: 3, children: [
            for (final c in {for (final r in f) _colorOf(r)}) Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          ])) else Expanded(child: ClipRect(child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final r in f.take(maxLines)) Container(
              margin: const EdgeInsets.only(top: 3), padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(color: _colorOf(r).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4), border: Border(left: BorderSide(color: _colorOf(r), width: 3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.chi, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: _colorOf(r), fontWeight: FontWeight.w800)),
                Text('${_hm(r.start)}–${_hm(r.end)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                Text(r.servizi.isEmpty ? 'Tutti i servizi' : r.servizi.map((x) => _svcNames[x] ?? x).join(', '),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.black87)),
              ]),
            ),
            if (f.length > maxLines) Text('+${f.length - maxLines} altre', style: const TextStyle(fontSize: 11)),
          ])))),
        ]),
      ),
    );
  }

  /// Tap giorno (o «Nuova fascia»): Inizio|Fine + giorni settimana + periodo Da–A.
  Future<void> _openFasciaForm({DateTime? seedDay, Fascia? edit}) async {
    final msg = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    final seed = seedDay ?? DateTime(now.year, now.month, now.day);
    var selected = <int>{seed.weekday};
    var start = 9 * 60;
    var end = 13 * 60;
    var from = DateTime(seed.year, seed.month, seed.day);
    var to = DateTime(seed.year, seed.month + 1, 0); // fine mese del giorno toccato
    if (to.isBefore(from)) to = from;

    // Fasce già presenti sul giorno toccato (per gestione rapida).
    var dayFasce = List<Fascia>.from(_data[BookingService.availKey(seed)] ?? const []);
    String? empId = _emps.length == 1 ? _emps.first.id : null;
    final allServices = (await bookingService.watchServices().first).where((s) => s.attivo).toList();
    final staffSvc = await bookingService.staffServices();
    final servizi = <String>{};
    List<ServiceType> servicesFor(String? id) => [for (final s in allServices) if (id != null && BookingService.canDo(staffSvc, id, s.id)) s];
    String svcName(String id) { final m = allServices.where((s) => s.id == id); return m.isEmpty ? id : m.first.name; }
    if (edit != null) {
      start = edit.start; end = edit.end; empId = edit.employeeId; servizi.addAll(edit.servizi);
      selected = <int>{seed.weekday}; to = from;
      if (servizi.isEmpty && empId != null) servizi.addAll(servicesFor(empId).map((x) => x.id));
      dayFasce.removeWhere((x) => x.same(edit));
    }
    if (!mounted) return;
    String nomeOf(String? id) { final e = _emps.where((x) => x.id == id); return e.isEmpty ? '' : (e.first.nome.isEmpty ? e.first.email : e.first.nome); }

    Future<void> openAndMaybeAgain() async {
      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (c) => StatefulBuilder(builder: (c, set) {
          Future<void> pickStart() async {
            final t = await showTimePicker(context: c, helpText: 'Inizio', initialTime: TimeOfDay(hour: start ~/ 60, minute: start % 60));
            if (t != null) set(() => start = t.hour * 60 + t.minute);
          }
          Future<void> pickEnd() async {
            final t = await showTimePicker(context: c, helpText: 'Fine', initialTime: TimeOfDay(hour: end ~/ 60, minute: end % 60));
            if (t != null) set(() => end = t.hour * 60 + t.minute);
          }
          Future<void> pickFrom() async {
            final d = await showDatePicker(context: c, helpText: 'Da', initialDate: from, firstDate: DateTime(2024), lastDate: DateTime(2100));
            if (d != null) set(() { from = DateTime(d.year, d.month, d.day); if (to.isBefore(from)) to = from; });
          }
          Future<void> pickTo() async {
            final d = await showDatePicker(context: c, helpText: 'A', initialDate: to.isBefore(from) ? from : to, firstDate: from, lastDate: DateTime(2100));
            if (d != null) set(() => to = DateTime(d.year, d.month, d.day));
          }
          final invalidTime = end <= start;
          final invalidDays = selected.isEmpty;
          final canSave = !invalidTime && !invalidDays && !to.isBefore(from) && empId != null && servizi.isNotEmpty;
          final sz = MediaQuery.of(c).size;
          return AlertDialog(
            insetPadding: EdgeInsets.symmetric(horizontal: sz.width < 600 ? 6 : 40, vertical: sz.width < 600 ? 10 : 24),
            titlePadding: const EdgeInsets.fromLTRB(20, 8, 4, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            title: Row(children: [
              Expanded(child: Text(seedDay != null
                  ? '${edit != null ? 'Modifica fascia' : 'Fascia'} · ${seed.day}/${seed.month}/${seed.year}'
                  : 'Nuova fascia', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              IconButton(tooltip: 'Chiudi', icon: const Icon(Icons.close, size: 28), onPressed: () => Navigator.pop(c)),
            ]),
            content: SizedBox(
              width: sz.width < 600 ? sz.width : 640,
              height: sz.height * 0.75,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (seedDay != null) ...[
                    const Text('Già su questo giorno', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 4),
                    if (dayFasce.isEmpty)
                      const Text('Nessuna fascia (giorno chiuso).', style: TextStyle(fontSize: 13))
                    else
                      for (var i = 0; i < dayFasce.length; i++)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${_hm(dayFasce[i].start)} – ${_hm(dayFasce[i].end)} · ${dayFasce[i].chi}', style: TextStyle(color: _colorOf(dayFasce[i]))),
                          subtitle: Text(dayFasce[i].servizi.isEmpty ? 'Tutti i servizi' : dayFasce[i].servizi.map(svcName).join(', '), style: const TextStyle(fontSize: 11)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => set(() => dayFasce.removeAt(i)),
                          ),
                        ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: dayFasce.isEmpty ? null : () => set(() => dayFasce.clear()),
                        icon: const Icon(Icons.clear_all, size: 18),
                        label: const Text('Svuota questo giorno'),
                      ),
                    ),
                    const Divider(height: 20),
                    const Text('Aggiungi fascia (anche su altri giorni)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                  ],
                  const Text('Persona *', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 6),
                  if (_emps.isEmpty) const Text('Nessun account staff/admin attivo.', style: TextStyle(color: Colors.red, fontSize: 13))
                  else Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final e in _emps) ChoiceChip(
                      label: Text(e.nome.isEmpty ? e.email : e.nome),
                      selected: empId == e.id,
                      onSelected: (_) => set(() { empId = e.id; servizi.removeWhere((x) => !servicesFor(empId).any((s) => s.id == x)); }),
                    ),
                  ]),
                  if (empId != null) ...[
                    const SizedBox(height: 14),
                    const Text('Servizi validi in questa fascia *', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final sv in servicesFor(empId)) FilterChip(
                        label: Text(sv.name, style: const TextStyle(fontSize: 12)),
                        selected: servizi.contains(sv.id),
                        onSelected: (v) => set(() => v ? servizi.add(sv.id) : servizi.remove(sv.id)),
                      ),
                    ]),
                    if (servizi.isEmpty) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Seleziona almeno un servizio', style: TextStyle(color: Colors.red, fontSize: 13))),
                  ],
                  if (empId == null) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Scegli la persona della fascia', style: TextStyle(color: Colors.red, fontSize: 13))),
                  const SizedBox(height: 14),
                  const Text('Giorni della settimana', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (var wd = 1; wd <= 7; wd++)
                      FilterChip(
                        label: Text(_dowShort[wd - 1]),
                        selected: selected.contains(wd),
                        onSelected: (v) => set(() { if (v) { selected.add(wd); } else { selected.remove(wd); } }),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  const Text('Fascia oraria', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Inizio', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 4),
                      OutlinedButton(
                        onPressed: pickStart,
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                        child: Text(_hm(start), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      ),
                    ])),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Fine', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 4),
                      OutlinedButton(
                        onPressed: pickEnd,
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                        child: Text(_hm(end), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      ),
                    ])),
                  ]),
                  if (invalidTime) const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('La fine deve essere dopo l\'inizio', style: TextStyle(color: Colors.red, fontSize: 13)),
                  ),
                  const SizedBox(height: 14),
                  const Text('Periodo di validità', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Da', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 4),
                      OutlinedButton(onPressed: pickFrom, child: Text(_df(from))),
                    ])),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('A', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 4),
                      OutlinedButton(onPressed: pickTo, child: Text(_df(to))),
                    ])),
                  ]),
                  if (invalidDays) const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Seleziona almeno un giorno', style: TextStyle(color: Colors.red, fontSize: 13)),
                  ),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Chiudi')),
              if (seedDay != null)
                TextButton(
                  onPressed: () => Navigator.pop(c, 'day_only'),
                  child: const Text('Salva solo giorno'),
                ),
              OutlinedButton.icon(
                onPressed: canSave ? () => Navigator.pop(c, 'save_more') : null,
                icon: const Icon(Icons.add),
                label: const Text('Salva e aggiungi altra fascia'),
              ),
              FilledButton(
                onPressed: canSave ? () => Navigator.pop(c, 'save') : null,
                child: const Text('Salva'),
              ),
            ],
          );
        }),
      );
      if (action == null) return;

      try {
        if (action == 'day_only' && seedDay != null) {
          // Applica eventuali delete/svuota sul giorno + nessuna nuova fascia se non serve.
          await bookingService.saveFasce(seed, dayFasce);
          if (!mounted) return;
          msg.showSnackBar(const SnackBar(content: Text('Giorno aggiornato')));
          return;
        }
        if (action != 'save' && action != 'save_more') return;

        // Se c'erano delete sul giorno seed, salvali prima (solo se seedDay).
        if (seedDay != null) {
          final original = _data[BookingService.availKey(seed)] ?? const [];
          bool same = original.length == dayFasce.length;
          if (same) {
            for (var i = 0; i < dayFasce.length; i++) {
              if (!original[i].same(dayFasce[i])) { same = false; break; }
            }
          }
          if (!same) {
            await bookingService.saveFasce(seed, dayFasce);
          }
        }

        var n = 0;
        for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
          if (!selected.contains(d.weekday)) continue;
          final existing = List<Fascia>.from(await bookingService.fasce(d));
          final fascia = Fascia(start, end, employeeId: empId, employeeNome: nomeOf(empId), servizi: servizi.toList());
          if (!existing.any((e) => e.same(fascia))) {
            existing.add(fascia);
            existing.sort((a, b) => a.start.compareTo(b.start));
          }
          await bookingService.saveFasce(d, existing);
          n++;
        }
        if (!mounted) return;
        msg.showSnackBar(SnackBar(content: Text('Fascia applicata a $n giorni')));
        if (action == 'save_more') {
          dayFasce = List<Fascia>.from(await bookingService.fasce(seed));
          final dur = end - start;
          start = end;
          end = (start + (dur > 0 ? dur : 60)).clamp(start + 15, 24 * 60 - 1);
          if (mounted) await openAndMaybeAgain();
          return;
        }
        final again = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Fascia salvata'),
            content: Text('Applicata a $n giorni. Vuoi aggiungere un’altra fascia?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Fine')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Aggiungi altra fascia')),
            ],
          ),
        );
        if (again == true && mounted) await openAndMaybeAgain();
      } catch (e) {
        msg.showSnackBar(SnackBar(content: Text('Errore: $e')));
      }
    }

    await openAndMaybeAgain();
  }
}
