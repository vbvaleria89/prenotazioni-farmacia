import 'package:farmacia_prenotazioni/widgets/day_strip.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final days = [for (var i = 0; i < 45; i++) DateTime(2026, 11, 9).add(Duration(days: i))];

  Future<void> pumpAt(WidgetTester tester, Size size, {required ValueNotifier<DateTime> selected}) async {
    final view = tester.view;
    view.physicalSize = size;
    view.devicePixelRatio = 1;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('it', 'IT'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('it', 'IT')],
        home: Scaffold(
          body: AnimatedBuilder(
            animation: selected,
            builder: (context, _) => DayStrip(
              days: days,
              selected: selected.value,
              onSelected: (d) => selected.value = d,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('desktop: frecce, calendario, scrollbar; rotella e frecce scorrono in orizzontale', (tester) async {
    final selected = ValueNotifier(DateTime(2026, 11, 9));
    addTearDown(selected.dispose);
    await pumpAt(tester, const Size(1280, 800), selected: selected);

    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month), findsOneWidget);
    expect(find.byType(Scrollbar), findsOneWidget);
    expect(const HorizontalDragScrollBehavior().dragDevices, containsAll({PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.touch}));

    final pos = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(pos.maxScrollExtent, greaterThan(0), reason: 'i giorni devono uscire dallo schermo');
    expect(pos.pixels, 0);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(pos.pixels, greaterThan(80));

    final afterArrow = pos.pixels;
    final box = tester.getRect(find.byType(DayStrip));
    await tester.sendEventToBinding(PointerScrollEvent(position: box.center, scrollDelta: const Offset(0, 200)));
    await tester.pump();
    expect(pos.pixels, greaterThan(afterArrow));
  });

  testWidgets('mobile: niente frecce laterali, calendario presente, swipe orizzontale', (tester) async {
    final selected = ValueNotifier(DateTime(2026, 11, 9));
    addTearDown(selected.dispose);
    await pumpAt(tester, const Size(390, 844), selected: selected);

    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.byIcon(Icons.calendar_month), findsOneWidget);

    final pos = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(pos.maxScrollExtent, greaterThan(0));
    await tester.drag(find.byType(ListView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(pos.pixels, greaterThan(50));
  });

  testWidgets('calendario apre il date picker nel periodo consentito', (tester) async {
    final selected = ValueNotifier(DateTime(2026, 11, 9));
    addTearDown(selected.dispose);
    await pumpAt(tester, const Size(1280, 800), selected: selected);
    await tester.tap(find.byIcon(Icons.calendar_month));
    await tester.pumpAndSettle();
    expect(find.text('Scegli il giorno'), findsOneWidget);
  });
}
