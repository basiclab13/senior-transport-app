import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/schedule_catalog.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';

import 'admin_overview_test.dart' show operatingCatalog;
import 'support/fixtures.dart';

void main() {
  const admin = AppUser(uid: 'fictional-admin', role: UserRole.admin);

  testWidgets(
    'unassigned passenger in an incomplete draft is counted, searchable and cannot be confirmed',
    (tester) async {
      final full = operatingCatalog();
      final missing = ScheduleCatalog(
        version: full.version,
        staff: full.staff,
        vehicles: full.vehicles,
        passengers: full.passengers,
        baseRoutes: [
          for (final route in full.baseRoutes)
            BaseRoute(
              id: route.id,
              name: route.name,
              period: route.period,
              staffId: route.staffId,
              vehicleId: route.vehicleId,
              passengerIds: route.period == TransportPeriod.morning
                  ? route.passengerIds.where((id) => id != 'p80').toList()
                  : route.passengerIds,
            ),
        ],
      );
      final c = ScheduleController(
        user: admin,
        catalog: missing,
        initialDate: DateTime(2026, 11, 16),
        clock: fixtureClock,
      );
      // Simulate an incomplete draft only in this widget test, never in Firestore.
      c.catalog = full;
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      expect(c.validationErrors, isNotEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-schedule')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('open-passenger-search')));
      await tester.pumpAndSettle();
      final summary = tester
          .widget<Text>(find.byKey(const Key('overview-summary')))
          .data!;
      expect(summary, contains('배정 79/80명'));
      expect(summary, contains('미배정 1명'));
      await tester.enterText(
        find.byKey(const Key('assignment-search')),
        '가상 이용자 80',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('미배정 · 기본 코스 담당 가상 직원 20'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '80-person catalog renders only employee 20 own timeline; scrolling and empty period are usable',
    (tester) async {
      final catalog = operatingCatalog();
      final source = ScheduleController(
        user: admin,
        catalog: catalog,
        initialDate: DateTime(2026, 11, 16),
        clock: fixtureClock,
      );
      source.confirm();
      const user = AppUser(
        uid: 'fictional-staff20',
        role: UserRole.staff,
        staffId: 's20',
      );
      final c = ScheduleController(
        user: user,
        catalog: catalog,
        initialDate: DateTime(2026, 11, 16),
        clock: fixtureClock,
        initialConfirmed: [source.confirmed!],
      );
      source.dispose();
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleScreen(
            user: user,
            controller: c,
            onSignOut: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('timeline-p1')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('timeline-p80')));
      await tester.pumpAndSettle();
      expect(find.text('가상 이용자 80'), findsOneWidget);
      expect(find.byKey(const Key('staff-search')), findsNothing);
      c.selectPeriod(TransportPeriod.afternoon);
      await tester.pumpAndSettle();
      expect(find.text('아직 확정된 일정이 없습니다.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
