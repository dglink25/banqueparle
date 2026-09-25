import 'package:flutter_test/flutter_test.dart';
import 'package:banqueparle/main.dart';

void main() {
  testWidgets('BanqueParleApp se lance sans erreur', (tester) async {
    await tester.pumpWidget(const BanqueParleApp());
    expect(find.text('BanqueParle'), findsOneWidget);
  });
}
