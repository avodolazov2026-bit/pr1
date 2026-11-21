import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/map_time_format.dart';

void main() {
  final now = DateTime.utc(2026, 11, 18, 12);

  test('recent updates are described as just now', () {
    expect(formatUpdatedAgo(now, now: now), 'только что');
    expect(
      formatUpdatedAgo(now.subtract(const Duration(seconds: 59)), now: now),
      'только что',
    );
  });

  test('updates within an hour use minutes', () {
    expect(
      formatUpdatedAgo(now.subtract(const Duration(minutes: 1)), now: now),
      '1 мин назад',
    );
    expect(
      formatUpdatedAgo(now.subtract(const Duration(minutes: 59)), now: now),
      '59 мин назад',
    );
  });

  test('updates within a day use hours', () {
    expect(
      formatUpdatedAgo(now.subtract(const Duration(minutes: 60)), now: now),
      '1 ч назад',
    );
    expect(
      formatUpdatedAgo(now.subtract(const Duration(hours: 23)), now: now),
      '23 ч назад',
    );
  });

  test('older updates use days', () {
    expect(
      formatUpdatedAgo(now.subtract(const Duration(hours: 24)), now: now),
      '1 дн назад',
    );
    expect(
      formatUpdatedAgo(now.subtract(const Duration(days: 5)), now: now),
      '5 дн назад',
    );
  });

  test('a future update is treated as just now', () {
    expect(
      formatUpdatedAgo(now.add(const Duration(minutes: 5)), now: now),
      'только что',
    );
    expect(
      formatLocationUpdated(now.add(const Duration(seconds: 10)), now: now),
      'Обновлено только что',
    );
    expect(
      formatLocationUpdated(now.subtract(const Duration(minutes: 1)), now: now),
      'Обновлено 1 мин назад',
    );
    expect(
      formatLocationUpdated(now.subtract(const Duration(minutes: 5)), now: now),
      'Обновлено 5 мин назад',
    );
    expect(
      formatLocationUpdated(now.subtract(const Duration(hours: 1)), now: now),
      'Обновлено 1 ч назад',
    );
    expect(
      formatLocationUpdated(now.subtract(const Duration(hours: 2)), now: now),
      'Обновлено 2 ч назад',
    );
    expect(
      formatLocationUpdated(now.subtract(const Duration(days: 3)), now: now),
      'Обновлено 3 дн назад',
    );
  });
}
