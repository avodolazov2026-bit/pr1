import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:geo_groups/main.dart';
import 'package:geo_groups/service_availability.dart';
import 'package:geo_groups/service_unavailable_screen.dart';

void main() {
  test('a true RPC result means the service is available', () async {
    final check = SupabaseServiceAvailabilityCheck(rpc: () async => true);
    expect(await check.check(), isTrue);
  });

  test('a socket error or timeout means the service is unavailable', () async {
    final socket = SupabaseServiceAvailabilityCheck(
      rpc: () async => throw const SocketException('offline'),
    );
    final timedOut = SupabaseServiceAvailabilityCheck(
      rpc: () => Completer<Object?>().future,
      timeout: const Duration(milliseconds: 10),
    );

    expect(await socket.check(), isFalse);
    expect(await timedOut.check(), isFalse);
    expect(isConnectivityFailure(const SocketException('offline')), isTrue);
    expect(
      isConnectivityFailure(
        const PostgrestException(message: 'Приглашение недоступно'),
      ),
      isFalse,
    );
  });

  test('a newer retry is not overwritten by an older result', () async {
    final first = Completer<bool>();
    final second = Completer<bool>();
    var calls = 0;
    final controller = ServiceAvailabilityController(
      check: () {
        calls += 1;
        return calls == 1 ? first.future : second.future;
      },
    );
    addTearDown(controller.dispose);

    final initial = controller.retry();
    controller.retry();
    first.complete(false);
    await initial;
    expect(controller.status, ServiceAvailability.checking);

    second.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, ServiceAvailability.available);
    expect(calls, 2);
  });

  testWidgets('a successful check opens the existing home screen', (
    tester,
  ) async {
    final controller = ServiceAvailabilityController(
      check: () async => true,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ServiceAvailabilityShell(controller: controller, child: const MyApp()),
    );
    await tester.pump();

    expect(find.text('Присоединиться по приглашению'), findsOneWidget);
    expect(find.text('Сервис временно недоступен'), findsNothing);
  });

  testWidgets('a network failure shows the unavailable screen', (tester) async {
    final controller = ServiceAvailabilityController(
      check: () async => false,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ServiceAvailabilityShell(
        controller: controller,
        child: const Text('Главный экран'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Сервис временно недоступен'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    expect(find.text('Главный экран'), findsNothing);
  });

  testWidgets('retry after a failure opens the app when the service returns', (
    tester,
  ) async {
    var calls = 0;
    final controller = ServiceAvailabilityController(
      check: () async {
        calls += 1;
        return calls > 1;
      },
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ServiceAvailabilityShell(
        controller: controller,
        child: const MaterialApp(home: Text('Главный экран')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Сервис временно недоступен'), findsOneWidget);

    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();

    expect(find.text('Главный экран'), findsOneWidget);
    expect(find.text('Сервис временно недоступен'), findsNothing);
  });

  testWidgets('the retry button cannot be pressed again while checking', (
    tester,
  ) async {
    final gate = Completer<bool>();
    var calls = 0;
    final controller = ServiceAvailabilityController(
      check: () {
        calls += 1;
        if (calls == 1) {
          return Future<bool>.value(false);
        }
        return gate.future;
      },
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ServiceAvailabilityShell(
        controller: controller,
        child: const Text('Главный экран'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Повторить'));
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(calls, 2);

    gate.complete(false);
    await tester.pumpAndSettle();
  });
}
