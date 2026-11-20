import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/geo_coordinate.dart';
import 'package:geo_groups/location_upload_filter.dart';

void main() {
  final origin = GeoCoordinate(latitude: 55.75, longitude: 37.62);
  final uploadedAt = DateTime.utc(2026, 11, 20, 12);

  test('первая точка с точностью 30 м отправляется', () {
    final filter = LocationUploadFilter();

    expect(
      filter.shouldUpload(
        coordinate: origin,
        accuracyMeters: LocationUploadFilter.maxAccuracyMeters,
        now: uploadedAt,
      ),
      isTrue,
    );
  });

  test('точка с точностью хуже 30 м не отправляется', () {
    final filter = LocationUploadFilter();

    expect(
      filter.shouldUpload(
        coordinate: origin,
        accuracyMeters: LocationUploadFilter.maxAccuracyMeters + 0.1,
        now: uploadedAt,
      ),
      isFalse,
    );
  });

  test('неподвижная точка раньше двух минут не отправляется', () {
    final filter = LocationUploadFilter()
      ..markUploaded(coordinate: origin, uploadedAt: uploadedAt);

    expect(
      filter.shouldUpload(
        coordinate: origin,
        accuracyMeters: 5,
        now: uploadedAt.add(
          LocationUploadFilter.maximumInterval - const Duration(seconds: 1),
        ),
      ),
      isFalse,
    );
  });

  test('сдвиг меньше 10 м раньше двух минут не отправляется', () {
    final filter = LocationUploadFilter()
      ..markUploaded(coordinate: origin, uploadedAt: uploadedAt);
    final nearby = _northOf(origin, 9);

    expect(distanceBetweenMeters(origin, nearby), lessThan(10));
    expect(
      filter.shouldUpload(
        coordinate: nearby,
        accuracyMeters: 5,
        now: uploadedAt.add(const Duration(seconds: 30)),
      ),
      isFalse,
    );
  });

  test('сдвиг ровно на 10 м или больше отправляется', () {
    final filter = LocationUploadFilter()
      ..markUploaded(coordinate: origin, uploadedAt: uploadedAt);
    final boundary = _northOfAtLeast(
      origin,
      LocationUploadFilter.minimumDistanceMeters,
    );
    final farther = _northOf(origin, 25);

    expect(
      distanceBetweenMeters(origin, boundary),
      greaterThanOrEqualTo(LocationUploadFilter.minimumDistanceMeters),
    );
    expect(
      filter.shouldUpload(
        coordinate: boundary,
        accuracyMeters: 5,
        now: uploadedAt.add(const Duration(seconds: 30)),
      ),
      isTrue,
    );
    expect(
      filter.shouldUpload(
        coordinate: farther,
        accuracyMeters: 5,
        now: uploadedAt.add(const Duration(seconds: 30)),
      ),
      isTrue,
    );
  });

  test('неподвижная точка ровно через 2 минуты отправляется', () {
    final filter = LocationUploadFilter()
      ..markUploaded(coordinate: origin, uploadedAt: uploadedAt);

    expect(
      filter.shouldUpload(
        coordinate: origin,
        accuracyMeters: 5,
        now: uploadedAt.add(LocationUploadFilter.maximumInterval),
      ),
      isTrue,
    );
  });

  test('неуспешная отправка не блокирует следующую подходящую точку', () {
    final filter = LocationUploadFilter();

    expect(
      filter.shouldUpload(
        coordinate: origin,
        accuracyMeters: 8,
        now: uploadedAt,
      ),
      isTrue,
    );
    expect(
      filter.shouldUpload(
        coordinate: origin,
        accuracyMeters: 8,
        now: uploadedAt,
      ),
      isTrue,
    );
  });

  test('неточная точка не затирает последнюю успешную отправку', () {
    final filter = LocationUploadFilter()
      ..markUploaded(coordinate: origin, uploadedAt: uploadedAt);
    final inaccurate = _northOf(origin, 40);
    final soon = uploadedAt.add(const Duration(seconds: 20));

    expect(
      filter.shouldUpload(
        coordinate: inaccurate,
        accuracyMeters: 45,
        now: soon,
      ),
      isFalse,
    );
    expect(
      filter.shouldUpload(coordinate: origin, accuracyMeters: 5, now: soon),
      isFalse,
    );
    expect(
      filter.shouldUpload(coordinate: inaccurate, accuracyMeters: 5, now: soon),
      isTrue,
    );
  });
}

/// Сдвигает точку на север на [meters] по дуге радиуса Земли.
GeoCoordinate _northOf(GeoCoordinate origin, double meters) {
  final degrees = meters / earthRadiusMeters * (180 / math.pi);
  return GeoCoordinate(
    latitude: origin.latitude + degrees,
    longitude: origin.longitude,
  );
}

/// Та же дуга, но не короче [meters] после округления формулы гаверсинуса.
GeoCoordinate _northOfAtLeast(GeoCoordinate origin, double meters) {
  var point = _northOf(origin, meters);
  var extraMeters = 0.0;
  while (distanceBetweenMeters(origin, point) < meters) {
    extraMeters += 0.0000001;
    point = _northOf(origin, meters + extraMeters);
  }
  return point;
}
