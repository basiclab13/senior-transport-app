import 'support/fixtures.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';

void main() {
  const admin = AppUser(uid: 'fictional-admin', role: UserRole.admin);
  late ScheduleController c;
  setUp(
    () =>
        c = fixtureController(user: admin, initialDate: DateTime(2026, 11, 13)),
  );
  tearDown(() => c.dispose());
  Future<void> open(WidgetTester tester, {bool wide = false}) async {
    tester.view.physicalSize = wide
        ? const Size(1280, 900)
        : const Size(390, 844);
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

  testWidgets('PC 직원 목록과 한 직원의 상세를 나란히 표시한다', (tester) async {
    await open(tester, wide: true);
    final list = find.byKey(const Key('staff-list'));
    final detail = find.byKey(const ValueKey('staff-detail-s1'));
    expect(tester.getRect(list).right, lessThan(tester.getRect(detail).left));
    expect(find.text('햇살 A코스'), findsOneWidget);
    expect(find.text('나무 B코스'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('staff-s2')));
    await tester.pumpAndSettle();
    expect(find.text('나무 B코스'), findsOneWidget);
    expect(find.text('햇살 A코스'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('모바일은 목록과 상세를 분리하고 검색을 유지한다', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('staff-detail-s1')), findsNothing);
    await tester.enterText(find.byKey(const Key('staff-search')), '김다정');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('staff-s2')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('staff-s1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('staff-list')), findsNothing);
    expect(find.byKey(const ValueKey('staff-detail-s1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('back-to-staff')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('staff-search')))
          .controller!
          .text,
      '김다정',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('근무 불가와 미배정 필터를 함께 적용한다', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('work-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('근무 불가').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assignment-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('미배정').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('staff-s3')), findsOneWidget);
    expect(find.byKey(const ValueKey('staff-s1')), findsNothing);
    expect(find.byKey(const ValueKey('staff-s2')), findsNothing);
  });

  testWidgets('관리자가 예상 방문 시각을 입력하고 수정한다', (tester) async {
    await open(tester, wide: true);
    await tester.ensureVisible(find.byKey(const ValueKey('visit-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('visit-p1')));
    await tester.pumpAndSettle();
    final edit = find.byKey(const ValueKey('time-p1'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('estimated-time-0')),
      '25:00',
    );
    await tester.tap(find.byKey(const Key('save-estimated-time')));
    await tester.pumpAndSettle();
    expect(find.textContaining('00:00~23:59'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('estimated-time-0')),
      '08:10',
    );
    await tester.tap(find.byKey(const Key('save-estimated-time')));
    await tester.pumpAndSettle();
    expect(c.draft.routes.first.estimatedVisitMinutes['p1'], 490);
    expect(find.textContaining('약속 시간 08:10'), findsOneWidget);
  });

  testWidgets('이용자 재배정 후 여러 직원의 변경사항을 함께 검토하고 확정한다', (tester) async {
    c.markAbsent('p2');
    await open(tester, wide: true);
    final add = find.byKey(const ValueKey('add-morning-a'));
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-person-p4')));
    await tester.pumpAndSettle();
    expect(c.routesForStaff('s1').single.passengerIds, ['p1', 'p3', 'p4']);
    expect(c.routesForStaff('s2').single.passengerIds, ['p5']);

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-schedule')));
    await tester.pumpAndSettle();
    expect(c.confirmed, isNull);
    expect(find.text('햇살 A코스 · 김다정'), findsOneWidget);
    expect(find.text('나무 B코스 · 이온유'), findsOneWidget);
    await tester.tap(find.byKey(const Key('approve-confirm')));
    await tester.pumpAndSettle();
    expect(c.confirmed!.routes.first.passengerIds, ['p1', 'p3', 'p4']);
    expect(c.confirmed!.routes.last.passengerIds, ['p5']);
  });

  testWidgets('작은 모바일에서도 직원 목록과 확정 버튼이 넘치지 않는다', (tester) async {
    await open(tester);
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('staff-search')), findsOneWidget);
    expect(find.byKey(const Key('confirm-schedule')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
