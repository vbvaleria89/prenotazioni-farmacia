import 'package:flutter/material.dart';

String slotHhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Elenco orari prenotabili: su schermi larghi chip compatti in Wrap (contenuto centrato);
/// su mobile griglia a 4 colonne con area di tocco di almeno 44 px.
class SlotTimes extends StatelessWidget {
  const SlotTimes({
    super.key,
    required this.slots,
    required this.onSelected,
    this.subtitleOf,
    this.enabled = true,
  });

  final List<DateTime> slots;
  final ValueChanged<DateTime> onSelected;
  final String? Function(DateTime time)? subtitleOf;
  final bool enabled;

  static const wideBreakpoint = 600.0;
  static const desktopMaxWidth = 840.0;
  static const chipWidth = 88.0;
  static const chipHeight = 40.0;
  static const chipHeightWithSubtitle = 52.0;
  static const mobileMinHeight = 44.0;

  bool _wide(BuildContext context) => MediaQuery.sizeOf(context).width >= wideBreakpoint;

  double _chipHeight(DateTime t) =>
      (subtitleOf?.call(t)?.isNotEmpty ?? false) ? chipHeightWithSubtitle : chipHeight;

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) return const SizedBox.shrink();
    final wide = _wide(context);
    if (wide) {
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: desktopMaxWidth),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in slots)
                  SizedBox(
                    width: chipWidth,
                    height: _chipHeight(t),
                    child: _button(context, t, wide: true),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      const cols = 4;
      const padding = 8.0;
      final hasSub = slots.any((t) => subtitleOf?.call(t)?.isNotEmpty ?? false);
      final cellW = (constraints.maxWidth - padding * 2) / cols;
      final minCellH = mobileMinHeight + 8;
      final preferred = cellW / (hasSub ? 1.4 : 2);
      final cellH = preferred < minCellH ? minCellH : preferred;
      return GridView.count(
        crossAxisCount: cols,
        padding: const EdgeInsets.all(padding),
        childAspectRatio: cellW / cellH,
        children: [
          for (final t in slots)
            Padding(
              padding: const EdgeInsets.all(4),
              child: _button(context, t, wide: false),
            ),
        ],
      );
    });
  }

  Widget _button(BuildContext context, DateTime t, {required bool wide}) {
    final sub = subtitleOf?.call(t);
    final time = Text(slotHhmm(t), style: const TextStyle(fontWeight: FontWeight.w600));
    final child = (sub == null || sub.isEmpty)
        ? time
        : Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              time,
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(sub, style: const TextStyle(fontSize: 10, color: Colors.black54)),
              ),
            ],
          );
    return OutlinedButton(
      onPressed: enabled ? () => onSelected(t) : null,
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: wide ? 4 : 8, vertical: 0),
        minimumSize: wide ? Size(chipWidth, _chipHeight(t)) : const Size(44, mobileMinHeight),
        maximumSize: wide ? Size(chipWidth, _chipHeight(t)) : null,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: wide ? VisualDensity.compact : VisualDensity.standard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: child,
    );
  }
}


/// Placeholder mentre arrivano gli orari, stessa densità dei chip desktop.
class SlotTimesSkeleton extends StatelessWidget {
  const SlotTimesSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < 12; i++)
                Container(
                  width: 88,
                  height: 40,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
