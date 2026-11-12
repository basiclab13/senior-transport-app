import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';

void main() {
  testWidgets('관리자 결석 처리, 확정 검토, 직원 최신 일정 조회', (tester) async {
    final c = ScheduleController(initialDate: DateTime(2026, 11, 12));
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(home: ScheduleScreen(controller: c)));
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
    expect(find.text('확정하여 공유'), findsOneWidget);
    await tester.tap(find.byKey(const Key('approve-confirm')));
    await tester.pumpAndSettle();
    expect(c.confirmed?.version, 1);
    await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('직원'));
    await tester.pumpAndSettle();
    expect(find.text('가상 어르신 B'), findsNothing);
    expect(find.text('나무 B코스'), findsNothing);
    expect(find.byKey(const Key('confirm-schedule')), findsNothing);
    expect(find.text('최신 확정 일정 · v1'), findsOneWidget);
  });

  testWidgets('모바일 화면과 직원 미확정 안내', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = ScheduleController(initialDate: DateTime(2026, 11, 12));
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(home: ScheduleScreen(controller: c)));
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    c.selectRole(DemoRole.staff);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(find.text('아직 확정된 일정이 없습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
