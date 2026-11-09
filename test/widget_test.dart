import 'package:flutter_test/flutter_test.dart';
import 'package:saree/main.dart';

void main() {
  testWidgets('shows setup guidance when Supabase is not configured', (tester) async {
    await tester.pumpWidget(const SareeApp());
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pumpAndSettle();
    expect(find.text('سريع يحتاج إلى ربط الخادم'), findsOneWidget);
  });
}
