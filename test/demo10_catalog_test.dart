import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/schedule_catalog.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';

import 'support/fixtures.dart' show openAdminEditor;

void main() {
  final manifest = jsonDecode(
    File('docs/fixtures/demo-10x24-v1.baseline.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final catalog = ScheduleCatalog.fromJson(
    manifest['catalogVersion'] as String,
    Map<String, dynamic>.from(manifest['collections'] as Map),
  );
  const admin = AppUser(uid: 'demo10-admin', role: UserRole.admin);
  test('demo10 preserves staff mapping and Friday leave, capacity and reserve metadata', () {
    expect(catalog.isTestData, isTrue);
    expect(catalog.staff.length, 10);
    expect(catalog.passengers.length, 24);
    expect(catalog.vehicles.every((v) => v.passengerCapacity == 4), isTrue);
    expect(catalog.staff[2].unavailableWeekdays, {5});
    final assigned = catalog.baseRoutes.map((r) => r.staffId).toSet();
    expect(assigned.length, 8);
    expect(
      catalog.staff.where((s) => !assigned.contains(s.id)).map((s) => s.id),
      ['s9', 's10'],
    );
  });
  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    testWidgets('demo10 dashboard and existing editor at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = ScheduleController(
        user: admin,
        catalog: catalog,
        initialDate: DateTime(2026, 12, 7),
        clock: () => DateTime.utc(2026, 12, 7),
      );
      addTearDown(c.dispose);
      expect(c.draft.routes.length, 8);
      expect(c.draft.routes.every((r) => r.passengerIds.length == 3), isTrue);
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
      expect(tester.takeException(), isNull);
      await openAdminEditor(tester);
      expect(tester.takeException(), isNull);
      c.selectPeriod(TransportPeriod.afternoon);
      await tester.pumpAndSettle();
      expect(c.draft.routes.length, 8);
      expect(c.confirmationErrors, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
