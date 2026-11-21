import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/widgets/passenger_details_dialog.dart';
import 'package:senior_transport_app/widgets/route_timeline.dart';

import 'support/fixtures.dart';

const admin = AppUser(uid: 'details-admin', role: UserRole.admin);
void main() {
  test('default appointments last across dates; explicit dated overrides and confirmed snapshots stay frozen', () async {
    final c = fixtureController(user: admin);
    addTearDown(c.dispose);
    await c.savePassengerDetails(
      'p1',
      note: '천천히 안내',
      defaultMorningMinute: 510,
    );
    expect(c.draft.routes.first.estimatedVisitMinutes['p1'], 510);
    c.confirm();
    final frozen = c.confirmed;
    await c.savePassengerDetails(
      'p1',
      note: '문 앞에서 안내',
      defaultMorningMinute: 525,
    );
    expect(identical(c.confirmed, frozen), isTrue);
    expect(c.draft.routes.first.estimatedVisitMinutes['p1'], 510);
    c.selectDate(DateTime(2026, 11, 14));
    expect(c.draft.routes.first.estimatedVisitMinutes['p1'], 525);
    expect(c.draft.routes.first.estimatedVisitSources['p1'], 'manual');
    c.setVisitMinute('morning-a', 'p1', 600);
    await c.savePassengerDetails(
      'p1',
      note: '문 앞에서 안내',
      defaultMorningMinute: 540,
    );
    expect(c.draft.routes.first.estimatedVisitMinutes['p1'], 600);
    c.confirm();
    c.selectDate(DateTime(2026, 11, 15));
    expect(c.draft.routes.first.estimatedVisitMinutes['p1'], 540);
    c.setVisitMinute('morning-a', 'p1', null);
    expect(
      c.draft.routes.first.estimatedVisitMinutes.containsKey('p1'),
      isFalse,
    );
    c.selectDate(DateTime(2026, 11, 16));
    expect(c.draft.routes.first.estimatedVisitMinutes['p1'], 540);
    c.selectPeriod(TransportPeriod.afternoon);
    expect(c.draft.routes.first.estimatedVisitMinutes, isEmpty);
    expect(c.passenger('p1').note, '문 앞에서 안내');
  });

  test(
    'legacy automatic and unlabelled values are never promoted to defaults',
    () async {
      final source = fixtureController(user: admin);
      source.setVisitMinute('morning-a', 'p1', 490);
      source.confirm();
      final stored = source.confirmed!.copyWith(
        routes: [
          source.confirmed!.routes.first.copyWith(
            estimatedVisitSources: {'p1': 'fixedInterval'},
          ),
          ...source.confirmed!.routes.skip(1),
        ],
      );
      source.dispose();
      final c = fixtureController(user: admin, initialConfirmed: [stored]);
      addTearDown(c.dispose);
      expect(c.passenger('p1').defaultMorningMinute, isNull);
      await c.savePassengerDetails('p1', note: '', defaultMorningMinute: 550);
      expect(c.draft.routes.first.estimatedVisitSources['p1'], 'fixedInterval');
      expect(c.draft.routes.first.estimatedVisitMinutes['p1'], 490);
      c.selectDate(DateTime(2026, 11, 14));
      expect(c.draft.routes.first.estimatedVisitMinutes['p1'], 550);
      expect(c.passenger('p1').note, isEmpty);
    },
  );

  test('staff cannot edit passenger defaults or notes', () async {
    final c = fixtureController(
      user: const AppUser(
        uid: 'details-staff',
        role: UserRole.staff,
        staffId: 's1',
      ),
    );
    addTearDown(c.dispose);
    await expectLater(
      c.savePassengerDetails('p1', note: '변경', defaultMorningMinute: 500),
      throwsStateError,
    );
  });

  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    testWidgets('overview and basic information time picker fit $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = fixtureController(user: admin);
      addTearDown(c.dispose);
      await c.savePassengerDetails(
        'p1',
        note: '승하차 안내가 필요합니다. ' * 30,
        defaultMorningMinute: 510,
      );
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
      expect(find.textContaining('1. 어르신 A'), findsWidgets);
      expect(find.textContaining('08:30'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PassengerDetailsDialog(passenger: c.passenger('p1')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('default-appointment-picker')));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      expect(find.text('약속 시간 선택'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RouteTimeline(
                controller: c,
                route: c.draft.routes.first,
                collapseNotes: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(('승하차 안내가 필요합니다. ' * 30).trim()), findsOneWidget);
      expect(find.text('특이사항 보기'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
