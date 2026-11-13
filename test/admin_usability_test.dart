import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/schedule_catalog.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';
import 'package:senior_transport_app/services/schedule_repository.dart';

import 'support/fixtures.dart';

void main() {
  const admin = AppUser(uid: 'fictional-admin', role: UserRole.admin);
  late ScheduleController c;
  setUp(
    () =>
        c = fixtureController(user: admin, initialDate: DateTime(2026, 11, 13)),
  );
  tearDown(() => c.dispose());
  Future<void> open(WidgetTester tester, {bool small = false}) async {
    tester.view.physicalSize = small
        ? const Size(320, 568)
        : const Size(1280, 900);
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
  }

  Future<void> moveDialog(WidgetTester tester) async {
    final visit = find.byKey(const ValueKey('visit-p1'));
    if (visit.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        visit,
        160,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('staff-detail-s1')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    } else {
      await tester.ensureVisible(visit);
    }
    await tester.pumpAndSettle();
    await tester.tap(visit);
    await tester.pumpAndSettle();
    final move = find.byKey(const ValueKey('move-p1'));
    await tester.ensureVisible(move);
    await tester.pumpAndSettle();
    await tester.tap(move);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'employee list uses name and numeric order, preserving catalog order',
    (tester) async {
      c.dispose();
      final base = demoCatalog();
      c = ScheduleController(
        user: admin,
        catalog: ScheduleCatalog(
          version: base.version,
          staff: const [
            Staff('s1', '직원 10'),
            Staff('s2', '직원 2'),
            Staff('s3', '직원 1'),
          ],
          vehicles: base.vehicles,
          passengers: base.passengers,
          baseRoutes: base.baseRoutes,
        ),
        initialDate: DateTime(2026, 11, 12),
      );
      await open(tester);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('staff-s3'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('staff-s2'))).dy),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('staff-s2'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('staff-s1'))).dy),
      );
      expect(c.catalog.staff.first.id, 's1');
    },
  );

  testWidgets(
    'reassignment searches names and combines work/capacity filters without writing',
    (tester) async {
      c.assign('morning-b', vehicleId: 'v3'); // Two occupants, capacity two.
      await open(tester);
      await moveDialog(tester);
      expect(find.textContaining('미배정 · 차량 미배정'), findsOneWidget);
      expect(find.textContaining('현재 2/2명 · 이동 후 3명 · 정원 초과'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reassignment-space')));
      await tester.pumpAndSettle();
      expect(find.text('검색·필터에 맞는 재배정 대상이 없습니다.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reassignment-space')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reassignment-available')));
      await tester.pumpAndSettle();
      expect(find.textContaining('미배정 · 차량 미배정'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('reassignment-search')),
        '이온유',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reassign-target-p1-morning-b')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('reassignment-search')),
        '없는 직원',
      );
      await tester.pumpAndSettle();
      expect(find.text('검색·필터에 맞는 재배정 대상이 없습니다.'), findsOneWidget);
      expect(c.confirmed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stale reassignment selection does not apply to an updated draft',
    (tester) async {
      await open(tester);
      await moveDialog(tester);
      c.markAbsent('p3');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('reassign-target-p1-morning-b')),
      );
      await tester.pumpAndSettle();
      expect(c.routesForStaff('s1').single.passengerIds, contains('p1'));
      expect(c.routesForStaff('s2').single.passengerIds, isNot(contains('p1')));
    },
  );

  testWidgets(
    'confirmation shows diff first and retains complete schedule on demand',
    (tester) async {
      c.confirm();
      c.markAbsent('p2');
      keepReviewedTimes(c);
      await open(tester);
      await tester.tap(find.byKey(const Key('confirm-schedule')));
      await tester.pumpAndSettle();
      expect(find.text('공유된 일정에서 1항목이 바뀝니다.'), findsOneWidget);
      expect(find.text('가상 어르신 B: 결석 처리'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('course-review-morning-a')));
      await tester.pumpAndSettle();
      expect(find.text('가상 어르신 B: 결석 처리'), findsOneWidget);
      expect(find.text('김다정 · 햇살 A코스'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('review-all-schedules')),
        120,
        scrollable: find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-all-schedules')));
      await tester.pumpAndSettle();
      expect(find.text('김다정 · 햇살 A코스'), findsOneWidget);
      expect(c.confirmed!.version, 1);
    },
  );

  testWidgets(
    'reverted changes are clearly identified without replacing confirmed data',
    (tester) async {
      c.confirm();
      c.setVisitMinute('morning-a', 'p1', null);
      await open(tester);
      expect(
        tester.widget(find.byKey(const Key('confirm-schedule'))),
        isA<TextButton>(),
      );
      await tester.tap(find.byKey(const Key('confirm-schedule')));
      await tester.pumpAndSettle();
      expect(find.text('기존 확정 일정과 변경사항이 없습니다.'), findsOneWidget);
      await tester.tap(find.text('계속 수정'));
      await tester.pumpAndSettle();
      expect(c.confirmed!.version, 1);
    },
  );

  testWidgets(
    'remote change while reviewing cannot approve a stale comparison',
    (tester) async {
      c.confirm();
      final initial = c.confirmed!;
      c.dispose();
      final repo = MemoryScheduleRepository();
      repo.snapshots[repo.key(initial.date, initial.period)] = initial;
      c = ScheduleController.remote(
        user: admin,
        repository: repo,
        clock: () => DateTime.utc(2026, 11, 13, 0),
      );
      addTearDown(repo.changes.close);
      await open(tester);
      c.markAbsent('p2');
      keepReviewedTimes(c);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-schedule')));
      await tester.pumpAndSettle();
      repo.changes.add(
        ScheduleViewData(repo.catalog, initial.copyWith(version: 2)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('approve-confirm')));
      await tester.pumpAndSettle();
      expect(repo.requests, isEmpty);
      expect(c.conflict, isTrue);
    },
  );

  testWidgets('small screen supports reassignment name search and filters', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('staff-s1')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpAndSettle();
    await moveDialog(tester);
    await tester.enterText(find.byKey(const Key('reassignment-search')), '이온유');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reassignment-space')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('reassign-target-p1-morning-b')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
