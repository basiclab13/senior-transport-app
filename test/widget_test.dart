import 'support/fixtures.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';

void main() {
  const admin = AppUser(uid: 'fictional-admin', role: UserRole.admin);
  const staff = AppUser(
    uid: 'fictional-staff',
    role: UserRole.staff,
    staffId: 's1',
  );

  testWidgets('관리자 결석 처리와 확정 검토 유지', (tester) async {
    final c = fixtureController(
      user: admin,
      initialDate: DateTime(2026, 11, 12),
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
    await tester.tap(find.byKey(const ValueKey('staff-s1')));
    await tester.pumpAndSettle();
    final absent = find.byKey(const ValueKey('absent-p2'));
    await tester.ensureVisible(absent);
    await tester.pumpAndSettle();
    await tester.tap(absent);
    await tester.pumpAndSettle();
    expect(c.draft.routes.first.passengerIds, ['p1', 'p3']);
    final confirm = find.byKey(const Key('confirm-schedule'));
    await tester.scrollUntilVisible(
      confirm,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(c.confirmed, isNull);
    await tester.tap(find.byKey(const Key('approve-confirm')));
    await tester.pumpAndSettle();
    expect(c.confirmed?.version, 1);
    expect(find.text('임시 역할 전환'), findsNothing);
  });

  testWidgets('모바일 직원 화면은 본인 계정으로 열리고 편집을 숨긴다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var loggedOut = false;
    final staffController = fixtureController(user: staff);
    addTearDown(staffController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          user: staff,
          controller: staffController,
          onSignOut: () async {
            loggedOut = true;
          },
        ),
      ),
    );
    expect(find.text('직원 화면'), findsOneWidget);
    expect(find.text('아직 확정된 일정이 없습니다.'), findsOneWidget);
    expect(find.byKey(const Key('confirm-schedule')), findsNothing);
    expect(find.text('시연할 직원'), findsNothing);
    await tester.tap(find.byKey(const Key('logout')));
    expect(loggedOut, isTrue);
    expect(tester.takeException(), isNull);
  });
}
