import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:geo_groups/supabase_bootstrap.dart';

/// Состояние входа, от которого зависит профиль и создание группы.
enum AuthKind { local, anonymous, confirmedPhone }

class AuthAccount {
  const AuthAccount.local() : kind = AuthKind.local, phoneE164 = null;

  const AuthAccount.anonymous() : kind = AuthKind.anonymous, phoneE164 = null;

  const AuthAccount.confirmed(this.phoneE164) : kind = AuthKind.confirmedPhone;

  final AuthKind kind;
  final String? phoneE164;

  /// Телефонный экран нужен только при живой неподтверждённой сессии Supabase.
  bool get needsPhoneSignIn => kind == AuthKind.anonymous;
}

const phoneSignInSubtitle =
    'Войдите по номеру телефона, чтобы создавать группы';
const phoneSignInDialogTitle = 'Войдите по номеру телефона';
const phoneSignInDialogMessage =
    'Войдите по номеру телефона, чтобы создавать группы. '
    'Для подтверждения номера телефона мы отправим вам одноразовый код.';

class AuthRequestException implements Exception {
  const AuthRequestException(this.message);

  final String message;
}

/// Итог выхода. Ошибка восстановления анонимной сессии не отменяет сам выход.
class AuthSignOutResult {
  const AuthSignOutResult({
    required this.anonymousSessionRestored,
    this.notice,
  });

  static const anonymousRestoreNotice =
      'Вы вышли из аккаунта. Не удалось восстановить анонимную сессию — проверьте подключение к интернету.';

  final bool anonymousSessionRestored;
  final String? notice;
}

/// Телефонный OTP и выход. Реализация не хранит токены самостоятельно.
abstract class AuthRepository {
  AuthAccount get current;

  Future<void> sendPhoneOtp(String phoneE164);

  Future<void> verifyPhoneOtp({
    required String phoneE164,
    required String code,
  });

  Future<AuthSignOutResult> signOut();
}

/// Публичный клиент Supabase Auth. Секретов и обхода SMS здесь нет.
class SupabaseAuthRepository implements AuthRepository {
  const SupabaseAuthRepository();

  @override
  AuthAccount get current {
    final auth = _authOrNull();
    if (auth == null) {
      return const AuthAccount.local();
    }
    return accountFromSupabaseUser(auth.currentUser);
  }

  @override
  Future<void> sendPhoneOtp(String phoneE164) async {
    final auth = _requiredAuth();
    try {
      await auth.signInWithOtp(phone: phoneE164, channel: OtpChannel.sms);
    } on AuthException catch (error) {
      throw AuthRequestException(_message(error.message));
    }
  }

  @override
  Future<void> verifyPhoneOtp({
    required String phoneE164,
    required String code,
  }) async {
    final auth = _requiredAuth();
    try {
      final response = await auth.verifyOTP(
        phone: phoneE164,
        token: code,
        type: OtpType.sms,
      );
      final user = response.user ?? auth.currentUser;
      if (!accountFromSupabaseUser(user).kind.isConfirmed) {
        throw const AuthRequestException(
          'Не удалось подтвердить номер. Попробуйте ещё раз.',
        );
      }
    } on AuthRequestException {
      rethrow;
    } on AuthException catch (error) {
      throw AuthRequestException(_message(error.message));
    }
  }

  @override
  Future<AuthSignOutResult> signOut() async {
    final auth = _requiredAuth();
    try {
      await auth.signOut();
    } on AuthException catch (error) {
      throw AuthRequestException(_message(error.message));
    }
    // verifyOTP открывает сессию телефонного пользователя и не переносит
    // членства с прежнего анонимного auth.uid(). После выхода анонимную
    // сессию снова создаёт только штатный bootstrap.
    try {
      final startup = await restoreAnonymousSessionAfterSignOut();
      if (startup == SupabaseStartup.ready) {
        return const AuthSignOutResult(anonymousSessionRestored: true);
      }
    } catch (_) {}
    return const AuthSignOutResult(
      anonymousSessionRestored: false,
      notice: AuthSignOutResult.anonymousRestoreNotice,
    );
  }

  GoTrueClient? _authOrNull() {
    try {
      if (!Supabase.instance.isInitialized) {
        return null;
      }
      return Supabase.instance.client.auth;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Supabase auth is not available yet: $error');
      }
      return null;
    }
  }

  GoTrueClient _requiredAuth() {
    final auth = _authOrNull();
    if (auth == null) {
      throw const AuthRequestException(
        'Вход по телефону сейчас недоступен. Попробуйте ещё раз.',
      );
    }
    return auth;
  }
}

extension on AuthKind {
  bool get isConfirmed => this == AuthKind.confirmedPhone;
}

/// Подтверждённый телефон — неанонимный пользователь с phone и phoneConfirmedAt.
AuthAccount accountFromSupabaseUser(User? user) {
  if (user == null || user.isAnonymous) {
    return const AuthAccount.anonymous();
  }
  final phone = user.phone?.trim();
  final confirmedAt = user.phoneConfirmedAt?.trim();
  if (phone == null ||
      phone.isEmpty ||
      confirmedAt == null ||
      confirmedAt.isEmpty) {
    return const AuthAccount.anonymous();
  }
  return AuthAccount.confirmed(phone);
}

String _message(String message) {
  final trimmed = message.trim();
  if (trimmed.isEmpty) {
    return 'Не удалось выполнить вход. Попробуйте ещё раз.';
  }
  return trimmed;
}

/// Российский номер или уже введённый E.164. Иначе null.
String? normalizePhoneE164(String raw) {
  final compact = raw.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
  if (compact.isEmpty) {
    return null;
  }
  if (compact.startsWith('+')) {
    final digits = compact.substring(1);
    if (!RegExp(r'^[1-9]\d{7,14}$').hasMatch(digits)) {
      return null;
    }
    return '+$digits';
  }
  final digits = compact.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 11 &&
      (digits.startsWith('8') || digits.startsWith('7'))) {
    return '+7${digits.substring(1)}';
  }
  if (digits.length == 10) {
    return '+7$digits';
  }
  return null;
}

/// Маска вида `+7 ••• •••-12-34`. Остальные номера скрывают середину так же.
String maskPhoneNumber(String e164) {
  final digits = e164.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 4) {
    return e164;
  }
  final last = digits.substring(digits.length - 4);
  final tail = '${last.substring(0, 2)}-${last.substring(2)}';
  if (digits.startsWith('7') && digits.length == 11) {
    return '+7 ••• •••-$tail';
  }
  final headLength = digits.length > 10 ? digits.length - 10 : 1;
  return '+${digits.substring(0, headLength)} ••• •••-$tail';
}
