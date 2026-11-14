import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/schedule_catalog.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';

import 'support/fixtures.dart';

ScheduleCatalog operatingCatalog() => ScheduleCatalog(
  version: 'operating-fictional-v1',
  staff: [
    for (var i = 1; i <= 20; i++)
      Staff('s$i', '가상 직원 ${i.toString().padLeft(2, '0')}'),
  ],
  vehicles: [for (var i = 1; i <= 20; i++) Vehicle('v$i', '가상 차량 $i', 6)],
  passengers: [
    for (var i = 1; i <= 80; i++)
      Passenger(
        'p$i',
        '가상 이용자 ${i.toString().padLeft(2, '0')}',
        '가상마을 테스트길 $i',
        '가상 주의사항',
      ),
  ],
  baseRoutes: [
    for (final period in TransportPeriod.values)
      for (var i = 1; i <= 20; i++)
        BaseRoute(
          id: '${period.name}-$i',
          name: '가상 $i코스',
          period: period,
          staffId: 's$i',
          vehicleId: 'v$i',
          passengerIds: [for (var j = 1; j <= 4; j++) 'p${(i - 1) * 4 + j}'],
        ),
  ],
);

void main() {
  const admin = AppUser(uid: 'fictional-admin', role: UserRole.admin);
  late ScheduleController c;
  late MemoryScheduleRepository repository;
  setUp(() {
    repository = MemoryScheduleRepository(catalog: operatingCatalog());
    c = ScheduleController.remote(
      user: admin,
      repository: repository,
      clock: fixtureClock,
    );
  });
  tearDown(() async {
    c.dispose();
    await repository.changes.close();
  });
  Future<void> open(WidgetTester tester, {bool small = false}) async {
    tester.view.physicalSize = small
        ? const Size(320, 568)
        : const Size(1440, 1000);
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
    await openAdminEditor(tester);
    c.selectDate(DateTime(2026, 11, 16));
    await tester.pumpAndSettle();
  }

  Future<void> overview(WidgetTester tester, {bool passengers = false}) async {
    await tester.tap(find.byKey(const Key('admin-overview')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('dashboard-search')));
  }

  testWidgets(
    '20 staff / 80 passengers: overview searches all staff and opens an offscreen assignment without publishing',
    (tester) async {
      await open(tester);
      await overview(tester);
      expect(find.textContaining('배정 80명 · 결석 0명 · 미배정 0명'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('dashboard-search')),
        '가상 직원 20',
      );
      await tester.pumpAndSettle();
      expect(find.text('20코스\n차량 20'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dashboard-staff-s20')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('staff-detail-s20')), findsOneWidget);
      expect(c.hasPendingChanges, isFalse);
      expect(repository.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'passenger search finds actual assignee despite staff filter and opens visit actions',
    (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('staff-search')), '가상 직원 01');
      await tester.pumpAndSettle();
      await overview(tester, passengers: true);
      await tester.enterText(
        find.byKey(const Key('dashboard-search')),
        '가상 이용자 80',
      );
      await tester.pumpAndSettle();
      expect(find.text('직원 20'), findsOneWidget);
      expect(find.text('20코스\n차량 20'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dashboard-staff-s20')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('staff-detail-s20')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('time-p80')));
      expect(find.byKey(const ValueKey('time-p80')), findsOneWidget);
      expect(repository.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact visits expose actions on selection and reassignment shows target occupancy',
    (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('absent-p1')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('visit-p1')));
      await tester.tap(find.byKey(const ValueKey('visit-p1')));
      await tester.pumpAndSettle();
      final move = find.byKey(const ValueKey('move-p1'));
      await tester.ensureVisible(move);
      await tester.tap(move);
      await tester.pumpAndSettle();
      expect(find.textContaining('현재 4/6명 · 이동 후 5명').first, findsOneWidget);
      expect(find.textContaining('직원 총 4명 · 차량 2 · 근무 가능'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('reassign-target-p1-morning-2')),
      );
      await tester.pumpAndSettle();
      expect(c.routesForStaff('s1').single.passengerIds, ['p2', 'p3', 'p4']);
      expect(c.routesForStaff('s2').single.passengerIds, [
        'p5',
        'p6',
        'p7',
        'p8',
        'p1',
      ]);
      expect(c.validationErrors, isEmpty);
      expect(repository.requests, isEmpty);
      await overview(tester, passengers: true);
      await tester.enterText(
        find.byKey(const Key('dashboard-search')),
        '가상 이용자 01',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dashboard-staff-s2')), findsOneWidget);
      expect(find.text('미확정 일정'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'overview follows date and period; absent passengers remain searchable',
    (tester) async {
      await open(tester);
      c.selectDate(DateTime(2026, 11, 17));
      c.selectPeriod(TransportPeriod.afternoon);
      await tester.pumpAndSettle();
      c.markAbsent('p80');
      await tester.pumpAndSettle();
      await overview(tester, passengers: true);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('selected-schedule-label')))
            .data,
        contains('11월 17일 (화) · 오후'),
      );
      expect(find.textContaining('배정 79명 · 결석 1명'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('dashboard-search')),
        '가상 이용자 80',
      );
      await tester.pumpAndSettle();
      expect(find.text('이용자 80 · 결석'), findsOneWidget);
      expect(find.byKey(const ValueKey('dashboard-staff-s20')), findsOneWidget);
      expect(repository.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reassignment warns at capacity and validation still blocks publication',
    (tester) async {
      await open(tester);
      c.movePassenger('p2', 'morning-2');
      c.movePassenger('p3', 'morning-2');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('visit-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('visit-p1')));
      await tester.pumpAndSettle();
      final move = find.byKey(const ValueKey('move-p1'));
      await tester.ensureVisible(move);
      await tester.pumpAndSettle();
      await tester.tap(move);
      await tester.pumpAndSettle();
      expect(find.textContaining('현재 6/6명 · 이동 후 7명 · 정원 초과'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('reassign-target-p1-morning-2')),
      );
      await tester.pumpAndSettle();
      expect(c.validationErrors.any((error) => error.contains('정원')), isTrue);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-schedule')))
            .onPressed,
        isNull,
      );
      expect(repository.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'small screen supports overview search, assignment detail and returning to staff',
    (tester) async {
      await open(tester, small: true);
      await overview(tester, passengers: true);
      await tester.enterText(
        find.byKey(const Key('dashboard-search')),
        '가상 이용자 80',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dashboard-staff-s20')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('staff-detail-s20')), findsOneWidget);
      await tester.tap(find.byKey(const Key('back-to-staff')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('staff-search')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
