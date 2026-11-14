import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/schedule_codec.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/utils/visit_time_wording.dart';

import 'support/fixtures.dart';

const admin = AppUser(uid: 'appointment-admin', role: UserRole.admin);
ScheduleSnapshot legacy(TransportPeriod period) {
  final c = fixtureController(user: admin);
  c.selectPeriod(period);
  final r = c.draft.routes.first;
  final snapshot = c.draft.copyWith(
    version: 1,
    confirmedAt: DateTime(2026),
    routes: [
      r.copyWith(
        estimatedVisitMinutes: {
          r.passengerIds[0]: 610,
          r.passengerIds[1]: 610,
          r.passengerIds[2]: 480,
        },
        estimatedVisitSources: {
          r.passengerIds[0]: 'manual',
          r.passengerIds[1]: 'fixedInterval',
        },
        startMinute: 600,
        endMinute: 540,
      ),
      ...c.draft.routes.skip(1),
    ],
  );
  c.dispose();
  return snapshot;
}

void main() {
  test('optional appointments may be absent, equal, reversed and outside legacy windows', () {
    final c = fixtureController(user: admin);
    addTearDown(c.dispose);
    c.confirm();
    c.setOperatingWindow('morning-a', 600, 540);
    c.setVisitMinute('morning-a', 'p1', 610);
    c.setVisitMinute('morning-a', 'p2', 610);
    c.setVisitMinute('morning-a', 'p3', 480);
    final values = routeToJson(c.draft.routes.first);
    c.reorder('morning-a', 0, 1);
    expect(c.confirmationErrors, isEmpty);
    c.confirm();
    expect(c.confirmed!.version, 2);
    expect(
      c.confirmed!.routes.first.estimatedVisitMinutes,
      values['estimatedVisitMinutes'],
    );
    expect(c.confirmed!.routes.first.startMinute, 600);
    expect(c.confirmed!.routes.first.endMinute, 540);
  });
  for (final period in TransportPeriod.values) {
    test(
      'legacy $period values survive reorder, transfer, exclusion and restoration',
      () {
        final loaded = legacy(period);
        final c = fixtureController(user: admin, initialConfirmed: [loaded]);
        addTearDown(c.dispose);
        c.selectPeriod(period);
        final first = c.draft.routes.first;
        final id = first.passengerIds[1];
        final original = first.estimatedVisitMinutes[id];
        c.reorder(first.baseRouteId, 0, 1);
        c.movePassenger(id, c.draft.routes.last.baseRouteId);
        expect(c.draft.routes.last.estimatedVisitMinutes[id], original);
        expect(c.draft.routes.last.estimatedVisitSources[id], 'fixedInterval');
        c.markAbsent(id);
        c.restorePassenger(id);
        final restored = c.draft.routes.firstWhere(
          (r) => r.passengerIds.contains(id),
        );
        expect(restored.estimatedVisitMinutes[id], original);
        expect(restored.estimatedVisitSources[id], 'fixedInterval');
        expect(c.confirmationErrors, isEmpty);
        c.confirm();
        final roundTrip = scheduleFromJson({
          ...scheduleToJson(c.confirmed!),
          'schemaVersion': 1,
          'status': 'confirmed',
          'timezone': 'Asia/Seoul',
          'version': c.confirmed!.version,
        }, c.confirmed!.confirmedAt!);
        expect(scheduleToJson(roundTrip), scheduleToJson(c.confirmed!));
        expect(
          c.confirmed!.routes.first.startMinute,
          loaded.routes.first.startMinute,
        );
      },
    );
  }
  test('only explicit AM input assigns manual; invalid or PM input does not mutate', () {
    final c = fixtureController(
      user: admin,
      initialConfirmed: [
        legacy(TransportPeriod.morning),
        legacy(TransportPeriod.afternoon),
      ],
    );
    addTearDown(c.dispose);
    expect(visitTimeText(c.period, c.draft.routes.first, 'p2'), isNull);
    expect(visitTimeText(c.period, c.draft.routes.first, 'p3'), isNull);
    c.setVisitMinute('morning-a', 'p2', 0);
    expect(c.draft.routes.first.estimatedVisitSources['p2'], 'manual');
    expect(visitTimeText(c.period, c.draft.routes.first, 'p2'), '약속 시간 00:00');
    for (final bad in [-1, 1440]) {
      final before = c.draft;
      expect(
        () => c.setVisitMinute('morning-a', 'p2', bad),
        throwsArgumentError,
      );
      expect(c.draft, same(before));
    }
    c.selectPeriod(TransportPeriod.afternoon);
    final before = scheduleToJson(c.draft);
    expect(() => c.setVisitMinute('afternoon-a', 'p3', null), throwsStateError);
    expect(scheduleToJson(c.draft), before);
  });

  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    testWidgets('AM manual-only edit and PM order-only screen at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = fixtureController(
        user: admin,
        initialConfirmed: [
          legacy(TransportPeriod.morning),
          legacy(TransportPeriod.afternoon),
        ],
      );
      addTearDown(c.dispose);
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
      if (find.byKey(const ValueKey('staff-detail-s1')).evaluate().isEmpty) {
        await tester.tap(find.byKey(const ValueKey('staff-s1')));
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('visit-p2')),
        120,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('staff-detail-s1')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('visit-p2')));
      await tester.pumpAndSettle();
      final edit = find.byKey(const ValueKey('time-p2'));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('estimated-time-0')),
            )
            .controller!
            .text,
        '',
      );
      expect(find.textContaining('이전 기록'), findsOneWidget);
      final before = scheduleToJson(c.draft);
      await tester.tap(find.byKey(const Key('save-estimated-time')));
      await tester.pumpAndSettle();
      expect(
        scheduleToJson(c.draft),
        before,
      ); // Blank does not erase historical data.
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('estimated-time-0')),
        '08:10',
      );
      await tester.tap(find.byKey(const Key('save-estimated-time')));
      await tester.pumpAndSettle();
      expect(c.draft.routes.first.estimatedVisitSources['p2'], 'manual');
      c.selectPeriod(TransportPeriod.afternoon);
      await tester.pumpAndSettle();
      if (find.byKey(const ValueKey('staff-detail-s1')).evaluate().isEmpty) {
        await tester.tap(find.byKey(const ValueKey('staff-s1')));
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('visit-p3')),
        -120,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('staff-detail-s1')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('visit-p3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('time-p3')), findsNothing);
      expect(find.textContaining('약속 시간'), findsNothing);
      expect(find.textContaining('기존 저장 시각'), findsNothing);
      expect(find.byKey(const Key('adjust-changed-times')), findsNothing);
      expect(find.byKey(const ValueKey('bulk-time-afternoon-a')), findsNothing);
      expect(
        c.draft.routes.first.estimatedVisitMinutes,
        legacy(TransportPeriod.afternoon).routes.first.estimatedVisitMinutes,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
