import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';

import 'ai_schedule_suggestion_test.dart' show FixedSuggestionRepository;
import 'support/fixtures.dart';

void main() {
  const admin = AppUser(uid: 'admin', role: UserRole.admin);
  late FixedSuggestionRepository repo;
  late ScheduleController c;
  setUp(() async {
    repo = FixedSuggestionRepository();
    c = ScheduleController.remote(
      user: admin,
      repository: repo,
      clock: fixtureClock,
    );
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() async {
    c.dispose();
    await repo.changes.close();
    await repo.availabilityChanges.close();
    await repo.availabilityEvents.close();
  });
  Future<void> baseline() async {
    c.setOperatingWindow('morning-a', 480, 570);
    c.setOperatingWindow('morning-b', 480, 570);
    for (final entry in {'p1': 490, 'p2': 495, 'p3': 500}.entries) {
      c.setVisitMinute('morning-a', entry.key, entry.value);
    }
    for (final entry in {'p4': 490, 'p5': 495}.entries) {
      c.setVisitMinute('morning-b', entry.key, entry.value);
    }
    expect(await c.publish(), isTrue);
    await Future<void>.value();
    await Future<void>.value();
  }

  test('all courses update atomically only after manual confirmation, with final publication kept separate', () async {
    await baseline();
    final previous = c.confirmed!;
    c.movePassenger('p1', 'morning-b');
    final original = c.draft;
    final plan = c.prepareVisitTimeBatch({
      'morning-a': 495,
      'morning-b': 490,
    }, 5);
    expect(plan.routeIds, {'morning-a', 'morning-b'});
    expect(plan.manualChanges, 1);
    expect(c.draft, same(original));
    expect(() => c.applyVisitTimeBatch(plan), throwsStateError);
    expect(c.draft, same(original));
    var notifications = 0;
    c.addListener(() => notifications++);
    c.applyVisitTimeBatch(plan, manualOverwriteConfirmed: true);
    expect(notifications, 1);
    expect(c.pendingTimeReviewRouteIds, isEmpty);
    expect(c.draft.routes.last.estimatedVisitMinutes['p1'], 500);
    expect(c.draft.routes.last.estimatedVisitSources['p1'], 'fixedInterval');
    expect(c.draft.routes.last.estimatedVisitSources['p4'], 'manual');
    expect(c.confirmed, same(previous));
    expect(repo.requests.length, 1);
    expect(await c.publish(), isTrue);
    expect(c.confirmed!.version, 2);
    expect(previous.routes.first.estimatedVisitMinutes['p1'], 490);
  });
  test('unchanged legacy times keep missing provenance', () async {
    final s = c.draft;
    repo.snapshots[repo.key(s.date, s.period)] = s.copyWith(
      version: 1,
      confirmedAt: DateTime(2026),
      routes: [
        s.routes.first.copyWith(
          estimatedVisitMinutes: {'p1': 490, 'p2': 495, 'p3': 500},
        ),
        s.routes.last,
      ],
    );
    await c.reloadDiscardingDraft();
    await Future<void>.delayed(Duration.zero);
    c.excludePassenger('p3');
    final plan = c.prepareVisitTimeBatch({'morning-a': 490}, 5);
    expect(plan.manualChanges, 0);
    c.applyVisitTimeBatch(plan);
    expect(c.draft.routes.first.estimatedVisitSources, isEmpty);
    expect(c.draft.routes.first.estimatedVisitMinutes, {'p1': 490, 'p2': 495});
  });
  for (final change in ['order', 'absence', 'date']) {
    test('$change change invalidates the whole review', () async {
      await baseline();
      c.reorder('morning-a', 0, 1);
      final plan = c.prepareVisitTimeBatch({'morning-a': 490}, 5);
      if (change == 'order') c.reorder('morning-a', 1, 1);
      if (change == 'absence') {
        await c.setStaffAbsence('s3', {TransportPeriod.morning}, true, 0);
      }
      if (change == 'date') {
        c.selectDate(DateTime(2026, 11, 13));
        await Future<void>.delayed(Duration.zero);
      }
      final original = c.draft;
      expect(
        () => c.applyVisitTimeBatch(plan, manualOverwriteConfirmed: true),
        throwsStateError,
      );
      expect(c.draft, same(original));
    });
  }
  test('operating-window, zero interval and midnight failures preserve all courses', () async {
    await baseline();
    c.reorder('morning-a', 0, 1);
    c.reorder('morning-b', 0, 1);
    final original = c.draft;
    final invalid = c.prepareVisitTimeBatch({
      'morning-a': 490,
      'morning-b': 490,
    }, 100);
    expect(
      () => c.applyVisitTimeBatch(invalid, manualOverwriteConfirmed: true),
      throwsStateError,
    );
    expect(
      () => c.prepareVisitTimeBatch({'morning-a': 490, 'morning-b': 490}, 0),
      throwsArgumentError,
    );
    expect(
      () => c.prepareVisitTimeBatch({'morning-a': 1435, 'morning-b': 490}, 5),
      throwsArgumentError,
    );
    expect(c.draft, same(original));
    expect(await c.publish(), isFalse);
  });
  test('empty course is acknowledged without invented times', () {
    for (final id in ['p1', 'p2', 'p3']) {
      c.excludePassenger(id);
    }
    final plan = c.prepareVisitTimeBatch({}, 5);
    expect(plan.previews, isEmpty);
    c.applyVisitTimeBatch(plan);
    expect(c.pendingTimeReviewRouteIds, isEmpty);
    expect(c.draft.routes.first.estimatedVisitMinutes, isEmpty);
  });
  test('batch is limited to selected date/period and staff cannot prepare or apply it', () async {
    await baseline();
    c.reorder('morning-a', 0, 1);
    final plan = c.prepareVisitTimeBatch({'morning-a': 490}, 5);
    final staff = fixtureController(
      user: const AppUser(uid: 'staff', role: UserRole.staff, staffId: 's1'),
    );
    addTearDown(staff.dispose);
    expect(
      () => staff.prepareVisitTimeBatch({'morning-a': 490}, 5),
      throwsStateError,
    );
    expect(
      () => staff.applyVisitTimeBatch(plan, manualOverwriteConfirmed: true),
      throwsStateError,
    );
    c.applyVisitTimeBatch(plan, manualOverwriteConfirmed: true);
    c.selectPeriod(TransportPeriod.afternoon);
    await Future<void>.delayed(Duration.zero);
    expect(c.draft.routes.first.estimatedVisitMinutes, isEmpty);
    expect(c.pendingTimeReviewRouteIds, isEmpty);
    c.selectDate(DateTime(2026, 11, 13));
    await Future<void>.delayed(Duration.zero);
    c.selectPeriod(TransportPeriod.morning);
    await Future<void>.delayed(Duration.zero);
    expect(c.draft.routes.first.estimatedVisitMinutes, isEmpty);
  });
  Future<void> open(WidgetTester tester, {bool small = false}) async {
    tester.view.physicalSize = small
        ? const Size(390, 844)
        : const Size(1280, 1000);
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

  testWidgets(
    'AI → time adjustment → manual confirmation → separate final confirmation',
    (tester) async {
      await baseline();
      await open(tester);
      await tester.tap(find.byKey(const Key('suggest-schedule')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('approve-ai-suggestion')));
      await tester.pumpAndSettle();
      expect(find.text('방문 시간 한 번에 맞추기'), findsOneWidget);
      final original = c.draft;
      expect(c.pendingTimeReviewRouteIds, {'morning-a'});
      expect(c.confirmed!.version, 1);
      await tester.tap(find.byKey(const Key('apply-batch-times')));
      await tester.pumpAndSettle();
      expect(find.text('직접 입력한 방문 시간도 바꿀까요?'), findsOneWidget);
      expect(c.draft, same(original));
      await tester.tap(find.text('바꾸지 않기'));
      await tester.pumpAndSettle();
      expect(c.draft, same(original));
      await tester.tap(find.byKey(const Key('apply-batch-times')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-batch-manual-times')));
      await tester.pumpAndSettle();
      expect(c.pendingTimeReviewRouteIds, isEmpty);
      expect(c.confirmed!.version, 1);
      expect(c.draft.routes.first.estimatedVisitMinutes['p3'], 490);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await tester.tap(find.byKey(const Key('confirm-schedule')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('approve-confirm')));
      await tester.pumpAndSettle();
      expect(c.confirmed!.version, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('small screen can defer, resume and reject a stale time review', (
    tester,
  ) async {
    await baseline();
    c.reorder('morning-a', 0, 1);
    await open(tester, small: true);
    await tester.tap(find.byKey(const Key('adjust-changed-times')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('나중에 하기'));
    await tester.pumpAndSettle();
    expect(c.pendingTimeReviewRouteIds, {'morning-a'});
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('confirm-schedule')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('adjust-changed-times')));
    await tester.pumpAndSettle();
    await c.setStaffAbsence('s3', {TransportPeriod.morning}, true, 0);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('apply-batch-times')))
          .onPressed,
      isNull,
    );
    expect(c.confirmed!.version, 1);
    expect(tester.takeException(), isNull);
  });
}
