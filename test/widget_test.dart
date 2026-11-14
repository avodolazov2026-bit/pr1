import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/main.dart';

void main() {
  testWidgets('Home screen shows the invitation action', (tester) async {
    currentDemoUserId = defaultDemoUserId;
    await tester.pumpWidget(const MyApp());

    expect(find.text('Geo Groups'), findsOneWidget);
    expect(find.text('Присоединиться по приглашению'), findsOneWidget);
  });
}
