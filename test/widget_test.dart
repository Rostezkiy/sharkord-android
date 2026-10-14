import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sharkord_flutter/app.dart';

void main() {
  testWidgets('a first launch lands on the connect screen', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const SharkordApp());
    await tester.pumpAndSettle();

    expect(find.text('Sign in to your server'), findsOneWidget);
  });
}
