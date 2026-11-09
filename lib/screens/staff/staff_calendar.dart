import 'package:firebase_auth/firebase_auth.dart';
import '../client/reschedule_page.dart';
import 'ricetta_info.dart';
import 'edit_booking.dart';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../models/appointment.dart';
import '../../theme/brand.dart';
import '../client/slot_picker.dart' show hhmm;

const _navy = Color(0xFF32448C);
const _green = Color(0xFF2E9E4F);
const _mesi = ['Gennaio','Febbraio','Marzo','Aprile','Maggio','Giugno','Luglio','Agosto','Settembre','Ottobre','Novembre','Dicembre'];
const _giorniBrevi = ['Lun','Mar','Mer','Gio','Ven','Sab','Dom'];
const _giorniInit = ['L','M','M','G','V','S','D'];

/// Orario giornaliero stile Teams (farmacia).
const _oraInizio = 8;
const _oraFine = 20;
const _pxPerOra = 56.0;

/// Calendario prenotazioni staff stile Microsoft Teams: Mese | Settimana.
class StaffCalendar extends StatefulWidget {
  const StaffCalendar({super.key});
  @override
  State<StaffCalendar> createState() => _StaffCalendarState();
}

class _StaffCalendarState extends State<StaffCalendar> {
  /// 0 = mese, 1 = settimana
  int _mode = 0;
  /// true = solo appuntamenti dell'utente loggato; false = calendario generale (solo admin).
  bool _onlyMe = true;
  /// null finché non sappiamo il profilo; staff non-admin non può vedere «Tutti».
  bool? _isAdmin;
  late DateTime _month; // primo del mese
  late DateTime _weekStart; // lunedì della settimana
  late DateTime _sel;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month);
    _sel = DateTime(n.year, n.month, n.day);
    _weekStart = _mondayOf(_sel);
    staffAuth.profile().then((e) {
      if (!mounted) return;
      final admin = e?.isAdmin == true;
      setState(() {
        _isAdmin = admin;
        // Admin: default «Tutti». Staff: sempre «I miei», niente scelta.
        _onlyMe = !admin;
      });
    }).catchError((_) {
      if (mounted) setState(() { _isAdmin = false; _onlyMe = true; });
    });
  }

  DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  bool _same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _nav(IconData i, VoidCallback f) => IconButton(
        icon: Icon(i, size: 22, color: _navy),
        onPressed: f,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      );

  Color _colorFor(Appointment a) {
    switch (a.effectiveStatus()) {
      case AppointmentStatus.annullato:
        return Colors.grey;
      case AppointmentStatus.inAttesa:
        return const Color(0xFFE8A317);
      case AppointmentStatus.confermato:
        return _navy;
      case AppointmentStatus.completato:
        return _green;
    }
  }

  void _goToday() {
    final n = DateTime.now();
    final t = DateTime(n.year, n.month, n.day);
    setState(() {
      _sel = t;
      _month = DateTime(t.year, t.month);
      _weekStart = _mondayOf(t);
    });
  }

  void _prev() {
    setState(() {
      if (_mode == 0) {
        _month = DateTime(_month.year, _month.month - 1);
      } else {
        _weekStart = _weekStart.subtract(const Duration(days: 7));
        _sel = _weekStart;
      }
    });
  }

  void _next() {
    setState(() {
      if (_mode == 0) {
        _month = DateTime(_month.year, _month.month + 1);
      } else {
        _weekStart = _weekStart.add(const Duration(days: 7));
        _sel = _weekStart;
      }
    });
  }

  String get _title {
    if (_mode == 0) return '${_mesi[_month.month - 1]} ${_month.year}';
    final end = _weekStart.add(const Duration(days: 6));
    if (_weekStart.month == end.month) {
      return '${_weekStart.day}–${end.day} ${_mesi[_weekStart.month - 1]} ${_weekStart.year}';
    }
    return '${_weekStart.day} ${_mesi[_weekStart.month - 1]} – ${end.day} ${_mesi[end.month - 1]} ${_weekStart.year}';
  }

  DateTime get _rangeFrom => _mode == 0 ? _month : _weekStart;
  DateTime get _rangeTo => _mode == 0
      ? DateTime(_month.year, _month.month + 1)
      : _weekStart.add(const Duration(days: 7));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandAppBar(subtitle: 'Calendario prenotazioni'),
      body: StreamBuilder<List<Appointment>>(
        stream: bookingService.watchRange(_rangeFrom, _rangeTo),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Errore: ${snap.error}'));
          final uid = FirebaseAuth.instance.currentUser?.uid;
          // Staff ordinario: forzato su «I miei». Admin: rispetta il selettore.
          final forceMine = _isAdmin != true;
          final mineOnly = forceMine || _onlyMe;
          final all = (snap.data ?? const <Appointment>[]).where((a) => !mineOnly || (uid != null && a.employeeId == uid)).toList();
          return Column(children: [
            if (_isAdmin == true) Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Vista calendario', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 6),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('I miei'), icon: Icon(Icons.person_outline)),
                    ButtonSegment(value: false, label: Text('Tutti'), icon: Icon(Icons.groups_outlined)),
                  ],
                  selected: {_onlyMe},
                  onSelectionChanged: (v) => setState(() => _onlyMe = v.first),
                ),
              ]),
            ) else if (_isAdmin == false) const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 2),
              child: Text('Mostra solo i servizi assegnati a te.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(children: [
                Expanded(
                  child: Text(_title,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _navy),
                      overflow: TextOverflow.ellipsis),
                ),
                _nav(Icons.chevron_left, _prev),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: _navy,
                  ),
                  onPressed: _goToday,
                  child: const Text('Oggi'),
                ),
                _nav(Icons.chevron_right, _next),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Mese'), icon: Icon(Icons.calendar_view_month, size: 18)),
                  ButtonSegment(value: 1, label: Text('Settimana'), icon: Icon(Icons.view_week, size: 18)),
                ],
                selected: {_mode},
                onSelectionChanged: (s) {
                  final m = s.first;
                  setState(() {
                    _mode = m;
                    if (m == 1) {
                      _weekStart = _mondayOf(_sel);
                    } else {
                      _month = DateTime(_sel.year, _sel.month);
                    }
                  });
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (st) => st.contains(WidgetState.selected) ? Colors.white : _navy,
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (st) => st.contains(WidgetState.selected) ? _navy : Colors.transparent,
                  ),
                ),
              ),
            ),
            Expanded(
              child: !snap.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : (_mode == 0 ? _monthView(all) : _weekView(all)),
            ),
          ]);
        },
      ),
    );
  }

  // ─── MESE ───────────────────────────────────────────────────────────────

  Widget _monthView(List<Appointment> all) {
    final lead = _month.weekday - 1;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final dayApps = all.where((a) => _same(a.start, _sel)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 720;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              for (final d in _giorniInit)
                Expanded(
                  child: Center(
                    child: Text(d,
                        style: TextStyle(
                          fontSize: wide ? 11 : 10,
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                ),
            ]),
            const SizedBox(height: 2),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childAspectRatio: wide ? 1.05 : 0.85,
              children: [
                for (var i = 0; i < lead; i++) const SizedBox(),
                for (var d = 1; d <= days; d++)
                  _monthCell(
                    DateTime(_month.year, _month.month, d),
                    all
                        .where((a) =>
                            _same(a.start, DateTime(_month.year, _month.month, d)) &&
                            a.status != AppointmentStatus.annullato)
                        .toList()
                      ..sort((a, b) => a.start.compareTo(b.start)),
                    wide,
                  ),
              ],
            ),
          ]);
        }),
        const Divider(height: 14),
        Row(children: [
          Expanded(
            child: Text(
              '${_sel.day} ${_mesi[_sel.month - 1]} · ${dayApps.length} prenotazioni',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navy),
            ),
          ),
          TextButton.icon(
            onPressed: () => setState(() {
              _mode = 1;
              _weekStart = _mondayOf(_sel);
            }),
            icon: const Icon(Icons.view_week, size: 16),
            label: const Text('Settimana'),
            style: TextButton.styleFrom(foregroundColor: _navy, visualDensity: VisualDensity.compact),
          ),
        ]),
        if (dayApps.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Nessuna prenotazione'))),
        for (final a in dayApps) _bookingCard(a),
      ],
    );
  }

  Widget _monthCell(DateTime date, List<Appointment> apps, bool wide) {
    final sel = _same(date, _sel);
    final today = _same(date, DateTime.now());
    final show = apps.take(wide ? 3 : 2).toList();
    final extra = apps.length - show.length;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _sel = date),
        onDoubleTap: () => setState(() {
          _sel = date;
          _mode = 1;
          _weekStart = _mondayOf(date);
        }),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.fromLTRB(3, 2, 3, 2),
          decoration: BoxDecoration(
            color: sel
                ? (today ? _green.withValues(alpha: 0.18) : _navy.withValues(alpha: 0.10))
                : Colors.white,
            border: Border.all(
              color: sel
                  ? (today ? _green : _navy)
                  : (today ? Brand.primary : Colors.grey.shade300),
              width: sel || today ? 1.6 : 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: today
                    ? const BoxDecoration(color: _green, shape: BoxShape.circle)
                    : null,
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: today ? Colors.white : (sel ? _navy : Colors.black87),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 1),
            for (final a in show)
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: _colorFor(a).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    '${hhmm(a.start)} ${a.service.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600, height: 1.1),
                  ),
                ),
              ),
            if (extra > 0)
              Text('+$extra', style: TextStyle(fontSize: 9, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  // ─── SETTIMANA ──────────────────────────────────────────────────────────

  Widget _weekView(List<Appointment> all) {
    final days = List.generate(7, (i) => _weekStart.add(Duration(days: i)));
    final hours = _oraFine - _oraInizio;
    final gridH = hours * _pxPerOra;
    final hourColW = 44.0;

    return Column(children: [
      // Intestazione giorni
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 8, 4),
        child: Row(children: [
          SizedBox(width: hourColW),
          for (final d in days)
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _sel = DateTime(d.year, d.month, d.day)),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: _same(d, _sel) ? _navy : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Column(children: [
                    Text(_giorniBrevi[d.weekday - 1],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _same(d, DateTime.now()) ? _green : Colors.black54,
                        )),
                    const SizedBox(height: 2),
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: _same(d, DateTime.now())
                          ? const BoxDecoration(color: _green, shape: BoxShape.circle)
                          : (_same(d, _sel)
                              ? BoxDecoration(color: _navy.withValues(alpha: 0.12), shape: BoxShape.circle)
                              : null),
                      child: Text(
                        '${d.day}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _same(d, DateTime.now())
                              ? Colors.white
                              : (_same(d, _sel) ? _navy : Colors.black87),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: 8, bottom: 16),
          child: SizedBox(
            height: gridH,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Colonna ore
              SizedBox(
                width: hourColW,
                child: Stack(children: [
                  for (var h = _oraInizio; h < _oraFine; h++)
                    Positioned(
                      top: (h - _oraInizio) * _pxPerOra - 6,
                      right: 4,
                      child: Text(
                        '${h.toString().padLeft(2, '0')}:00',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                      ),
                    ),
                ]),
              ),
              // Giorni
              for (final d in days)
                Expanded(
                  child: _dayColumn(
                    d,
                    all
                        .where((a) =>
                            _same(a.start, d) && a.status != AppointmentStatus.annullato)
                        .toList(),
                    gridH,
                  ),
                ),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _dayColumn(DateTime day, List<Appointment> apps, double gridH) {
    final today = _same(day, DateTime.now());
    return Container(
      decoration: BoxDecoration(
        color: today ? _green.withValues(alpha: 0.04) : null,
        border: Border(left: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Stack(clipBehavior: Clip.hardEdge, children: [
        // Linee orarie
        for (var h = _oraInizio; h <= _oraFine; h++)
          Positioned(
            top: (h - _oraInizio) * _pxPerOra,
            left: 0,
            right: 0,
            child: Container(height: 1, color: Colors.grey.shade200),
          ),
        // Mezz'ore
        for (var h = _oraInizio; h < _oraFine; h++)
          Positioned(
            top: (h - _oraInizio) * _pxPerOra + _pxPerOra / 2,
            left: 0,
            right: 0,
            child: Container(height: 1, color: Colors.grey.shade100),
          ),
        // Eventi
        for (final a in apps) _eventBlock(a, gridH),
      ]),
    );
  }

  Widget _eventBlock(Appointment a, double gridH) {
    final startMin = a.start.hour * 60 + a.start.minute;
    final endMin = a.end.hour * 60 + a.end.minute;
    final base = _oraInizio * 60;
    final top = ((startMin - base) / 60.0) * _pxPerOra;
    final height = (((endMin - startMin).clamp(15, 24 * 60)) / 60.0) * _pxPerOra;
    final clampedTop = top.clamp(0.0, gridH - 8);
    final clampedH = height.clamp(18.0, gridH - clampedTop);
    final c = _colorFor(a);

    return Positioned(
      top: clampedTop,
      left: 2,
      right: 2,
      height: clampedH,
      child: Material(
        color: c.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(4),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _openDetail(a),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${hhmm(a.start)}–${hhmm(a.end)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700, height: 1.1),
              ),
              if (clampedH >= 28)
                Text(
                  a.service.name,
                  maxLines: clampedH >= 44 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.white, height: 1.15),
                ),
              if (clampedH >= 52 && a.customerName.isNotEmpty)
                Text(
                  a.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.9)),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  void _openDetail(Appointment a) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: _bookingCard(a, asSheet: true),
        ),
      ),
    );
  }

  // ─── CARD AZIONI (invariate) ────────────────────────────────────────────

  Widget _bookingCard(Appointment a, {bool asSheet = false}) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: asSheet ? 0 : 3),
      child: ListTile(
        dense: true,
        leading: Text(hhmm(a.start), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _navy)),
        title: Text('${a.service.name} · ${a.stanzaLabel}${a.customerName.isNotEmpty ? ' · ${a.customerName}' : ''}'),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if ((a.employeeNome ?? '').isNotEmpty) Text('Operatore: ${a.employeeNome}'),
          if (a.phone.isNotEmpty || (a.email ?? '').isNotEmpty)
            Text([
              if (a.phone.isNotEmpty) 'Tel. ${a.phone}',
              if ((a.email ?? '').isNotEmpty) a.email!,
            ].join(' · ')),
          Text('Codice ${a.id.substring(0, 6).toUpperCase()} · ${hhmm(a.start)}–${hhmm(a.end)} · ${a.esenzione ? 'Con esenzione' : 'Senza esenzione'}'),
          Wrap(spacing: 6, children: [PagatoBadge(a), RimborsoBadge(a)]),
          RicettaInfo(a),
          Wrap(spacing: 4, children: [
            TextButton.icon(
              onPressed: () async {
                final nav = Navigator.of(context);
                await apriCorrezioneCliente(context, a);
                if (asSheet && nav.mounted) nav.maybePop();
              },
              icon: const Icon(Icons.person_outline, size: 16, color: _navy),
              label: const Text('Correggi dati cliente'),
            ),
            if (a.status != AppointmentStatus.annullato)
              TextButton.icon(
                onPressed: () async {
                  final nav = Navigator.of(context);
                  await apriModificaPrenotazione(context, a);
                  if (asSheet && nav.mounted) nav.maybePop();
                },
                icon: const Icon(Icons.edit, size: 16, color: _navy),
                label: const Text('Modifica'),
              ),
            if (a.blocksRoom)
              TextButton.icon(
                onPressed: () async {
                  final nav = Navigator.of(context);
                  final ok = await apriRiprogramma(context, a, asStaff: true);
                  if (ok && asSheet && nav.mounted) nav.maybePop();
                },
                icon: const Icon(Icons.event_repeat, size: 16, color: _navy),
                label: const Text('Riprogramma'),
              ),
            if (a.status == AppointmentStatus.inAttesa)
              TextButton.icon(
                onPressed: () => _run(context, () => bookingService.confirm(a)),
                icon: const Icon(Icons.check, size: 16, color: Colors.green),
                label: const Text('Conferma'),
              ),
            if (a.blocksRoom)
              TextButton.icon(
                onPressed: () => annullaPrenotazione(context, a),
                icon: const Icon(Icons.close, size: 16, color: Colors.red),
                label: const Text('Annulla'),
              ),
            if (a.rimborsoPending)
              TextButton.icon(
                onPressed: () => segnaRimborsato(context, a),
                icon: const Icon(Icons.currency_exchange, size: 16, color: Color(0xFF9B2C2C)),
                label: const Text('Segna rimborsato'),
              ),
            TextButton.icon(
              onPressed: () => _run(context, () => bookingService.freeRoom(a)),
              icon: const Icon(Icons.meeting_room, size: 16, color: Colors.blue),
              label: const Text('Libera stanza'),
            ),
            if (!a.pagato)
              TextButton.icon(
                onPressed: () => segnaPagato(context, a),
                icon: const Icon(Icons.euro, size: 16, color: Color(0xFF2E9E4F)),
                label: const Text('Pagato'),
              ),
            WhatsAppClienteButton(a),
          ]),
        ]),
        trailing: StatoBadge(a.effectiveStatus()),
      ),
    );
  }
}

Future<void> _run(BuildContext context, Future<void> Function() f) async {
  final m = ScaffoldMessenger.of(context);
  try {
    await f();
  } catch (e) {
    m.showSnackBar(SnackBar(content: Text('Operazione non riuscita: $e')));
  }
}
