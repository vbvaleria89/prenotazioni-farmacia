import 'package:flutter_test/flutter_test.dart';
import 'package:farmacia_prenotazioni/app.dart';

void main() {
  testWidgets('Role picker mostra brand San Ciro', (tester) async {
    await tester.pumpWidget(const FarmaciaApp());
    expect(find.text('Farmacia San Ciro'), findsWidgets);
    expect(find.text('Sono un cliente'), findsOneWidget);
  });
}
