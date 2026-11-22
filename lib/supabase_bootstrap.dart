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

/// После выхода снова включает штатный вход.
///
/// Уже идущий запуск дожидается и не подменяется. Он мог вернуть
/// [SupabaseStartup.ready] для сессии, которую выход уже закрыл, поэтому флаг
/// сбрасывается повторно и анонимная сессия открывается следующим
/// [bootstrapSupabase]. Повторный [Supabase.initialize] не вызывается: SDK
/// поднимает только [_initializeSupabase], и только пока он ещё не отмечен
/// запущенным.
Future<SupabaseStartup> restoreAnonymousSessionAfterSignOut({
  SupabaseConfig? config,
  Future<void> Function(SupabaseConfig config)? initialize,
  Future<SupabaseStartup> Function()? openSession,
  bool debugSdkHttp = false,
}) async {
  _sessionReady = false;
  final ongoing = _ongoing;
  if (ongoing != null) {
    try {
      await ongoing;
    } catch (_) {}
  }
  // Предыдущий запуск мог успеть вернуть ready для уже закрытой сессии.
  _sessionReady = false;
  return bootstrapSupabase(
    config: config,
    initialize: initialize,
    openSession: openSession,
    debugSdkHttp: debugSdkHttp,
  );
}

/// Инициализирует SDK один раз и восстанавливает либо создаёт анонимную сессию.
///
/// Без обоих параметров сразу возвращает [SupabaseStartup.local] и к сети не обращается.
Future<SupabaseStartup> bootstrapSupabase({
  SupabaseConfig? config,
  Future<void> Function(SupabaseConfig config)? initialize,
  Future<SupabaseStartup> Function()? openSession,
  bool debugSdkHttp = false,
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
    initialize ?? (config) => _initializeSupabase(config, debug: debugSdkHttp),
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
      _logBootstrapFailure(error);
    }
    return SupabaseStartup.failed;
  }
}

void _logBootstrapFailure(Object error) {
  debugPrint('Supabase bootstrap failed: ${error.runtimeType}: $error');
  if (error is AuthException) {
    debugPrint(
      'Supabase bootstrap details: '
      'code=${error.code} status=${error.statusCode} message=${error.message}',
    );
    return;
  }
  if (error is PostgrestException) {
    debugPrint(
      'Supabase bootstrap details: '
      'code=${error.code} message=${error.message}',
    );
  }
}

Future<void> _initializeSupabase(
  SupabaseConfig config, {
  bool debug = false,
}) {
  return Supabase.initialize(
    url: config.url,
    publishableKey: config.publishableKey,
    debug: debug,
  );
}

Future<SupabaseStartup> _openAnonymousSession() async {
  final auth = Supabase.instance.client.auth;
  if (auth.currentSession == null) {
    await auth.signInAnonymously();
  }
  if (auth.currentSession == null) {
    throw StateError('anonymous session was not created');
  }
  return SupabaseStartup.ready;
}
