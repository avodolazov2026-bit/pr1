import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/supabase_bootstrap.dart';

void main() {
  tearDown(resetSupabaseBootstrapState);

  test('supabase is configured only when url and key are both present', () {
    expect(
      supabaseConfigFromValues(url: '', publishableKey: '').isConfigured,
      isFalse,
    );
    expect(
      supabaseConfigFromValues(
        url: 'https://example.supabase.co',
        publishableKey: '',
      ).isConfigured,
      isFalse,
    );
    expect(
      supabaseConfigFromValues(
        url: '',
        publishableKey: 'publishable-key',
      ).isConfigured,
      isFalse,
    );
    expect(
      supabaseConfigFromValues(url: '   ', publishableKey: '   ').isConfigured,
      isFalse,
    );
    expect(
      supabaseConfigFromValues(
        url: ' \nhttps://example.supabase.co ',
        publishableKey: ' publishable-key ',
      ).isConfigured,
      isTrue,
    );
  });

  test('configured values are trimmed and kept apart', () {
    final config = supabaseConfigFromValues(
      url: ' https://example.supabase.co ',
      publishableKey: ' publishable-key ',
    );

    expect(config.url, 'https://example.supabase.co');
    expect(config.publishableKey, 'publishable-key');
  });

  test('missing configuration stays local and does not initialize', () async {
    var initialized = 0;

    final result = await bootstrapSupabase(
      config: supabaseConfigFromValues(url: ' ', publishableKey: ' '),
      initialize: (_) async => initialized++,
      openSession: () async => SupabaseStartup.ready,
    );

    expect(result, SupabaseStartup.local);
    expect(initialized, 0);
  });

  test('a successful bootstrap initializes once across later calls', () async {
    var initialized = 0;
    var sessions = 0;
    final config = supabaseConfigFromValues(
      url: 'https://example.supabase.co',
      publishableKey: 'publishable-key',
    );

    Future<SupabaseStartup> start() {
      return bootstrapSupabase(
        config: config,
        initialize: (_) async => initialized++,
        openSession: () async {
          sessions++;
          return SupabaseStartup.ready;
        },
      );
    }

    expect(await start(), SupabaseStartup.ready);
    expect(await start(), SupabaseStartup.ready);

    expect(initialized, 1);
    expect(sessions, 1);
  });

  test('overlapping calls share one initialization', () async {
    var initialized = 0;
    final gate = Completer<void>();
    final config = supabaseConfigFromValues(
      url: 'https://example.supabase.co',
      publishableKey: 'publishable-key',
    );

    Future<SupabaseStartup> start() {
      return bootstrapSupabase(
        config: config,
        initialize: (_) async {
          initialized++;
          await gate.future;
        },
        openSession: () async => SupabaseStartup.ready,
      );
    }

    final first = start();
    final second = start();
    gate.complete();

    expect(await Future.wait([first, second]), [
      SupabaseStartup.ready,
      SupabaseStartup.ready,
    ]);
    expect(initialized, 1);
  });

  test(
    'a failed initialization can be retried without a stale guard',
    () async {
      var initialized = 0;
      final config = supabaseConfigFromValues(
        url: 'https://example.supabase.co',
        publishableKey: 'publishable-key',
      );

      final failed = await bootstrapSupabase(
        config: config,
        initialize: (_) async {
          initialized++;
          throw StateError('unavailable');
        },
        openSession: () async => SupabaseStartup.ready,
      );
      final ready = await bootstrapSupabase(
        config: config,
        initialize: (_) async => initialized++,
        openSession: () async => SupabaseStartup.ready,
      );

      expect(failed, SupabaseStartup.failed);
      expect(ready, SupabaseStartup.ready);
      expect(initialized, 2);
    },
  );

  test('restore opens a new session after an in-flight bootstrap', () async {
    var initialized = 0;
    var sessions = 0;
    final gate = Completer<void>();
    final config = supabaseConfigFromValues(
      url: 'https://example.supabase.co',
      publishableKey: 'publishable-key',
    );

    final first = bootstrapSupabase(
      config: config,
      initialize: (_) async => initialized++,
      openSession: () async {
        sessions++;
        await gate.future;
        return SupabaseStartup.ready;
      },
    );
    final restored = restoreAnonymousSessionAfterSignOut(
      config: config,
      initialize: (_) async => initialized++,
      openSession: () async {
        sessions++;
        return SupabaseStartup.failed;
      },
    );
    gate.complete();

    expect(await first, SupabaseStartup.ready);
    expect(await restored, SupabaseStartup.failed);
    expect(sessions, 2);
    expect(initialized, 1);
  });

  test(
    'a failed in-flight bootstrap does not escape anonymous restore',
    () async {
      var initialized = 0;
      var sessions = 0;
      final gate = Completer<void>();
      final config = supabaseConfigFromValues(
        url: 'https://example.supabase.co',
        publishableKey: 'publishable-key',
      );

      final first = bootstrapSupabase(
        config: config,
        initialize: (_) async => initialized++,
        openSession: () async {
          sessions++;
          await gate.future;
          throw StateError('unavailable');
        },
      );
      final restored = restoreAnonymousSessionAfterSignOut(
        config: config,
        initialize: (_) async => initialized++,
        openSession: () async {
          sessions++;
          return SupabaseStartup.ready;
        },
      );
      gate.complete();

      expect(await first, SupabaseStartup.failed);
      expect(await restored, SupabaseStartup.ready);
      expect(sessions, 2);
      expect(initialized, 1);
    },
  );

  test(
    'a failed session result is replaced by the next anonymous restore',
    () async {
      var initialized = 0;
      var sessions = 0;
      final gate = Completer<void>();
      final config = supabaseConfigFromValues(
        url: 'https://example.supabase.co',
        publishableKey: 'publishable-key',
      );

      final first = bootstrapSupabase(
        config: config,
        initialize: (_) async => initialized++,
        openSession: () async {
          sessions++;
          await gate.future;
          return SupabaseStartup.failed;
        },
      );
      final restored = restoreAnonymousSessionAfterSignOut(
        config: config,
        initialize: (_) async => initialized++,
        openSession: () async {
          sessions++;
          return SupabaseStartup.ready;
        },
      );
      gate.complete();

      expect(await first, SupabaseStartup.failed);
      expect(await restored, SupabaseStartup.ready);
      expect(sessions, 2);
      expect(initialized, 1);
    },
  );

  test('restore after a finished bootstrap opens the session again', () async {
    var initialized = 0;
    var sessions = 0;
    final config = supabaseConfigFromValues(
      url: 'https://example.supabase.co',
      publishableKey: 'publishable-key',
    );

    Future<void> initialize(SupabaseConfig _) async => initialized++;

    Future<SupabaseStartup> openSession() async {
      sessions++;
      return SupabaseStartup.ready;
    }

    expect(
      await bootstrapSupabase(
        config: config,
        initialize: initialize,
        openSession: openSession,
      ),
      SupabaseStartup.ready,
    );
    expect(
      await restoreAnonymousSessionAfterSignOut(
        config: config,
        initialize: initialize,
        openSession: openSession,
      ),
      SupabaseStartup.ready,
    );
    expect(sessions, 2);
    expect(initialized, 1);
  });

  test('a missing anonymous session does not report ready', () async {
    final result = await bootstrapSupabase(
      config: supabaseConfigFromValues(
        url: 'https://example.supabase.co',
        publishableKey: 'publishable-key',
      ),
      initialize: (_) async {},
      openSession: () async {
        throw StateError('anonymous session was not created');
      },
    );

    expect(result, SupabaseStartup.failed);
    expect(result, isNot(SupabaseStartup.ready));
  });
}
