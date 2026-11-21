import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/member_distance.dart';

void main() {
  test('haversine matches one degree of latitude', () {
    final meters = geodesicDistanceMeters(0, 0, 1, 0);

    expect(meters, isNotNull);
    expect(meters!, closeTo(111194.93, 0.1));
  });

  test('invalid coordinates do not produce a distance', () {
    expect(geodesicDistanceMeters(double.nan, 0, 0, 0), isNull);
    expect(geodesicDistanceMeters(0, double.infinity, 0, 0), isNull);
    expect(geodesicDistanceMeters(91, 0, 0, 0), isNull);
    expect(geodesicDistanceMeters(0, 181, 0, 0), isNull);
  });

  test('meters stay in meters and a kilometer uses one decimal', () {
    expect(formatDistanceMeters(349.6), '350 м');
    expect(formatDistanceMeters(999.4), '999 м');
    expect(formatDistanceMeters(1000), '1,0 км');
    expect(formatDistanceMeters(2300), '2,3 км');
    expect(formatDistanceMeters(2349), '2,3 км');
    expect(formatDistanceMeters(double.nan), isNull);
    expect(formatDistanceMeters(double.negativeInfinity), isNull);
  });
}
