import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/main.dart';

void main() {
  testWidgets('Home screen shows the invitation action', (tester) async {
    currentDemoUserId = defaultDemoUserId;
    await tester.pumpWidget(const MyApp());

    expect(find.text('Geo Groups'), findsOneWidget);
    expect(find.text('Присоединиться по приглашению'), findsOneWidget);
  });

  testWidgets('light theme background is warm beige', (tester) async {
    await tester.pumpWidget(const MyApp());

    final theme = Theme.of(tester.element(find.text('Geo Groups')));

    expect(theme.scaffoldBackgroundColor, appBackgroundColor);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFFAF7F0));
    expect(theme.canvasColor, appBackgroundColor);
    expect(theme.bottomSheetTheme.backgroundColor, appBackgroundColor);
    expect(theme.dialogTheme.backgroundColor, appBackgroundColor);
    expect(theme.cardTheme.color, Colors.white);
    expect(theme.inputDecorationTheme.fillColor, Colors.white);
  });
}
