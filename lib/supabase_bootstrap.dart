import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Результат запуска: локальный режим, сессия готова или подключение не удалось.
enum SupabaseStartup { local, ready, failed }

/// Публичные параметры Supabase. Секретов здесь нет.
class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.publishableKey});

  final String url;
  final String publishableKey;

  bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}

/// Supabase включён только когда заданы оба непустых значения.
SupabaseConfig supabaseConfigFromValues({
  required String url,
  required String publishableKey,
}) {
  return SupabaseConfig(url: url.trim(), publishableKey: publishableKey.trim());
}

SupabaseConfig supabaseConfigFromEnvironment() {
  return supabaseConfigFromValues(
    url: const String.fromEnvironment('SUPABASE_URL'),
    publishableKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );
}

var _sdkInitialized = false;
var _sessionReady = false;
Future<SupabaseStartup>? _ongoing;

/// Сбрасывает только защиту от повторного запуска. SDK при этом не вызывается.
@visibleForTesting
void resetSupabaseBootstrapState() {
  _sdkInitialized = false;
  _sessionReady = false;
  _ongoing = null;
}

/// Инициализирует SDK один раз и восстанавливает либо создаёт анонимную сессию.
///
/// Без обоих параметров сразу возвращает [SupabaseStartup.local] и к сети не обращается.
Future<SupabaseStartup> bootstrapSupabase({
  SupabaseConfig? config,
  Future<void> Function(SupabaseConfig config)? initialize,
  Future<SupabaseStartup> Function()? openSession,
}) {
  final resolved = config ?? supabaseConfigFromEnvironment();
  if (!resolved.isConfigured) {
    return Future<SupabaseStartup>.value(SupabaseStartup.local);
  }
  if (_sessionReady) {
    return Future<SupabaseStartup>.value(SupabaseStartup.ready);
  }
  final ongoing = _ongoing;
  if (ongoing != null) {
    return ongoing;
  }
  final run = _bootstrap(
    resolved,
    initialize ?? _initializeSupabase,
    openSession ?? _openAnonymousSession,
  );
  _ongoing = run;
  run.whenComplete(() {
    if (identical(_ongoing, run)) {
      _ongoing = null;
    }
  });
  return run;
}

Future<SupabaseStartup> _bootstrap(
  SupabaseConfig config,
  Future<void> Function(SupabaseConfig config) initialize,
  Future<SupabaseStartup> Function() openSession,
) async {
  try {
    if (!_sdkInitialized) {
      await initialize(config);
      _sdkInitialized = true;
    }
    final result = await openSession();
    if (result == SupabaseStartup.ready) {
      _sessionReady = true;
    }
    return result;
  } catch (error) {
    if (kDebugMode) {
      debugPrint('Supabase bootstrap failed: ${error.runtimeType}');
    }
    return SupabaseStartup.failed;
  }
}

Future<void> _initializeSupabase(SupabaseConfig config) {
  return Supabase.initialize(
    url: config.url,
    publishableKey: config.publishableKey,
    debug: false,
  );
}

Future<SupabaseStartup> _openAnonymousSession() async {
  final auth = Supabase.instance.client.auth;
  if (auth.currentSession == null) {
    await auth.signInAnonymously();
  }
  if (auth.currentSession == null) {
    return SupabaseStartup.failed;
  }
  return SupabaseStartup.ready;
}
