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
    expect(find.text('운행 참고 08:00–09:00 · 60분'), findsNothing);
    expect(find.text('약속 시간 08:10'), findsOneWidget);
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
    expect(find.text('어르신 D'), findsNothing);
    expect(find.byKey(const Key('confirm-schedule')), findsNothing);
    expect(find.byKey(const ValueKey('absent-p1')), findsNothing);
    expect(find.byKey(const Key('staff-search')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('오전·오후 전환과 다른 날짜 조회에서 확정본을 구분한다', (tester) async {
    await open(tester);
    expect(find.textContaining('실제 운행 시각과 다를 수'), findsNothing);
    await tester.tap(find.text('오후'));
    await tester.pumpAndSettle();
    expect(find.text('운행 참고 16:00–17:00 · 60분'), findsNothing);
    expect(find.textContaining('기존 저장 시각 16:10'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('timeline-p3')));
    await tester.pumpAndSettle();
    expect(find.text('기존 저장 시각 16:10 · 직접 입력'), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('timeline-p3'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('timeline-p1'))).dy),
    );
    await tester.tap(find.byTooltip('다음 날짜'));
    await tester.pumpAndSettle();
    expect(find.text('내일 · 11월 13일 (금) · 오후'), findsOneWidget);
    expect(find.text('아직 확정된 일정이 없습니다. 관리자에게 확인해 주세요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-p3')), findsNothing);
    await tester.tap(find.byTooltip('이전 날짜'));
    await tester.pumpAndSettle();
    expect(find.textContaining('기존 저장 시각 16:10'), findsNothing);
  });

  testWidgets('첫 화면의 미연결 사진 안내는 저장된 것처럼 표시하지 않는다', (tester) async {
    await open(tester);
    expect(find.text('사진 등록을 사용할 수 없습니다. 관리자에게 문의해 주세요.'), findsOneWidget);
    expect(find.byKey(const Key('register-work-start')), findsNothing);
    expect(find.text('내 송영 일정'), findsOneWidget);
  });
}
