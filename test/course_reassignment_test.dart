import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/course_reassignment.dart';
import 'package:senior_transport_app/models/schedule_changes.dart';
import 'package:senior_transport_app/models/schedule_catalog.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';
import 'package:senior_transport_app/widgets/course_reassignment_dialog.dart';

import 'staff_absence_test.dart' show AbsenceRepository;
import 'admin_overview_test.dart' show operatingCatalog;
import 'support/fixtures.dart';

void main() {
  const admin = AppUser(uid: 'admin', role: UserRole.admin);
  const am = TransportPeriod.morning;
  const pm = TransportPeriod.afternoon;
  late AbsenceRepository repo;
  late ScheduleController c;
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  setUp(() async {
    repo = AbsenceRepository();
    c = ScheduleController.remote(
      user: admin,
      repository: repo,
      clock: fixtureClock,
    );
    await settle();
  });
  tearDown(() async {
    c.dispose();
    await repo.changes.close();
    await repo.availabilityChanges.close();
    await repo.availabilityEvents.close();
  });

  test('whole course changes only the draft owner and preserves vehicle, stops and all manually entered times', () async {
    c.setVisitMinute('morning-a', 'p1', 490);
    c.setVisitMinute('morning-a', 'p2', 500);
    c.setOperatingWindow('morning-a', 480, 570);
    await c.publish();
    final confirmed = c.confirmed!;
    final original = c.draft.routes.first;
    await c.setStaffAbsence('s1', {am, pm}, true, 0);
    c.reassignAbsentCourse('morning-a', 's3');
    final moved = c.draft.routes.first;
    expect(moved.staffId, 's3');
    expect(moved.vehicleId, original.vehicleId);
    expect(moved.passengerIds, original.passengerIds);
    expect(moved.estimatedVisitMinutes, original.estimatedVisitMinutes);
    expect(moved.startMinute, original.startMinute);
    expect(moved.endMinute, original.endMinute);
    expect(c.confirmed, same(confirmed));
    expect(repo.requests.length, 1);
    expect(c.hasPendingChanges, isTrue);
    expect(c.reassignmentNeeded, isFalse);
    expect(c.confirmedReassignmentNeeded, isTrue);
    final diff = ScheduleChanges.compare(confirmed, c.draft, c.catalog);
    expect(
      diff.items
          .where((d) => d.kind == ScheduleChangeKind.staff)
          .single
          .description,
      contains('김다정 → 박여유'),
    );
    expect(
      diff.items.where((d) => d.kind == ScheduleChangeKind.order),
      isEmpty,
    );
    expect(c.validationErrors, isEmpty);
    c.selectPeriod(pm);
    await settle();
    expect(c.draft.routes.first.staffId, 's1');
    expect(c.reassignmentNeeded, isTrue);
    c.selectDate(DateTime(2026, 11, 13));
    await settle();
    expect(c.isStaffAbsent('s1'), isFalse);
    expect(c.draft.routes.first.staffId, 's1');
    c.selectDate(DateTime(2026, 11, 12));
    c.selectPeriod(am);
    await settle();
    expect(c.draft.routes.first.staffId, 's3');
  });

  test('available staff already assigned a course cannot take a second; rejection preserves unresolved source', () async {
    await c.setStaffAbsence('s1', {am}, true, 0);
    final original = c.draft;
    expect(() => c.reassignAbsentCourse('morning-a', 's2'), throwsStateError);
    expect(c.draft, same(original));
    expect(c.reassignmentNeeded, isTrue);
    expect(c.hasPendingChanges, isFalse);
    expect(await c.publish(), isFalse);
  });

  test('non-absent source, absent target, weekly leave and stale schedule conflict are rejected', () async {
    expect(() => c.reassignAbsentCourse('morning-a', 's3'), throwsStateError);
    await c.setStaffAbsence('s1', {am}, true, 0);
    await c.setStaffAbsence('s3', {am}, true, 0);
    expect(() => c.reassignAbsentCourse('morning-a', 's3'), throwsStateError);
    await c.setStaffAbsence('s3', {am}, false, 1);
    c.conflict = true;
    expect(() => c.reassignAbsentCourse('morning-a', 's3'), throwsStateError);
    c.conflict = false;
    c.selectDate(DateTime(2026, 11, 13));
    await settle();
    await c.setStaffAbsence('s1', {am}, true, 0);
    expect(() => c.reassignAbsentCourse('morning-a', 's3'), throwsStateError);
  });

  test('one unresolved absent employee continues blocking the entire schedule after another transfer', () async {
    await c.setStaffAbsence('s1', {am}, true, 0);
    await c.setStaffAbsence('s2', {am}, true, 0);
    c.reassignAbsentCourse('morning-a', 's3');
    expect(c.reassignmentNeeded, isTrue);
    expect(c.validationErrors.any((e) => e.contains('결근 직원')), isTrue);
    expect(await c.publish(), isFalse);
  });

  test('capacity and duplicate vehicle warnings block transfer without silently choosing another vehicle', () async {
    final snapshot = c.draft;
    final route = snapshot.routes.first;
    final target = c.staff('s3');
    final tooSmall = ScheduleCatalog(
      version: c.catalog.version,
      staff: c.catalog.staff,
      vehicles: [for (final v in c.catalog.vehicles) Vehicle(v.id, v.name, 1)],
      passengers: c.catalog.passengers,
      baseRoutes: c.catalog.baseRoutes,
    );
    expect(
      courseReassignmentBlockReason(tooSmall, snapshot, route, target, {'s1'}),
      contains('정원 초과'),
    );
    final duplicate = snapshot.copyWith(
      routes: [
        route,
        snapshot.routes[1].copyWith(vehicleId: route.vehicleId),
      ],
    );
    expect(
      courseReassignmentBlockReason(c.catalog, duplicate, route, target, {
        's1',
      }),
      contains('차량 중복'),
    );
  });

  test('first confirmation summary includes original and new staff before any confirmed history exists', () async {
    await c.setStaffAbsence('s1', {am}, true, 0);
    c.reassignAbsentCourse('morning-a', 's3');
    final summary = ScheduleChanges.compare(null, c.draft, c.catalog);
    expect(summary.initial, isTrue);
    expect(summary.items.single.description, contains('김다정 → 박여유'));
    c.dispose();
    c = ScheduleController.remote(
      user: const AppUser(uid: 'employee', role: UserRole.staff, staffId: 's1'),
      repository: repo,
      clock: fixtureClock,
    );
    await settle();
    expect(() => c.reassignAbsentCourse('morning-a', 's3'), throwsStateError);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
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
  }

  testWidgets(
    'source-detail action searches candidates, disables occupied staff, previews handoff in confirmation',
    (tester) async {
      await c.publish();
      await c.setStaffAbsence('s1', {am}, true, 0);
      await open(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('transfer-course-morning-a')),
      );
      await tester.tap(find.byKey(const ValueKey('transfer-course-morning-a')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('course-transfer-target-s2')),
            )
            .onTap,
        isNull,
      );
      expect(find.textContaining('현재 이용자 2명'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('course-transfer-search')),
        '박여유',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-transfer-target-s3')));
      await tester.pumpAndSettle();
      expect(c.draft.routes.first.staffId, 's3');
      expect(c.confirmed!.routes.first.staffId, 's1');
      await tester.tap(find.byKey(const Key('confirm-schedule')));
      await tester.pumpAndSettle();
      expect(find.textContaining('김다정 → 박여유'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'availability change while candidate dialog is open rejects stale selection',
    (tester) async {
      await c.setStaffAbsence('s1', {am}, true, 0);
      await open(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('transfer-course-morning-a')),
      );
      await tester.tap(find.byKey(const ValueKey('transfer-course-morning-a')));
      await tester.pumpAndSettle();
      await c.setStaffAbsence('s3', {am}, true, 0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-transfer-target-s3')));
      await tester.pumpAndSettle();
      expect(c.draft.routes.first.staffId, 's1');
      expect(find.textContaining('대상을 다시 확인'), findsOneWidget);
    },
  );

  testWidgets(
    '20 staff 80 passengers, small-screen candidate search shows no eligible staff without changing draft',
    (tester) async {
      final catalog = operatingCatalog();
      final preview = ScheduleController(
        user: admin,
        catalog: catalog,
        initialDate: DateTime(2026, 11, 16),
        clock: fixtureClock,
      );
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(preview.dispose);
      final original = preview.draft;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (_) => CourseReassignmentDialog(
                    catalog: catalog,
                    snapshot: original,
                    route: original.routes.first,
                    absentStaffIds: const {'s1'},
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('course-transfer-search')),
        '직원 20',
      );
      await tester.pumpAndSettle();
      expect(find.text('가상 직원 20'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('course-transfer-target-s20')),
            )
            .onTap,
        isNull,
      );
      await tester.tap(find.text('재배정 가능만'));
      await tester.pumpAndSettle();
      expect(find.textContaining('재배정 필요 상태가 유지'), findsOneWidget);
      expect(preview.draft, same(original));
      expect(tester.takeException(), isNull);
    },
  );
}
