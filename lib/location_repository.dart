import 'package:flutter/widgets.dart';
import 'package:geo_groups/geo_coordinate.dart';
import 'package:geo_groups/supabase_bootstrap.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Чтение и сохранение текущих позиций участников одной группы.
abstract class LocationRepository {
  Future<List<GroupMemberLocation>> loadGroupLocations(String groupId);

  Future<void> upsertMyLocation({
    required String groupId,
    required String userId,
    required GeoCoordinate coordinate,
  });
}

/// Локальный режим: к таблице locations не обращается.
class LocalLocationRepository implements LocationRepository {
  const LocalLocationRepository();
  @override
  Future<List<GroupMemberLocation>> loadGroupLocations(String groupId) async {
    return const [];
  }

  @override
  Future<void> upsertMyLocation({
    required String groupId,
    required String userId,
    required GeoCoordinate coordinate,
  }) async {}
}

typedef LocationRows = Future<List<Map<String, dynamic>>> Function(
  String groupId,
);

typedef LocationUpsert = Future<void> Function(Map<String, dynamic> row);

LocationRepository locationRepositoryFor(SupabaseStartup startup) {
  if (startup == SupabaseStartup.ready) {
    return SupabaseLocationRepository();
  }
  return LocalLocationRepository();
}

/// Позиции группы из public.locations. RLS остаётся на стороне базы.
class SupabaseLocationRepository implements LocationRepository {
  SupabaseLocationRepository({LocationRows? locations, LocationUpsert? upsert})
    : _locations = locations ?? _locationsFromSupabase,
      _upsert = upsert ?? _upsertLocation;

  final LocationRows _locations;
  final LocationUpsert _upsert;

  @override
  Future<List<GroupMemberLocation>> loadGroupLocations(String groupId) async {
    return mapLocationRows(await _locations(groupId));
  }

  @override
  Future<void> upsertMyLocation({
    required String groupId,
    required String userId,
    required GeoCoordinate coordinate,
  }) {
    return _upsert(
      locationUpsertRow(
        groupId: groupId,
        userId: userId,
        coordinate: coordinate,
      ),
    );
  }
}

/// Строка для upsert. updated_at не передаётся: его выставляет база.
Map<String, dynamic> locationUpsertRow({
  required String groupId,
  required String userId,
  required GeoCoordinate coordinate,
}) {
  return {
    'group_id': groupId,
    'user_id': userId,
    'latitude': coordinate.latitude,
    'longitude': coordinate.longitude,
  };
}

/// Собирает позиции из уже прочитанных строк. Пустой вход даёт пустой список.
List<GroupMemberLocation> mapLocationRows(List<Map<String, dynamic>> rows) {
  return [for (final row in rows) ?locationFromRow(row)];
}

/// Одна строка locations. Неполная или недопустимая строка пропускается.
GroupMemberLocation? locationFromRow(Map<String, dynamic> row) {
  final userId = row['user_id'];
  final latitude = row['latitude'];
  final longitude = row['longitude'];
  final updatedAt = _dateTime(row['updated_at']);
  if (userId is! String ||
      userId.isEmpty ||
      latitude is! num ||
      longitude is! num ||
      updatedAt == null) {
    return null;
  }
  try {
    return GroupMemberLocation(
      memberId: userId,
      coordinate: GeoCoordinate(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
      ),
      updatedAt: updatedAt,
    );
  } on ArgumentError {
    return null;
  }
}

Future<List<Map<String, dynamic>>> _locationsFromSupabase(
  String groupId,
) async {
  final rows = await Supabase.instance.client
      .from('locations')
      .select('group_id,user_id,latitude,longitude,updated_at')
      .eq('group_id', groupId);
  return _rowMaps(rows);
}

Future<void> _upsertLocation(Map<String, dynamic> row) {
  return Supabase.instance.client
      .from('locations')
      .upsert(row, onConflict: 'group_id,user_id', defaultToNull: false);
}

List<Map<String, dynamic>> _rowMaps(Object? rows) {
  if (rows is! List) {
    return const [];
  }
  return [
    for (final row in rows)
      if (row is Map) Map<String, dynamic>.from(row),
  ];
}

DateTime? _dateTime(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

/// Делает выбранный репозиторий позиций доступным экранам под [MaterialApp].
class LocationRepositoryScope extends InheritedWidget {
  const LocationRepositoryScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final LocationRepository repository;

  static LocationRepository? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<LocationRepositoryScope>()
        ?.repository;
  }

  @override
  bool updateShouldNotify(LocationRepositoryScope oldWidget) {
    return oldWidget.repository != repository;
  }
}
