import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/schedule_catalog.dart';
import 'package:senior_transport_app/models/staff_absence.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';

import 'admin_overview_test.dart' show operatingCatalog;
import 'attendance_test.dart' show PhotoSchedules;
import 'support/fixtures.dart' show fixtureClock, openStaffInfo;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('CAPTURE_DASHBOARD');
  const admin = AppUser(uid: 'fictional-dashboard-admin', role: UserRole.admin);
  late ScheduleController c;
  setUpAll(() async {
    if (capture && Platform.isWindows) {
      final loader = FontLoader('DashboardDemo')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File('C:/Windows/Fonts/malgun.ttf').readAsBytes(),
            ),
          ),
        );
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File('build/web/assets/fonts/MaterialIcons-Regular.otf')
                  .readAsBytes(),
            ),
          ),
        );
      await icons.load();
    }
  });
  setUp(
    () => c = ScheduleController(
      user: admin,
      catalog: operatingCatalog(),
      initialDate: DateTime(2026, 11, 16),
      clock: () => DateTime.utc(2026, 11, 16),
    ),
  );
  tearDown(() => c.dispose());
  final boundary = GlobalKey();
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1440, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: ThemeData(fontFamily: capture ? 'DashboardDemo' : null),
          home: ScheduleScreen(
            user: admin,
            controller: c,
            onSignOut: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!capture) return;
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('.local-tools/dashboard').createSync(recursive: true);
      File('.local-tools/dashboard/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'default PC home summarizes 20 staff / 80 passengers and leaves editing closed',
    (tester) async {
      await open(tester);
      expect(find.byKey(const Key('admin-dashboard')), findsOneWidget);
      expect(find.text('80명'), findsOneWidget);
      expect(find.text('20명'), findsOneWidget);
      expect(find.text('0건'), findsOneWidget);
      expect(find.byKey(const ValueKey('staff-detail-s1')), findsNothing);
      final table = tester.widget<Table>(
        find.byKey(const Key('dashboard-staff-table')),
      );
      expect(table.children.length, 21);
      expect(find.text('담당 코스 · 차량'), findsOneWidget);
      final first = find.byKey(const ValueKey('dashboard-staff-s1'));
      final second = find.byKey(const ValueKey('dashboard-staff-s2'));
      expect(tester.getTopLeft(first).dx, tester.getTopLeft(second).dx);
      expect(find.text('오늘 · 11월 16일 (월) · 오전'), findsOneWidget);
      expect(c.confirmed, isNull);
      expect(c.hasPendingChanges, isFalse);
      await screenshot(tester, 'pc-overview');
      final last = find.byKey(const ValueKey('dashboard-staff-s20'));
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      expect(last.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'passenger search uses actual reassignment and opens existing visit actions',
    (tester) async {
      c.movePassenger('p80', 'morning-19');
      await open(tester);
      await tester.enterText(
        find.byKey(const Key('dashboard-search')),
        '가상 이용자 80',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dashboard-staff-s19')), findsOneWidget);
      expect(find.byKey(const ValueKey('dashboard-staff-s20')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('dashboard-staff-s19')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('staff-detail-s19')), findsOneWidget);
      expect(find.byKey(const ValueKey('time-p80')), findsOneWidget);
      expect(c.confirmed, isNull);
    },
  );
  testWidgets(
    'absence, missing passengers and time review appear in priority order with correct destinations',
    (tester) async {
      final full = operatingCatalog();
      c.dispose();
      c = ScheduleController(
        user: admin,
        initialDate: DateTime(2026, 11, 16),
        catalog: ScheduleCatalog(
          version: full.version,
          staff: full.staff,
          vehicles: full.vehicles,
          passengers: full.passengers,
          baseRoutes: [
            for (final r in full.baseRoutes)
              BaseRoute(
                id: r.id,
                name: r.name,
                period: r.period,
                staffId: r.staffId,
                vehicleId: r.vehicleId,
                passengerIds: r.period == TransportPeriod.morning
                    ? r.passengerIds.where((id) => id != 'p80').toList()
                    : r.passengerIds,
              ),
          ],
        ),
      );
      c.catalog = full;
      c.absences = {
        's1': StaffAbsence(
          staffId: 's1',
          periods: {TransportPeriod.morning},
          version: 1,
        ),
      };
      c.reorder('morning-2', 0, 1);
      await open(tester);
      final absence = find.textContaining('다른 직원에게 코스를 넘겨주세요.');
      final missing = find.text('배정되지 않은 이용자 1명을 확인해 주세요.');
      final time = find.text('가상 2코스: 방문 시간을 확인해 주세요.');
      expect(
        tester.getTopLeft(absence).dy,
        lessThan(tester.getTopLeft(missing).dy),
      );
      expect(
        tester.getTopLeft(missing).dy,
        lessThan(tester.getTopLeft(time).dy),
      );
      expect(find.text('3건'), findsOneWidget);
      await screenshot(tester, 'pc-problems');
      await tester.tap(missing);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('staff-detail-s20')), findsOneWidget);
      await tester.tap(find.byKey(const Key('admin-overview')));
      await tester.pumpAndSettle();
      await tester.tap(time);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('staff-detail-s2')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-schedule')))
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'staff search opens course editor and can return to overview without discarding changes',
    (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const Key('dashboard-search')),
        '가상 직원 20',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dashboard-staff-s20')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('staff-detail-s20')), findsOneWidget);
      c.markAbsent('p80');
      await tester.pumpAndSettle();
      final draft = c.draft;
      await tester.tap(find.byKey(const Key('admin-overview')));
      await tester.pumpAndSettle();
      expect(c.draft, same(draft));
      expect(c.confirmed, isNull);
      expect(find.textContaining('결석 1명'), findsOneWidget);
    },
  );
  testWidgets('lookup failure never becomes a zero-problem dashboard', (
    tester,
  ) async {
    c.availabilityError = '결근 정보를 확인할 수 없습니다.';
    await open(tester);
    expect(find.byKey(const Key('dashboard-no-problems')), findsNothing);
    expect(find.byKey(const Key('dashboard-problem-count')), findsNothing);
    expect(find.byKey(const Key('confirm-schedule')), findsNothing);
    expect(find.text('다시 불러오기'), findsOneWidget);
  });
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'mobile $width: summary, searchable last employee, editor and return',
      (tester) async {
        await open(tester, size: Size(width, 844));
        expect(find.byKey(const Key('dashboard-staff-table')), findsNothing);
        await screenshot(tester, 'mobile-${width.toInt()}');
        final search = find.byKey(const Key('dashboard-search'));
        await tester.ensureVisible(search);
        await tester.enterText(search, '가상 직원 20');
        await tester.pumpAndSettle();
        final last = find.byKey(const ValueKey('dashboard-staff-s20'));
        expect(
          find.ancestor(of: last, matching: find.byType(Card)),
          findsOneWidget,
        );
        await tester.ensureVisible(last);
        await tester.tap(last);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('staff-detail-s20')), findsOneWidget);
        await tester.tap(find.byKey(const Key('admin-overview')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('admin-dashboard')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'selected date and period stay explicit; current schedule follows 19:00 policy',
    (tester) async {
      c.dispose();
      var now = DateTime.utc(2026, 11, 16, 9, 59);
      c = ScheduleController(
        user: admin,
        catalog: operatingCatalog(),
        clock: () => now,
      );
      await open(tester);
      expect(find.text('오늘 · 11월 16일 (월) · 오후'), findsOneWidget);
      c.selectDate(DateTime(2026, 11, 20));
      c.selectPeriod(TransportPeriod.morning);
      now = DateTime.utc(2026, 11, 16, 10);
      await tester.pumpAndSettle();
      expect(find.text('2026년 11월 20일 (금) · 오전'), findsOneWidget);
      await tester.tap(find.byKey(const Key('current-schedule')));
      await tester.pumpAndSettle();
      expect(find.text('내일 · 11월 17일 (화) · 오전'), findsOneWidget);
    },
  );

  testWidgets(
    'confirmed unchanged schedule is quiet; edits restore validation and final confirmation',
    (tester) async {
      c.confirm();
      await open(tester);
      expect(find.byKey(const Key('confirm-schedule')), findsNothing);
      expect(find.byKey(const Key('confirmed-no-changes')), findsOneWidget);
      await screenshot(tester, 'readability-confirmed-pc');
      c.markAbsent('p1');
      await tester.pumpAndSettle();
      final confirm = find.byKey(const Key('confirm-schedule'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      c.keepVisitTimes('morning-1');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(c.confirmed!.version, 1);
      await tester.tap(find.byKey(const Key('approve-confirm')));
      await tester.pumpAndSettle();
      expect(c.confirmed!.version, 2);
      expect(find.byKey(const Key('confirm-schedule')), findsNothing);
    },
  );
  testWidgets(
    'confirmed absence and save failure retain their blocking guidance',
    (tester) async {
      c.confirm();
      c.absences = {
        's1': StaffAbsence(
          staffId: 's1',
          periods: {TransportPeriod.morning},
          version: 1,
        ),
      };
      await open(tester);
      expect(find.byKey(const Key('confirmed-no-changes')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-schedule')))
            .onPressed,
        isNull,
      );
      c.absences = {};
      c.saveError = '연결을 확인한 뒤 다시 시도해 주세요.';
      await open(tester);
      expect(find.byKey(const Key('confirmed-no-changes')), findsNothing);
      expect(find.byKey(const Key('reload-schedule')), findsOneWidget);
    },
  );
  testWidgets(
    'staff photo actions stay in staff information; detail has no duplicate overview/search buttons',
    (tester) async {
      c.dispose();
      final repo = PhotoSchedules();
      c = ScheduleController.remote(
        user: admin,
        repository: repo,
        clock: fixtureClock,
      );
      await open(tester);
      await tester.tap(find.byKey(const Key('admin-editor')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-assignment-overview')), findsNothing);
      expect(find.byKey(const Key('open-passenger-search')), findsNothing);
      expect(find.byKey(const ValueKey('attendance-s1')), findsNothing);
      expect(find.byKey(const ValueKey('visit-p1')), findsOneWidget);
      await screenshot(tester, 'readability-detail-pc');
      await openStaffInfo(tester, 's1');
      final records = find.byKey(const ValueKey('attendance-s1'));
      await tester.ensureVisible(records);
      await tester.tap(records);
      await tester.pumpAndSettle();
      expect(find.text('김다정 업무 사진 기록'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await repo.changes.close();
      await repo.attendance.updates.close();
    },
  );
}
