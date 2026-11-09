import 'package:flutter/material.dart';
import '../../app.dart';
import '../../models/appointment.dart';
import '../../models/device.dart';
import '../../widgets/device_unavailable_dialog.dart';
import '../../theme/brand.dart';
import 'slot_picker.dart' show hhmm;
import '../../widgets/slot_times.dart';
import '../../widgets/day_strip.dart';

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

Future<void> showRescheduleBlocked(BuildContext context) => showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Riprogrammazione non consentita'),
        content: const Text('Non è possibile riprogrammare la prenotazione a meno di 24 ore dall\'inizio. Contatta la farmacia.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Ho capito'))],
      ),
    );

/// Apre il flusso Riprogramma. Ritorna true se spostata.
Future<bool> apriRiprogramma(BuildContext context, Appointment a, {bool asStaff = false}) async {
  if (!asStaff && !a.clientMayCancel()) {
    await showRescheduleBlocked(context);
    return false;
  }
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ReschedulePage(appointment: a, asStaff: asStaff)));
  return ok == true;
}

class ReschedulePage extends StatefulWidget {
  const ReschedulePage({super.key, required this.appointment, this.asStaff = false});
  final Appointment appointment;
  final bool asStaff;
  @override
  State<ReschedulePage> createState() => _ReschedulePageState();
}

class _ReschedulePageState extends State<ReschedulePage> {
  List<DateTime> days = const [];
  DateTime? day;
  bool loading = true;
  bool saving = false;

  Appointment get a => widget.appointment;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final all = await bookingService.daysWithAvailability(daysAhead: 60);
      final ds = [for (final d in all) if (a.service.availableOn(d.weekday)) d];
      if (!mounted) return;
      setState(() {
        days = ds;
        day = ds.firstWhere((d) => _sameDay(d, a.start), orElse: () => ds.isEmpty ? a.start : ds.first);
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _pick(DateTime t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confermi il nuovo orario?'),
        content: Text('${a.service.name}\nDa: ${a.start.day}/${a.start.month} alle ${hhmm(a.start)}\nA: ${t.day}/${t.month} alle ${hhmm(t)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Indietro')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Riprogramma')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => saving = true);
    final m = ScaffoldMessenger.of(context);
    try {
      await bookingService.reschedule(a, t, asStaff: widget.asStaff);
      m.showSnackBar(SnackBar(content: Text('Prenotazione spostata al ${t.day}/${t.month} alle ${hhmm(t)}.')));
      if (mounted) Navigator.pop(context, true);
    } on DeviceUnavailableException catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      await showDeviceUnavailableDialog(context, e);
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      await showDialog<void>(context: context, builder: (c) => AlertDialog(
        title: const Text('Riprogrammazione non riuscita'),
        content: Text(e.message),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Ho capito'))],
      ));
    } catch (e) {
      if (mounted) setState(() => saving = false);
      m.showSnackBar(SnackBar(content: Text('Riprogrammazione non riuscita: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandAppBar(subtitle: 'Riprogramma · ${a.service.name}'),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Attuale: ${a.start.day}/${a.start.month}/${a.start.year} alle ${hhmm(a.start)}. Scegli il nuovo orario.', textAlign: TextAlign.center),
              ),
              if (days.isEmpty)
                const Expanded(child: Center(child: Text('Nessuna disponibilità nei prossimi giorni. Contatta la farmacia.')))
              else ...[
                DayStrip(
                  days: days,
                  selected: day,
                  onSelected: (d) => setState(() => day = d),
                ),
                Expanded(
                  child: day == null
                      ? const SizedBox()
                      : FutureBuilder<List<DateTime>>(
                          key: ValueKey(day),
                          future: bookingService.availableSlots(a.service, day!, excludeId: a.id),
                          builder: (context, snap) {
                            if (snap.hasError) return Center(child: Text('Errore: ${snap.error}'));
                            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                            final slots = snap.data!.where((t) => t != a.start && t.isAfter(DateTime.now())).toList();
                            if (slots.isEmpty) return const Center(child: Text('Nessuno slot libero in questo giorno'));
                            return SlotTimes(
                              slots: slots,
                              enabled: !saving,
                              onSelected: _pick,
                            );
                          },
                        ),
                ),
              ],
            ]),
    );
  }
}
