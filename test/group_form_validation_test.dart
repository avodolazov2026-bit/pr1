import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/created_groups_screen.dart';
import 'package:geo_groups/geo_group.dart';

void main() {
  setUp(() {
    currentDemoUserId = defaultDemoUserId;
  });

  testWidgets(
    'create form shows a past start immediately and enables after a valid schedule',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en', 'US'),
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(alwaysUse24HourFormat: true),
              child: child!,
            );
          },
          home: const CreatedGroupsScreen(),
        ),
      );
      await tester.tap(find.text('Добавить группу'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Поход');
      await tester.pump();

      final now = DateTime.now();
      await tester.tap(find.textContaining('Время начала'));
      await tester.pumpAndSettle();
      await _enterTime(tester, TimeOfDay(hour: now.hour, minute: now.minute));

      expect(
        find.text('Время начала должно быть позже текущего времени'),
        findsWidgets,
      );
      expect(_createButton(tester).onPressed, isNull);

      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final dayAfter = DateTime(now.year, now.month, now.day + 2);
      await tester.tap(find.textContaining('Дата начала'));
      await tester.pumpAndSettle();
      await _enterDate(tester, tomorrow);
      await tester.tap(find.text('Дата завершения'));
      await tester.pumpAndSettle();
      await _enterDate(tester, dayAfter);
      await tester.tap(find.text('Время завершения'));
      await tester.pumpAndSettle();
      await _enterTime(tester, const TimeOfDay(hour: 12, minute: 0));

      expect(
        find.text('Время начала должно быть позже текущего времени'),
        findsNothing,
      );
      expect(
        find.text('Время окончания должно быть позже времени начала'),
        findsNothing,
      );
      expect(find.text('Выберите дату и время завершения'), findsNothing);
      expect(find.text('Введите название группы'), findsNothing);
      expect(_createButton(tester).onPressed, isNotNull);
    },
  );
}

FilledButton _createButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Создать'),
  );
}

Future<void> _enterTime(WidgetTester tester, TimeOfDay time) async {
  await tester.tap(find.byTooltip('Switch to text input mode'));
  await tester.pumpAndSettle();
  final fields = find.descendant(
    of: find.byType(Dialog),
    matching: find.byType(TextFormField),
  );
  await tester.enterText(fields.at(0), time.hour.toString().padLeft(2, '0'));
  await tester.pump();
  await tester.enterText(fields.at(1), time.minute.toString().padLeft(2, '0'));
  await tester.pump();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> _enterDate(WidgetTester tester, DateTime date) async {
  await tester.tap(find.byTooltip('Switch to input'));
  await tester.pumpAndSettle();
  final field = find.descendant(
    of: find.byType(Dialog),
    matching: find.byType(TextFormField),
  );
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  await tester.enterText(field, '$month/$day/${date.year}');
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}
