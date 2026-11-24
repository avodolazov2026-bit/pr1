import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/created_groups_screen.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/theme/app_theme.dart';

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
      await tester.tap(find.text('Создать группу'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Поход');
      await tester.pump();

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await tester.tap(find.textContaining('Начало:'));
      await tester.pumpAndSettle();
      await _enterDate(tester, today);
      await _enterTime(tester, TimeOfDay(hour: now.hour, minute: now.minute));

      expect(
        find.text('Время начала должно быть позже текущего времени'),
        findsWidgets,
      );
      expect(_createButton(tester).onPressed, isNull);

      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final dayAfter = DateTime(now.year, now.month, now.day + 2);
      await tester.tap(find.textContaining('Начало:'));
      await tester.pumpAndSettle();
      await _enterDate(tester, tomorrow);
      await _enterTime(tester, const TimeOfDay(hour: 10, minute: 0));
      await tester.tap(find.text('Окончание группы'));
      await tester.pumpAndSettle();
      await _enterDate(tester, dayAfter);
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

  testWidgets('create form uses one start button and one end button', (
    tester,
  ) async {
    await _openCreateForm(tester);

    expect(find.textContaining('Начало:'), findsOneWidget);
    expect(find.text('Окончание группы'), findsOneWidget);
    expect(find.textContaining('Дата начала'), findsNothing);
    expect(find.textContaining('Время начала'), findsNothing);
    expect(find.textContaining('Дата завершения'), findsNothing);
    expect(find.textContaining('Время завершения'), findsNothing);
    expect(find.byIcon(Icons.event_outlined), findsNWidgets(2));
  });

  testWidgets('a complete date and time updates the start and the end', (
    tester,
  ) async {
    await _openCreateForm(tester);
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final dayAfter = DateTime(now.year, now.month, now.day + 2);
    final start = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 15, 30);
    final end = DateTime(dayAfter.year, dayAfter.month, dayAfter.day, 18, 0);

    await tester.tap(find.textContaining('Начало:'));
    await tester.pumpAndSettle();
    await _enterDate(tester, tomorrow);
    await _enterTime(tester, const TimeOfDay(hour: 15, minute: 30));
    await tester.tap(find.text('Окончание группы'));
    await tester.pumpAndSettle();
    await _enterDate(tester, dayAfter);
    await _enterTime(tester, const TimeOfDay(hour: 18, minute: 0));

    expect(find.text('Начало: ${formatGroupDateTime(start)}'), findsOneWidget);
    expect(find.text('Окончание: ${formatGroupDateTime(end)}'), findsOneWidget);
  });

  testWidgets('cancelling the date leaves the start unchanged', (tester) async {
    await _openCreateForm(tester);
    final before = tester.widget<Text>(find.textContaining('Начало:')).data;

    await tester.tap(find.textContaining('Начало:'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.textContaining('Начало:')).data, before);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('cancelling the time leaves the whole start unchanged', (
    tester,
  ) async {
    await _openCreateForm(tester);
    final before = tester.widget<Text>(find.textContaining('Начало:')).data;
    final tomorrow = DateTime.now().add(const Duration(days: 1));

    await tester.tap(find.textContaining('Начало:'));
    await tester.pumpAndSettle();
    await _enterDate(tester, tomorrow);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.textContaining('Начало:')).data, before);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('cancelling the date leaves the chosen end unchanged', (
    tester,
  ) async {
    await _openCreateForm(tester);
    final end = await _chooseEnd(tester);
    final label = 'Окончание: ${formatGroupDateTime(end)}';

    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text(label), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('cancelling the time leaves the chosen end unchanged', (
    tester,
  ) async {
    await _openCreateForm(tester);
    final end = await _chooseEnd(tester);
    final label = 'Окончание: ${formatGroupDateTime(end)}';
    final otherDay = DateTime(end.year, end.month, end.day + 1);
    final otherEnd = DateTime(
      otherDay.year,
      otherDay.month,
      otherDay.day,
      end.hour,
      end.minute,
    );

    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    await _enterDate(tester, otherDay);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text(label), findsOneWidget);
    expect(
      find.text('Окончание: ${formatGroupDateTime(otherEnd)}'),
      findsNothing,
    );
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('an indefinite group disables the end button', (tester) async {
    await _openCreateForm(tester);

    await tester.ensureVisible(find.text('Бессрочная группа'));
    await tester.tap(find.text('Бессрочная группа'));
    await tester.pump();

    final button = tester.widget<AppTonalButton>(
      find.widgetWithText(AppTonalButton, 'Окончание группы'),
    );
    expect(button.onPressed, isNull);
  });
}

Future<void> _openCreateForm(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en', 'US'),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
      home: const CreatedGroupsScreen(),
    ),
  );
  await tester.tap(find.text('Создать группу'));
  await tester.pumpAndSettle();
}

Future<DateTime> _chooseEnd(WidgetTester tester) async {
  final now = DateTime.now();
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final dayAfter = DateTime(now.year, now.month, now.day + 2);
  final end = DateTime(dayAfter.year, dayAfter.month, dayAfter.day, 18, 0);

  await tester.tap(find.textContaining('Начало:'));
  await tester.pumpAndSettle();
  await _enterDate(tester, tomorrow);
  await _enterTime(tester, const TimeOfDay(hour: 15, minute: 30));
  await tester.tap(find.text('Окончание группы'));
  await tester.pumpAndSettle();
  await _enterDate(tester, dayAfter);
  await _enterTime(tester, const TimeOfDay(hour: 18, minute: 0));
  expect(find.text('Окончание: ${formatGroupDateTime(end)}'), findsOneWidget);
  return end;
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
