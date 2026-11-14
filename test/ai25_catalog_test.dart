import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/data/emulator_display_names.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/schedule_catalog.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';

void main() {
  late ScheduleCatalog catalog;
  const admin = AppUser(uid: 'ai25-fixture-admin', role: UserRole.admin);
  setUp(() {
    final manifest = jsonDecode(
      File('docs/fixtures/ai-test-25x80-v1.baseline.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    catalog = ScheduleCatalog.fromJson(
      manifest['catalogVersion'] as String,
      Map<String, dynamic>.from(manifest['collections'] as Map),
    );
  });
  test('new catalog names survive legacy display overlay and contain five spare staff', () {
    expect(catalog.isTestData, isTrue);
    expect(catalog.staff.length, 25);
    expect(catalog.vehicles.length, 20);
    expect(catalog.passengers.length, 80);
    expect(catalog.baseRoutes.length, 40);
    expect(catalog.vehicles.every((v) => v.passengerCapacity == 4), isTrue);
    expect(catalog.staff.last.name, '노채원');
    expect(catalog.vehicles.first.name, '1호차');
    expect(
      emulatorDisplayCatalog(
        catalog,
        enabled: true,
        projectId: 'demo-senior-transport',
      ),
      same(catalog),
    );
    final existing = ScheduleCatalog.fromJson('deploy-test-v2', {
      'staff': <dynamic>[],
      'vehicles': <dynamic>[],
      'passengers': <dynamic>[],
      'baseRoutes': <dynamic>[],
    });
    expect(existing.isTestData, isFalse);
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      '25/80 dashboard labels test data at width $width without changing names',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = ScheduleController(
          user: admin,
          catalog: catalog,
          initialDate: DateTime(2026, 12, 7),
        );
        addTearDown(c.dispose);
        expect(c.draft.routes.length, 20);
        expect(c.draft.routes.every((r) => r.passengerIds.length == 4), isTrue);
        expect(c.confirmationErrors, isEmpty);
        await tester.pumpWidget(
          MaterialApp(
            home: ScheduleScreen(
              user: admin,
              controller: c,
              onSignOut: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('테스트 데이터'), findsNothing);
        expect(find.byKey(const Key('app-info')), findsOneWidget);
        expect(find.textContaining('가상 직원'), findsNothing);
        expect(find.textContaining('가상 이용자'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
