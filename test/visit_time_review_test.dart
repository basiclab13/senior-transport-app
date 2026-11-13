import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/models/visit_time_review.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';
import 'package:senior_transport_app/services/visit_time_calculator.dart';

import 'support/fixtures.dart';

void main() {
  const admin = AppUser(uid: 'admin', role: UserRole.admin);
  late ScheduleController c;
  setUp(() => c = fixtureController(user: admin));
  tearDown(() => c.dispose());

  test(
    'reorder preserves estimates and blocks confirmation until explicit review',
    () {
      c.confirm();
      final before = c.confirmed;
      c.reorder('morning-a', 0, 1);
      expect(c.pendingTimeReviewRouteIds, {'morning-a'});
      expect(c.confirmationErrors.join(), contains('재검토'));
      expect(c.confirm, throwsStateError);
      expect(c.confirmed, same(before));
      final snapshot = c.draft;
      c.keepVisitTimes('morning-a', expectedSnapshot: snapshot);
      expect(c.draft, same(snapshot));
      expect(
        c.timeReviews['morning-a']!.decision,
        VisitTimeReviewDecision.kept,
      );
      c.confirm();
      expect(c.confirmed!.version, 2);
      expect(c.timeReviews, isEmpty);
    },
  );

  test('both transfer sides need review; manual and legacy estimates move unchanged', () {
    c.setVisitMinute('morning-a', 'p1', 500);
    c.movePassenger('p1', 'morning-b');
    expect(c.pendingTimeReviewRouteIds, {'morning-a', 'morning-b'});
    expect(
      c.draft.routes.first.estimatedVisitMinutes.containsKey('p1'),
      isFalse,
    );
    expect(c.draft.routes.last.estimatedVisitMinutes['p1'], 500);
    expect(c.draft.routes.last.estimatedVisitSources['p1'], 'manual');
    c.movePassenger('p1', 'morning-a');
    expect(c.draft.routes.first.estimatedVisitMinutes['p1'], 500);
    expect(c.pendingTimeReviewRouteIds, {'morning-a', 'morning-b'});
  });

  for (final absent in [false, true]) {
    test(
      'exclude/absence ($absent) and restore preserve local estimates and require a new review',
      () {
        c.setVisitMinute('morning-a', 'p2', 495);
        c.excludePassenger('p2', absent: absent);
        c.keepVisitTimes('morning-a');
        c.restorePassenger('p2');
        expect(c.pendingTimeReviewRouteIds, {'morning-a'});
        expect(c.draft.routes.first.estimatedVisitMinutes['p2'], 495);
        expect(c.draft.routes.first.estimatedVisitSources['p2'], 'manual');
      },
    );
  }

  test('full course handoff preserves estimates and requires review', () {
    c.setVisitMinute('morning-a', 'p1', 490);
    c.assign('morning-a', staffId: 's3');
    expect(c.pendingTimeReviewRouteIds, {'morning-a'});
    expect(c.timeReviews['morning-a']!.reasons, contains('담당 직원 변경·코스 인계'));
    expect(c.draft.routes.first.estimatedVisitMinutes['p1'], 490);
  });

  test('keep rejects reversed, duplicate and out-of-window times without acknowledging', () {
    c.applyVisitTimePreview(previewVisitTimes(c.draft, 'morning-a', 480, 5));
    c.reorder('morning-a', 0, 1);
    expect(() => c.keepVisitTimes('morning-a'), throwsStateError);
    expect(c.pendingTimeReviewRouteIds, {'morning-a'});
    expect(c.confirm, throwsStateError);
    c.setVisitMinute('morning-a', 'p2', 480);
    expect(() => c.keepVisitTimes('morning-a'), throwsStateError);
    c.setVisitMinute('morning-a', 'p1', 485);
    c.setOperatingWindow('morning-a', 500, 550);
    expect(() => c.keepVisitTimes('morning-a'), throwsStateError);
  });

  test('preview cancellation changes nothing; application resolves and later changes invalidate it', () {
    c.reorder('morning-a', 0, 1);
    final old = c.draft;
    final preview = previewVisitTimes(old, 'morning-a', 480, 5);
    expect(c.draft, same(old));
    expect(c.pendingTimeReviewRouteIds, {'morning-a'});
    c.applyVisitTimePreview(preview);
    expect(c.pendingTimeReviewRouteIds, isEmpty);
    expect(
      c.timeReviews['morning-a']!.decision,
      VisitTimeReviewDecision.applied,
    );
    c.markAbsent('p3');
    expect(c.pendingTimeReviewRouteIds, {'morning-a'});
    expect(() => c.applyVisitTimePreview(preview), throwsStateError);
    expect(
      () => c.keepVisitTimes('morning-a', expectedSnapshot: old),
      throwsStateError,
    );
  });

  test('protected legacy no-op preview can be explicitly applied without rewriting sources', () {
    final legacy = c.draft.routes.first.copyWith(
      estimatedVisitMinutes: {'p1': 480, 'p2': 485, 'p3': 490},
    );
    final confirmed = c.draft.copyWith(
      routes: [legacy, c.draft.routes.last],
      version: 1,
      confirmedAt: DateTime(2026),
    );
    c.dispose();
    c = fixtureController(user: admin, initialConfirmed: [confirmed]);
    c.excludePassenger('p3');
    final snapshot = c.draft;
    final preview = previewVisitTimes(snapshot, 'morning-a', 500, 10);
    expect(preview.protectedIds, {'p1', 'p2'});
    c.applyVisitTimePreview(preview);
    expect(c.draft, same(snapshot));
    expect(c.draft.routes.first.estimatedVisitSources, isEmpty);
    expect(c.pendingTimeReviewRouteIds, isEmpty);
  });

  test('review and removed estimates stay in their dated period; empty course can be reviewed', () {
    c.setVisitMinute('morning-a', 'p1', 480);
    c.markAbsent('p1');
    c.markAbsent('p2');
    c.markAbsent('p3');
    expect(c.draft.routes.first.passengerIds, isEmpty);
    c.keepVisitTimes('morning-a');
    c.selectPeriod(TransportPeriod.afternoon);
    expect(c.timeReviews, isEmpty);
    c.selectPeriod(TransportPeriod.morning);
    c.selectDate(DateTime(2026, 11, 13));
    expect(c.timeReviews, isEmpty);
    c.selectDate(DateTime(2026, 11, 12));
    expect(c.timeReviews['morning-a']!.decision, VisitTimeReviewDecision.kept);
    c.restorePassenger('p1');
    expect(c.draft.routes.first.estimatedVisitMinutes['p1'], 480);
    expect(c.pendingTimeReviewRouteIds, {'morning-a'});
  });

  test('remote pending gate makes no request; failed save keeps review and reload discards it', () async {
    c.dispose();
    final repo = MemoryScheduleRepository();
    addTearDown(repo.changes.close);
    c = ScheduleController.remote(
      user: admin,
      repository: repo,
      clock: fixtureClock,
    );
    await Future<void>.delayed(Duration.zero);
    c.markAbsent('p2');
    expect(await c.publish(), isFalse);
    expect(repo.requests, isEmpty);
    c.keepVisitTimes('morning-a');
    repo.publishFailure = StateError('offline');
    expect(await c.publish(), isFalse);
    expect(c.timeReviews['morning-a']!.decision, VisitTimeReviewDecision.kept);
    await c.reloadDiscardingDraft();
    expect(c.timeReviews, isEmpty);
    expect(c.hasPendingChanges, isFalse);
  });

  test('staff cannot acknowledge administrator review', () {
    final staff = fixtureController(
      user: const AppUser(uid: 'staff', role: UserRole.staff, staffId: 's1'),
    );
    addTearDown(staff.dispose);
    expect(() => staff.keepVisitTimes('morning-a'), throwsStateError);
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
    if (small) {
      await tester.tap(find.byKey(const ValueKey('staff-s1')));
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'review badge offers immediate preview and explicit keep, with confirmation gated',
    (tester) async {
      c.markAbsent('p2');
      await open(tester);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-schedule')))
            .onPressed,
        isNull,
      );
      expect(find.text('방문 시간 다시 맞추기'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('keep-times-morning-a')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('keep-times-morning-a')));
      await tester.pumpAndSettle();
      expect(find.text('기존 방문 시간 확인'), findsOneWidget);
      expect(c.pendingTimeReviewRouteIds, {'morning-a'});
      await tester.tap(find.byKey(const Key('approve-keep-times')));
      await tester.pumpAndSettle();
      expect(c.pendingTimeReviewRouteIds, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-schedule')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('confirm-schedule')));
      await tester.pumpAndSettle();
      expect(find.textContaining('방문 시간 확인 완료 · 1코스'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'membership changed while preview is open cannot apply old calculated results',
    (tester) async {
      c.reorder('morning-a', 0, 1);
      await open(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('bulk-time-morning-a')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bulk-time-morning-a')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('bulk-first-minute')),
        '08:00',
      );
      await tester.enterText(find.byKey(const Key('bulk-interval')), '5');
      await tester.tap(find.byKey(const Key('calculate-visit-preview')));
      await tester.pumpAndSettle();
      c.markAbsent('p3');
      final current = c.draft;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apply-bulk-visit-times')));
      await tester.pumpAndSettle();
      expect(c.draft, same(current));
      expect(c.draft.routes.first.estimatedVisitMinutes, isEmpty);
      expect(c.pendingTimeReviewRouteIds, {'morning-a'});
      expect(find.textContaining('최신 방문 순서로 다시 계산'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changed order while keep confirmation is open rejects stale acknowledgement',
    (tester) async {
      c.markAbsent('p3');
      await open(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('keep-times-morning-a')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('keep-times-morning-a')));
      await tester.pumpAndSettle();
      c.reorder('morning-a', 0, 1);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('approve-keep-times')));
      await tester.pumpAndSettle();
      expect(c.pendingTimeReviewRouteIds, {'morning-a'});
      expect(find.textContaining('최신 시각을 다시 검토'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keep dialog blocks conflict, small layout offers direct B-1 preview',
    (tester) async {
      c.applyVisitTimePreview(previewVisitTimes(c.draft, 'morning-a', 480, 5));
      c.reorder('morning-a', 0, 1);
      await open(tester, small: true);
      await tester.ensureVisible(
        find.byKey(const ValueKey('keep-times-morning-a')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('keep-times-morning-a')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('approve-keep-times')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('bulk-time-morning-a')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bulk-time-morning-a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calculate-visit-preview')), findsOneWidget);
      expect(c.pendingTimeReviewRouteIds, {'morning-a'});
      expect(tester.takeException(), isNull);
    },
  );
}
