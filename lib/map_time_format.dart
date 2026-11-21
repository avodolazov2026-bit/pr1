/// Подпись времени позиции для списка участников.
String formatLocationUpdated(DateTime updatedAt, {DateTime? now}) {
  return 'Обновлено ${formatUpdatedAgo(updatedAt, now: now)}';
}

/// Короткое русское описание того, как давно обновлена позиция.
String formatUpdatedAgo(DateTime updatedAt, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final elapsed = current.difference(updatedAt);
  if (elapsed.isNegative || elapsed < const Duration(minutes: 1)) {
    return 'только что';
  }
  if (elapsed < const Duration(hours: 1)) {
    return '${elapsed.inMinutes} мин назад';
  }
  if (elapsed < const Duration(hours: 24)) {
    return '${elapsed.inHours} ч назад';
  }
  return '${elapsed.inDays} дн назад';
}
