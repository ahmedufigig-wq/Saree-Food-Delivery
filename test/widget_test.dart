import 'package:flutter_test/flutter_test.dart';
import 'package:saree/main.dart';

void main() {
  testWidgets('renders the Saree application shell', (tester) async {
    await tester.pumpWidget(const SareeApp());
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SareeApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
