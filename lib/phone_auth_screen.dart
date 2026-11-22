import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:geo_groups/auth_repository.dart';

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key, this.auth});

  final AuthRepository? auth;

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  late final AuthRepository _auth =
      widget.auth ?? const SupabaseAuthRepository();

  var _codeSent = false;
  var _busy = false;
  String? _error;
  String? _phoneE164;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_busy) {
      return;
    }
    final phone = normalizePhoneE164(_phoneController.text);
    if (phone == null) {
      setState(() {
        _error = _phoneController.text.trim().isEmpty
            ? 'Введите номер телефона'
            : 'Проверьте номер: нужен код страны, например +7';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.sendPhoneOtp(phone);
    } on AuthRequestException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = error.message;
      });
      return;
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = 'Не удалось отправить код. Попробуйте ещё раз.';
      });
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _codeSent = true;
      _phoneE164 = phone;
      _error = null;
    });
  }

  Future<void> _confirm() async {
    if (_busy) {
      return;
    }
    final phone = _phoneE164;
    final code = _codeController.text.trim();
    if (phone == null) {
      return;
    }
    if (!RegExp(r'^\d{6,10}$').hasMatch(code)) {
      setState(() => _error = 'Введите код из SMS');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.verifyPhoneOtp(phoneE164: phone, code: code);
    } on AuthRequestException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = error.message;
      });
      return;
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = 'Не удалось подтвердить код. Попробуйте ещё раз.';
      });
      return;
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(true);
  }

  void _editPhone() {
    if (_busy) {
      return;
    }
    setState(() {
      _codeSent = false;
      _phoneE164 = null;
      _codeController.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Войдите по номеру телефона')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            Text(
              'Отправим одноразовый код по SMS. Пароль не требуется.',
              style: textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _phoneController,
              enabled: !_codeSent && !_busy,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Номер телефона',
                hintText: '+7 900 000-00-00',
                border: OutlineInputBorder(),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-\(\)]')),
              ],
              onSubmitted: (_) => _sendCode(),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Код из SMS',
                  border: OutlineInputBorder(),
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _confirm(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_codeSent)
                FilledButton(
                  onPressed: _busy ? null : _sendCode,
                  child: Text(_busy ? 'Отправляем код…' : 'Получить код'),
                )
              else ...[
                FilledButton(
                  onPressed: _busy ? null : _confirm,
                  child: Text(_busy ? 'Проверяем код…' : 'Подтвердить'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _sendCode,
                  child: const Text('Отправить код ещё раз'),
                ),
                TextButton(
                  onPressed: _busy ? null : _editPhone,
                  child: const Text('Изменить номер'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
