import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/main.dart';

void main() {
  testWidgets('app shell shows the placeholder home text', (tester) async {
    await tester.pumpWidget(const MainApp());

    expect(find.text('Hello World!'), findsOneWidget);
  });
}
