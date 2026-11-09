import '../../theme/brand.dart';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../services/booking_service.dart';
import '../../models/service_type.dart';
import '../../widgets/device_unavailable_dialog.dart';
import 'booking_confirm.dart';
import '../../widgets/slot_times.dart';
import '../../widgets/day_strip.dart';
import 'client_account_bar.dart';

String hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class SlotPicker extends StatefulWidget {
  final ServiceType service;
  final bool fromStaff;
  const SlotPicker({super.key, required this.service, this.fromStaff = false});
  @override
  State<SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends State<SlotPicker> {
  DateTime? day;
  List<DateTime> days = const [];
  bool loadingDays = true;
  String? daysError;
  Future<(List<DateTime>, bool)>? _dayFuture;
  DateTime? _futureDay;

  static const _weekdays = ['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom'];

  @override
  void initState() {
    super.initState();
    bookingService.addListener(_onBookingsChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    bookingService.removeListener(_onBookingsChanged);
    super.dispose();
  }

  void _onBookingsChanged() {
    if (!mounted || day == null) return;
    _startLoad(day!, force: true);
  }

  bool _same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  void _selectDay(DateTime d) {
    if (day != null && _same(day!, d) && _dayFuture != null) return;
    _startLoad(d);
  }

  void _startLoad(DateTime d, {bool force = false}) {
    setState(() {
      day = d;
      if (force || _futureDay == null || !_same(_futureDay!, d)) {
        _futureDay = d;
        _dayFuture = _load(d);
      }
    });
    _prefetchAround(d);
  }

  void _prefetchAround(DateTime d) {
    final i = days.indexWhere((x) => _same(x, d));
    if (i >= 0 && i + 1 < days.length) {
      bookingService.prefetchSlots(widget.service, days[i + 1]);
    }
  }

  Future<void> _bootstrap() async {
    try {
      final all = await bookingService.daysWithAvailability(daysAhead: 60);
      final forService = [for (final d in all) if (widget.service.availableOn(d.weekday)) d];
      // Non calcola tutti i giorni della striscia: solo il primo prenotabile (cache per il FutureBuilder).
      var selected = await bookingService.firstBookableDay(widget.service, daysAhead: 60);
      List<DateTime> shown = const [];
      if (widget.fromStaff) {
        final t = DateTime.now();
        final t0 = DateTime(t.year, t.month, t.day);
        shown = List.generate(45, (i) => DateTime(t0.year, t0.month, t0.day + i));
        selected ??= t0;
      } else {
        shown = forService;
      }
      if (!mounted) return;
      setState(() {
        days = shown;
        day = selected;
        loadingDays = false;
        daysError = null;
        if (selected != null) {
          _futureDay = selected;
          _dayFuture = _load(selected);
        }
      });
      if (selected != null) _prefetchAround(selected);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadingDays = false;
        daysError = e is StateError ? e.message : '$e';
        final now = DateTime.now();
        day = now;
        days = List.generate(7, (i) => now.add(Duration(days: i)));
      });
    }
  }

  /// Staff: per ogni slot, chi è libero (fascia + servizio + nessun'altra prenotazione). Mai mostrato al cliente.
  final Map<DateTime, List<(String, String)>> _free = {};

  Future<(List<DateTime>, bool)> _load(DateTime d) async {
    final slots = await bookingService.availableSlots(widget.service, d);
    var noFasce = false;
    if (widget.fromStaff && slots.isEmpty) noFasce = (await bookingService.availability(d)).isEmpty;
    if (widget.fromStaff) {
      _free.addAll(bookingService.slotPeople(widget.service, d));
    }
    return (slots, noFasce);
  }

  /// Staff: scelta persona. Una sola libera → preselezionata. Null = annulla; ('', '') = nessuna persona.
  Future<(String, String)?> _pickPerson(List<(String, String)> people, {bool optional = false}) async {
    if (people.length == 1 && !optional) return people.first;
    if (people.isEmpty) return ('', '');
    return showDialog<(String, String)>(context: context, builder: (c) => SimpleDialog(
      title: Text(optional ? 'Con chi? (facoltativo)' : 'Chi è disponibile'),
      children: [
        for (final p in people) SimpleDialogOption(onPressed: () => Navigator.pop(c, p),
            child: Row(children: [const Icon(Icons.person, size: 20), const SizedBox(width: 8), Text(p.$2, style: const TextStyle(fontSize: 16))])),
        if (optional) SimpleDialogOption(onPressed: () => Navigator.pop(c, ('', '')), child: const Text('Nessuna persona')),
      ],
    ));
  }

  Future<void> _openStaffSlot(DateTime t) async {
    final p = await _pickPerson(_free[t] ?? const []);
    if (p == null || !mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => BookingConfirm(service: widget.service, start: t, fromStaff: true,
        employeeId: p.$1.isEmpty ? null : p.$1, employeeNome: p.$1.isEmpty ? null : p.$2)));
  }

  Future<void> _manual(DateTime d) async {
    final t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Orario del servizio',
      cancelText: 'Annulla',
      confirmText: 'OK',
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null || !mounted) return;
    final start = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    if (start.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Orario già passato')));
      return;
    }
    if (widget.service.usesDevice) {
      final next = await bookingService.nextDeviceBookable(widget.service, start);
      final busy = await bookingService.deviceBusyMessage(widget.service, start);
      if (busy != null && mounted) {
        await showDeviceUnavailableDialog(context, DeviceUnavailableException(widget.service.deviceLabel, nextFree: next));
        return;
      }
    }
    final svc = await bookingService.staffServices();
    final all = (await staffAuth.employees().first).where((e) => e.attivo && BookingService.canDo(svc, e.id, widget.service.id)).map((e) => (e.id, e.nome.isEmpty ? e.email : e.nome)).toList();
    if (!mounted) return;
    final p = await _pickPerson(all, optional: true);
    if (p == null || !mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => BookingConfirm(service: widget.service, start: start, fromStaff: true, manualTime: true,
        employeeId: p.$1.isEmpty ? null : p.$1, employeeNome: p.$1.isEmpty ? null : p.$2)));
  }

  String _chipLabel(DateTime d) {
    final wd = _weekdays[(d.weekday - 1).clamp(0, 6)];
    return '$wd ${d.day}/${d.month}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandAppBar(subtitle: widget.service.name),
      body: Column(children: [
        if (!widget.fromStaff) const ClientAccountBar(),
        if (loadingDays)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (days.isEmpty && !widget.fromStaff)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  daysError ?? 'Nessuna disponibilità nei prossimi 60 giorni.\nImposta le fasce in Area admin → Disponibilità.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else ...[
          DayStrip(
            days: days,
            selected: day,
            onSelected: _selectDay,
            labelOf: _chipLabel,
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                final selected = day;
                if (selected == null || _dayFuture == null) {
                  return const Center(child: Text('Seleziona un giorno'));
                }
                return FutureBuilder(
                  future: _dayFuture,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      final e = snap.error;
                      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(e is StateError ? e.message : 'Errore nel caricamento degli orari: $e', textAlign: TextAlign.center)));
                    }
                    if (!snap.hasData) return const SlotTimesSkeleton();
                    final (slots, noFasce) = snap.data!;
                    if (slots.isEmpty) {
                      if (widget.fromStaff && noFasce) {
                        return Center(child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Text('Nessuna disponibilità impostata per questo giorno.\nPuoi inserire l\'orario del servizio a mano.', textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              icon: const Icon(Icons.schedule),
                              label: const Text('Inserisci orario a mano'),
                              onPressed: () => _manual(selected),
                            ),
                          ]),
                        ));
                      }
                      return const Center(child: Text('Nessuno slot libero in questo giorno'));
                    }
                    return SlotTimes(
                      slots: slots,
                      subtitleOf: widget.fromStaff
                          ? (t) {
                              final people = _free[t] ?? const [];
                              if (people.isEmpty) return null;
                              return people.map((p) => p.$2.split(' ').first).join(', ');
                            }
                          : null,
                      onSelected: (t) => widget.fromStaff
                          ? _openStaffSlot(t)
                          : Navigator.push(context, MaterialPageRoute(builder: (_) => BookingConfirm(service: widget.service, start: t, fromStaff: widget.fromStaff))),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ]),
    );
  }
}
