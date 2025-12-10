import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agui_dash_2/main.dart';

void main() {
  testWidgets('App loads chat screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: AgUiDashApp(),
      ),
    );

    // Verify that the chat screen title is displayed.
    expect(find.text('AG-UI Dashboard'), findsOneWidget);

    // Verify input field is present
    expect(find.byType(TextField), findsOneWidget);
  });
}
