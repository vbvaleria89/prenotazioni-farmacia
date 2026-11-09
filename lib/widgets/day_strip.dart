import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String dayChipLabel(DateTime d, {List<String> weekdays = const ['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom']}) {
  final wd = weekdays[(d.weekday - 1).clamp(0, 6)];
  return '$wd ${d.day}/${d.month}';
}

/// Consente il trascinamento orizzontale anche con mouse e trackpad (oltre al dito).
class HorizontalDragScrollBehavior extends MaterialScrollBehavior {
  const HorizontalDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };
}

/// Fila di giorni orizzontale: rotella, trascinamento, frecce, scrollbar e calendario.
class DayStrip extends StatefulWidget {
  const DayStrip({
    super.key,
    required this.days,
    required this.selected,
    required this.onSelected,
    this.labelOf = dayChipLabel,
  });

  final List<DateTime> days;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;
  final String Function(DateTime day) labelOf;

  @override
  State<DayStrip> createState() => _DayStripState();
}

class _DayStripState extends State<DayStrip> {
  final _controller = ScrollController();
  final _keys = <String, GlobalKey>{};

  static String _id(DateTime d) => '${d.year}-${d.month}-${d.day}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ensureSelectedVisible());
  }

  @override
  void didUpdateWidget(DayStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selChanged = widget.selected != null &&
        (oldWidget.selected == null || !sameDay(oldWidget.selected!, widget.selected!));
    if (selChanged || oldWidget.days.length != widget.days.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ensureSelectedVisible());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Esposto per i test.
  void ensureSelectedVisible({bool animate = true}) {
    if (!mounted || widget.selected == null) return;
    final ctx = _keys[_id(widget.selected!)]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.35,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      duration: animate ? const Duration(milliseconds: 250) : Duration.zero,
      curve: Curves.easeOut,
    );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    final pos = _controller.position;
    if (!pos.hasPixels || !pos.hasContentDimensions) return;
    final next = (_controller.offset + event.scrollDelta.dy + event.scrollDelta.dx).clamp(0.0, pos.maxScrollExtent);
    if (next != _controller.offset) _controller.jumpTo(next);
  }

  /// Sposta di circa una schermata (almeno ~7 chip / una settimana).
  void pageBy(int direction) {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    if (!pos.hasPixels || !pos.hasContentDimensions) return;
    final viewport = pos.viewportDimension;
    final step = viewport > 80 ? viewport * 0.9 : 7 * 96.0;
    final next = (pos.pixels + direction * step).clamp(0.0, pos.maxScrollExtent);
    _controller.animateTo(next, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _pickDate() async {
    if (widget.days.isEmpty || !mounted) return;
    final first = DateTime(widget.days.first.year, widget.days.first.month, widget.days.first.day);
    final last = DateTime(widget.days.last.year, widget.days.last.month, widget.days.last.day);
    var initial = widget.selected ?? first;
    initial = DateTime(initial.year, initial.month, initial.day);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final allowed = {for (final d in widget.days) DateTime(d.year, d.month, d.day)};
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      selectableDayPredicate: (d) => allowed.contains(DateTime(d.year, d.month, d.day)),
      helpText: 'Scegli il giorno',
      cancelText: 'Annulla',
      confirmText: 'OK',
    );
    if (picked == null || !mounted) return;
    for (final d in widget.days) {
      if (sameDay(d, picked)) {
        widget.onSelected(d);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final list = ScrollConfiguration(
      behavior: const HorizontalDragScrollBehavior(),
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: Scrollbar(
          controller: _controller,
          thumbVisibility: wide,
          interactive: true,
          child: ListView.builder(
            controller: _controller,
            primary: false,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: widget.days.length,
            itemBuilder: (context, i) {
              final d = widget.days[i];
              final key = _keys.putIfAbsent(_id(d), GlobalKey.new);
              final selected = widget.selected != null && sameDay(d, widget.selected!);
              return Padding(
                key: key,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: ChoiceChip(
                  label: Text(widget.labelOf(d)),
                  selected: selected,
                  onSelected: (_) => widget.onSelected(d),
                ),
              );
            },
          ),
        ),
      ),
    );

    return SizedBox(
      height: wide ? 68 : 60,
      child: Row(
        children: [
          if (wide)
            IconButton(
              tooltip: 'Giorni precedenti',
              onPressed: () => pageBy(-1),
              icon: const Icon(Icons.chevron_left),
            ),
          Expanded(child: list),
          if (wide)
            IconButton(
              tooltip: 'Giorni successivi',
              onPressed: () => pageBy(1),
              icon: const Icon(Icons.chevron_right),
            ),
          IconButton(
            tooltip: 'Scegli una data',
            onPressed: widget.days.isEmpty ? null : _pickDate,
            icon: const Icon(Icons.calendar_month),
          ),
        ],
      ),
    );
  }
}
