import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/staff_absence.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';
import 'package:senior_transport_app/utils/admin_schedule_status.dart';

import 'support/fixtures.dart';

void main() {
  const admin = AppUser(uid: 'fictional-admin-polish', role: UserRole.admin);
  late ScheduleController c;
  setUp(() => c = fixtureController(user: admin));
  tearDown(() => c.dispose());
  Future<void> open(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 844);
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

  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    testWidgets(
      'initial view/date/period never implies edits at $width; compact footer and capped search',
      (tester) async {
        await open(tester, width);
        expect(find.text('미확정 일정'), findsOneWidget);
        expect(find.text('변경사항 있음'), findsNothing);
        expect(find.text('확정을 막는 문제는 없습니다.'), findsNothing);
        expect(find.text('확정 전 확인 완료'), findsNothing);
        expect(
          tester.getSize(find.byKey(const Key('dashboard-search'))).width,
          lessThanOrEqualTo(480),
        );
        final button = find.byKey(const Key('confirm-schedule'));
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.getRect(button).bottom, lessThanOrEqualTo(844));
        c.selectDate(DateTime(2026, 11, 13));
        c.selectPeriod(TransportPeriod.afternoon);
        await tester.pumpAndSettle();
        expect(find.text('미확정 일정'), findsOneWidget);
        expect(hasScheduleContentChanges(c), false);
        expect(c.hasPendingChanges, false);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('missing times and reordered visits do not block confirmation', (
    tester,
  ) async {
    await open(tester, 1280);
    expect(c.confirmationErrors, isEmpty);
    expect(find.byKey(const Key('dashboard-attention')), findsNothing);
    expect(find.textContaining('확정 가능'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('confirm-schedule')))
          .onPressed,
      isNotNull,
    );
    c.reorder('morning-a', 0, 1);
    await tester.pumpAndSettle();
    expect(c.confirmationErrors, isEmpty);
    expect(find.textContaining('확정 불가'), findsNothing);
    expect(find.textContaining('확정 가능'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('confirm-schedule')))
          .onPressed,
      isNotNull,
    );
    await tester.pumpAndSettle();
    expect(c.confirmationErrors, isEmpty);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('confirm-schedule')))
          .onPressed,
      isNotNull,
    );
  });
  testWidgets(
    'confirmed/no-op edits remain quiet; real change needs explicit confirmation',
    (tester) async {
      c.confirm();
      await open(tester, 1280);
      expect(find.text('확정된 일정'), findsOneWidget);
      c.assign('morning-a', staffId: c.draft.routes.first.staffId);
      await tester.pumpAndSettle();
      expect(c.hasPendingChanges, true);
      expect(hasScheduleContentChanges(c), false);
      expect(find.byKey(const Key('confirmed-no-changes')), findsOneWidget);
      expect(
        tester.widget(find.byKey(const Key('confirm-schedule'))),
        isA<TextButton>(),
      );
      c.markAbsent('p1');
      await tester.pumpAndSettle();
      expect(find.text('변경사항 있음'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-schedule')));
      await tester.pumpAndSettle();
      expect(c.confirmed!.version, 1);
      await tester.tap(find.byKey(const Key('approve-confirm')));
      await tester.pumpAndSettle();
      expect(c.confirmed!.version, 2);
      expect(find.text('확정된 일정'), findsOneWidget);
    },
  );
  testWidgets(
    'absence and course handoff retain blocking/review rules and consistent status',
    (tester) async {
      c.confirm();
      c.absences = {
        's1': StaffAbsence(
          staffId: 's1',
          periods: {TransportPeriod.morning},
          version: 1,
        ),
      };
      await open(tester, 1280);
      expect(find.textContaining('다른 직원 배정 필요'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-schedule')))
            .onPressed,
        isNull,
      );
      c.reassignAbsentCourse('morning-a', 's3');
      await tester.pumpAndSettle();
      expect(find.text('변경사항 있음'), findsOneWidget);
      expect(c.confirmationErrors, isEmpty);
      await tester.pumpAndSettle();
      expect(c.confirmationErrors, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-schedule')))
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'concurrent edit conflict is a blocker, not a zero-error confirmation',
    (tester) async {
      c.confirm();
      c.conflict = true;
      await open(tester, 1280);
      expect(c.confirmationErrors, isEmpty);
      expect(adminBlockingMessages(c), hasLength(1));
      expect(find.text('다른 관리자의 변경 확인 필요'), findsOneWidget);
      expect(find.textContaining('확정 불가'), findsWidgets);
      expect(find.textContaining('확정 가능'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-schedule')))
            .onPressed,
        isNull,
      );
    },
  );
}
