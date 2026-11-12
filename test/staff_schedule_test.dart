import 'support/fixtures.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';

void main() {
  const admin = AppUser(uid: 'fictional-admin', role: UserRole.admin);
  const staff = AppUser(
    uid: 'fictional-staff',
    role: UserRole.staff,
    staffId: 's1',
  );
  late ScheduleController c;
  setUp(() {
    final source = fixtureController(
      user: admin,
      initialDate: DateTime(2026, 11, 12),
    );
    source.setOperatingWindow('morning-a', 480, 540);
    source.setVisitMinute('morning-a', 'p1', 490);
    source.setVisitMinute('morning-a', 'p2', 500);
    source.setVisitMinute('morning-a', 'p3', 510);
    source.confirm();
    final morning = source.confirmed!;
    source.selectPeriod(TransportPeriod.afternoon);
    source.setOperatingWindow('afternoon-a', 960, 1020);
    source.setVisitMinute('afternoon-a', 'p3', 970);
    source.setVisitMinute('afternoon-a', 'p1', 980);
    source.setVisitMinute('afternoon-a', 'p2', 990);
    source.confirm();
    c = fixtureController(
      user: staff,
      initialDate: DateTime(2026, 11, 12),
      initialConfirmed: [morning, source.confirmed!],
    );
    source.dispose();
  });
  tearDown(() => c.dispose());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          user: staff,
          controller: c,
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('직원은 본인 확정 일정의 예상 시각·위치·차량과 방문 순서만 확인한다', (tester) async {
    await open(tester);
    final first = find.byKey(const ValueKey('timeline-p1'));
    await tester.ensureVisible(first);
    await tester.pumpAndSettle();
    expect(find.text('담당 차량 · 햇살 1호'), findsOneWidget);
    expect(find.text('예상 운행 08:00–09:00 · 60분'), findsOneWidget);
    expect(find.text('예상 08:10'), findsOneWidget);
    expect(find.text('가상마을 햇살길 1'), findsOneWidget);
    expect(
      tester.getTopLeft(first).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('timeline-p2'))).dy),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('timeline-p2'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('timeline-p3'))).dy),
    );
    expect(find.text('나무 B코스'), findsNothing);
    expect(find.text('가상 어르신 D'), findsNothing);
    expect(find.byKey(const Key('confirm-schedule')), findsNothing);
    expect(find.byKey(const ValueKey('absent-p1')), findsNothing);
    expect(find.byKey(const Key('staff-search')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('오전·오후 전환과 다른 날짜 조회에서 확정본을 구분한다', (tester) async {
    await open(tester);
    expect(find.textContaining('실제 운행 시각과 다를 수'), findsOneWidget);
    await tester.tap(find.text('오후'));
    await tester.pumpAndSettle();
    expect(find.text('예상 운행 16:00–17:00 · 60분'), findsOneWidget);
    expect(find.text('예상 16:10'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('timeline-p3'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('timeline-p1'))).dy),
    );
    await tester.tap(find.byTooltip('다음 날짜'));
    await tester.pumpAndSettle();
    expect(find.text('2026-11-13'), findsOneWidget);
    expect(find.text('아직 확정된 일정이 없습니다.'), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-p3')), findsNothing);
    await tester.tap(find.byTooltip('이전 날짜'));
    await tester.pumpAndSettle();
    expect(find.text('예상 16:10'), findsOneWidget);
  });

  testWidgets('출퇴근 사진 인증 안내로 이동하며 저장된 것처럼 표시하지 않는다', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('attendance')));
    await tester.pumpAndSettle();
    expect(find.text('사진 인증 기능 준비 중'), findsOneWidget);
    expect(find.textContaining('출퇴근 인증이 기록되지 않습니다'), findsOneWidget);
    expect(find.textContaining('김다정 · 2026-11-12 · 오전'), findsOneWidget);
    await tester.tap(find.text('내 일정으로 돌아가기'));
    await tester.pumpAndSettle();
    expect(find.text('직원 화면'), findsOneWidget);
  });
}
