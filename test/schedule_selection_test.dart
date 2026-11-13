import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';
import 'package:senior_transport_app/services/schedule_repository.dart';
import 'package:senior_transport_app/services/schedule_selection_policy.dart';

import 'support/fixtures.dart';

class TrackingRepository extends MemoryScheduleRepository {
  final watches = <String>[];
  @override
  Stream<ScheduleViewData> watch(
    AppUser user,
    DateTime date,
    TransportPeriod period,
  ) {
    watches.add('${dateKey(date)}_${period.name}');
    return super.watch(user, date, period);
  }
}

void main() {
  const policy = ScheduleSelectionPolicy();
  const admin = AppUser(uid: 'fictional-admin', role: UserRole.admin);
  const staff = AppUser(
    uid: 'fictional-staff',
    role: UserRole.staff,
    staffId: 's1',
  );

  for (final sample in [
    ('2026-11-11T15:00:00Z', '2026-11-12', TransportPeriod.morning),
    ('2026-11-12T00:29:59.999Z', '2026-11-12', TransportPeriod.morning),
    ('2026-11-12T00:30:00Z', '2026-11-12', TransportPeriod.afternoon),
    ('2026-11-12T09:59:59.999Z', '2026-11-12', TransportPeriod.afternoon),
    ('2026-11-12T10:00:00Z', '2026-11-13', TransportPeriod.morning),
    ('2026-11-12T11:00:00Z', '2026-11-13', TransportPeriod.morning),
    ('2026-11-12T14:59:59.999Z', '2026-11-13', TransportPeriod.morning),
    ('2026-11-12T15:00:00Z', '2026-11-13', TransportPeriod.morning),
    ('2026-12-31T10:00:00Z', '2027-01-01', TransportPeriod.morning),
    ('2028-02-28T10:00:00Z', '2028-02-29', TransportPeriod.morning),
    ('2026-11-30T10:00:00Z', '2026-12-01', TransportPeriod.morning),
  ]) {
    test('Seoul boundary ${sample.$1}', () {
      final selection = policy.select(DateTime.parse(sample.$1));
      expect(dateKey(selection.date), sample.$2);
      expect(selection.period, sample.$3);
    });
  }

  test(
    'instant conversion ignores device zone and cutoffs are configurable',
    () {
      final selection = policy.select(
        DateTime.parse('2026-11-12T11:30:00+11:00'),
      );
      expect(dateKey(selection.date), '2026-11-12');
      expect(selection.period, TransportPeriod.afternoon);
      const custom = ScheduleSelectionPolicy(
        afternoonFromMinute: 8 * 60 + 45,
        nextMorningFromMinute: 18 * 60,
      );
      expect(
        custom.select(DateTime.parse('2026-11-11T23:45:00Z')).period,
        TransportPeriod.afternoon,
      );
      expect(
        dateKey(custom.select(DateTime.parse('2026-11-12T09:00:00Z')).date),
        '2026-11-13',
      );
      expect(
        () => ScheduleSelectionPolicy(
          afternoonFromMinute: 1200,
          nextMorningFromMinute: 600,
        ),
        throwsAssertionError,
      );
    },
  );

  test(
    'relative labels use Seoul calendar; other dates include year and weekday',
    () {
      final instant = DateTime.parse('2026-11-11T23:00:00Z');
      expect(
        policy.describe(
          DateTime(2026, 11, 12),
          TransportPeriod.afternoon,
          instant,
        ),
        '오늘 · 11월 12일 (목) · 오후',
      );
      expect(
        policy.describe(
          DateTime(2026, 11, 13),
          TransportPeriod.morning,
          instant,
        ),
        '내일 · 11월 13일 (금) · 오전',
      );
      expect(
        policy.describe(
          DateTime(2026, 11, 11),
          TransportPeriod.morning,
          instant,
        ),
        '2026년 11월 11일 (수) · 오전',
      );
    },
  );

  test('manual selection and edits survive time boundaries and explicit current return', () {
    var now = DateTime.parse('2026-11-12T00:29:00Z');
    final c = fixtureController(user: admin, clock: () => now);
    addTearDown(c.dispose);
    expect(c.period, TransportPeriod.morning);
    c.selectDate(DateTime(2026, 11, 18));
    c.selectPeriod(TransportPeriod.afternoon);
    c.markAbsent('p1');
    now = DateTime.parse('2026-11-13T10:00:00Z');
    c.setVisitMinute('afternoon-a', 'p2', 1000);
    final edited = c.draft;
    expect(dateKey(c.selectedDate), '2026-11-18');
    expect(c.period, TransportPeriod.afternoon);
    c.selectCurrentSchedule();
    expect(dateKey(c.selectedDate), '2026-11-14');
    expect(c.period, TransportPeriod.morning);
    c.selectDate(DateTime(2026, 11, 18));
    c.selectPeriod(TransportPeriod.afternoon);
    expect(c.draft, same(edited));
    expect(c.hasPendingChanges, isTrue);
  });

  test('remote current selection changes date and period in one subscription, without publishing', () async {
    var now = DateTime.parse('2026-11-12T00:30:00Z');
    final repository = TrackingRepository();
    final c = ScheduleController.remote(
      user: admin,
      repository: repository,
      clock: () => now,
    );
    addTearDown(() async {
      c.dispose();
      await repository.changes.close();
    });
    await Future<void>.delayed(Duration.zero);
    expect(repository.watches, ['2026-11-12_afternoon']);
    repository.watches.clear();
    now = DateTime.parse('2026-11-12T10:00:00Z');
    c.retryLoad(); // Server refresh cannot silently switch the active selection.
    await Future<void>.delayed(Duration.zero);
    expect(c.period, TransportPeriod.afternoon);
    repository.watches.clear();
    c.selectCurrentSchedule();
    await Future<void>.delayed(Duration.zero);
    expect(repository.watches, ['2026-11-13_morning']);
    c.selectCurrentSchedule();
    expect(repository.watches.length, 1);
    expect(repository.requests, isEmpty);
    c.saving = true;
    now = DateTime.parse('2026-11-14T10:00:00Z');
    c.selectCurrentSchedule();
    expect(dateKey(c.selectedDate), '2026-11-13');
    c.saving = false;
  });

  for (final user in [admin, staff]) {
    testWidgets(
      '${user.role.name}: shared label, manual period stays pinned and current button recomputes',
      (tester) async {
        var now = DateTime.parse('2026-11-12T00:30:00Z');
        final c = fixtureController(user: user, clock: () => now);
        addTearDown(c.dispose);
        tester.view.physicalSize = const Size(1280, 900);
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
        expect(find.text('오늘 · 11월 12일 (목) · 오후'), findsOneWidget);
        await tester.tap(find.text('오전').first);
        await tester.pumpAndSettle();
        expect(c.period, TransportPeriod.morning);
        now = DateTime.parse('2026-11-12T10:00:00Z');
        await tester.pump(const Duration(hours: 12));
        await tester.pumpAndSettle();
        expect(dateKey(c.selectedDate), '2026-11-12');
        expect(c.period, TransportPeriod.morning);
        await tester.tap(find.byKey(const Key('current-schedule')));
        await tester.pumpAndSettle();
        expect(find.text('내일 · 11월 13일 (금) · 오전'), findsOneWidget);
        expect(dateKey(c.selectedDate), '2026-11-13');
        tester.view.physicalSize = const Size(320, 568);
        await tester.pumpAndSettle();
        expect(find.text('내일 · 11월 13일 (금) · 오전'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'confirmation names the actual manual future date, weekday and afternoon',
    (tester) async {
      final c = fixtureController(
        user: admin,
        initialDate: DateTime(2026, 11, 16),
      );
      addTearDown(c.dispose);
      c.selectPeriod(TransportPeriod.afternoon);
      tester.view.physicalSize = const Size(1280, 900);
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
      expect(find.text('2026년 11월 16일 (월) · 오후'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-schedule')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('confirmation-target'))).data,
        contains('2026-11-16 (월) · 오후'),
      );
      expect(c.confirmed, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
