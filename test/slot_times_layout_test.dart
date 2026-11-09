import 'dart:io';
import 'dart:ui' as ui;

import 'package:farmacia_prenotazioni/widgets/slot_times.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final slots = [
    for (var h = 9; h <= 17; h++)
      for (var m = 0; m < 60; m += 15)
        if (!(h == 17 && m > 0)) DateTime(2026, 11, 10, h, m),
  ];

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    final view = tester.view;
    view.physicalSize = size;
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Holter Cardiaco')),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Scegli un orario', textAlign: TextAlign.center),
              ),
              Expanded(
                child: RepaintBoundary(
                  child: ColoredBox(
                    color: Colors.white,
                    child: SlotTimes(slots: slots, onSelected: (_) {}),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> savePng(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('/workspace/farmacia-prenotazioni/docs/screenshots');
      await dir.create(recursive: true);
      await File('${dir.path}/$name').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('desktop 1280: chip compatti ~88x40, non a tutta larghezza', (tester) async {
    await pumpAt(tester, const Size(1280, 800));
    final button = tester.getSize(find.byType(OutlinedButton).first);
    expect(button.width, closeTo(SlotTimes.chipWidth, 1));
    expect(button.height, closeTo(SlotTimes.chipHeight, 1));
    expect(button.width, lessThan(120));
    // Il blocco orari non si allarga a tutta la pagina.
    final wrap = tester.getSize(find.byType(Wrap));
    expect(wrap.width, lessThanOrEqualTo(SlotTimes.desktopMaxWidth + 1));
    expect(wrap.width, lessThan(1000));
    await savePng(tester, 'slot-times-1280.png');
  });

  testWidgets('mobile 390: area di tocco almeno 44 px', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    final button = tester.getSize(find.byType(OutlinedButton).first);
    expect(button.height, greaterThanOrEqualTo(SlotTimes.mobileMinHeight));
    // Ancora una griglia a 4 colonne, i bottoni riempiono la cella.
    expect(button.width, greaterThan(60));
    await savePng(tester, 'slot-times-390.png');
  });
}
