import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/main.dart';
import 'package:geo_groups/theme/app_theme.dart';

void main() {
  testWidgets('Home screen shows the invitation action', (tester) async {
    currentDemoUserId = defaultDemoUserId;
    await tester.pumpWidget(const MyApp());

    expect(find.text('Qunora'), findsOneWidget);
    expect(find.text('Присоединиться по приглашению'), findsOneWidget);
  });

  testWidgets('light theme background is warm beige', (tester) async {
    await tester.pumpWidget(const MyApp());

    final theme = Theme.of(tester.element(find.text('Qunora')));

    expect(theme.scaffoldBackgroundColor, AppColors.surface);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFFAFAFD));
    expect(theme.canvasColor, AppColors.surface);
    expect(theme.bottomSheetTheme.backgroundColor, AppColors.surface);
    expect(theme.dialogTheme.backgroundColor, AppColors.surface);
    expect(theme.cardTheme.color, AppColors.surface);
    expect(theme.inputDecorationTheme.fillColor, AppColors.surfaceContainer);
  });
}
