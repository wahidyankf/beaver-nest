import 'package:flutter_test/flutter_test.dart';

import 'package:hello_world/main.dart';

void main() {
  testWidgets('renders a hello-world greeting', (tester) async {
    await tester.pumpWidget(const HelloWorldApp());

    expect(find.text('Hello, World!'), findsOneWidget);
  });
}
