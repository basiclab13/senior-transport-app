import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/schedule_codec.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';
import 'package:senior_transport_app/utils/visit_time_wording.dart';
import 'package:senior_transport_app/widgets/route_timeline.dart';

import 'support/fixtures.dart';

void main() {
  const admin = AppUser(uid: 'fictional-time-admin', role: UserRole.admin);
  const staff = AppUser(
    uid: 'fictional-time-staff',
    role: UserRole.staff,
    staffId: 's1',
  );
  late ScheduleController c;
  setUp(() => c = fixtureController(user: admin));
  tearDown(() => c.dispose());

  test('manual input, calculated reference, legacy unknown and missing stay distinct without changing sources', () {
    final route = c.draft.routes.first.copyWith(
      estimatedVisitMinutes: {'p1': 490, 'p2': 500, 'p3': 510},
      estimatedVisitSources: {'p1': 'manual', 'p2': 'fixedInterval'},
    );
    expect(visitTimeText(TransportPeriod.morning, route, 'p1'), '약속 시간 08:10');
    expect(visitTimeText(TransportPeriod.morning, route, 'p2'), isNull);
    expect(visitTimeText(TransportPeriod.morning, route, 'p3'), isNull);
    expect(visitTimeText(TransportPeriod.morning, route, 'missing'), isNull);
    expect(visitTimeText(TransportPeriod.afternoon, route, 'p1'), isNull);
    expect(route.estimatedVisitSources.containsKey('p3'), false);
    expect(route.isManualEstimate('p3'), false);
  });
  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    testWidgets('AM/PM times and stored values remain honest at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final route = c.draft.routes.first.copyWith(
        estimatedVisitMinutes: {'p1': 490, 'p2': 500, 'p3': 510},
        estimatedVisitSources: {'p1': 'manual', 'p2': 'fixedInterval'},
      );
      final before = routeToJson(route);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RouteTimeline(
                controller: c,
                route: route,
                collapseNotes: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('약속 시간 08:10'), findsOneWidget);
      expect(find.textContaining('계산 참고 08:20'), findsNothing);
      expect(find.textContaining('약속 여부 확인'), findsNothing);
      c.selectPeriod(TransportPeriod.afternoon);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RouteTimeline(
                key: const Key('pm'),
                controller: c,
                route: route,
                collapseNotes: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('약속 시간'), findsNothing);
      expect(find.textContaining('미입력'), findsNothing);
      expect(find.textContaining('기존 저장 시각'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('timeline-p1')));
      await tester.pumpAndSettle();
      expect(find.text('기존 저장 시각 08:10 · 직접 입력'), findsNothing);
      expect(routeToJson(route), before);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'admin/staff headers are single and date/period remain visible at $width',
      (tester) async {
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
        expect(find.text('송영 현황'), findsOneWidget);
        expect(find.textContaining('오늘 · 11월 12일'), findsOneWidget);
        c.selectPeriod(TransportPeriod.afternoon);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dashboard-attention')), findsNothing);
        final viewer = fixtureController(user: staff);
        addTearDown(viewer.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: ScheduleScreen(
              key: const Key('staff'),
              user: staff,
              controller: viewer,
              onSignOut: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('내 송영 일정'), findsOneWidget);
        expect(find.text('내 방문 순서와 업무 사진을 확인합니다.'), findsNothing);
        expect(find.text('예상 방문 시간은 실제 운행 시각과 다를 수 있습니다.'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
