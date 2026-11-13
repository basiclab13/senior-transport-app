import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/attendance_record.dart';
import 'package:senior_transport_app/models/staff_absence.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/screens/staff_schedule_view.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';

import 'attendance_test.dart'
    show PhotoSchedules, demoPhoto, staffUser, adminUser;
import 'support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('CAPTURE_STAFF');
  late PhotoSchedules repo;
  late ScheduleController c;
  final boundary = GlobalKey();
  setUpAll(() async {
    if (capture && Platform.isWindows) {
      for (final entry in {
        'StaffDemo': 'C:/Windows/Fonts/malgun.ttf',
        'MaterialIcons': 'build/web/assets/fonts/MaterialIcons-Regular.otf',
      }.entries) {
        await (FontLoader(entry.key)..addFont(
              Future.value(
                ByteData.sublistView(await File(entry.value).readAsBytes()),
              ),
            ))
            .load();
      }
    }
  });
  setUp(() async {
    repo = PhotoSchedules();
    final source = fixtureController(user: adminUser);
    source.setOperatingWindow('morning-a', 480, 540);
    source.setVisitMinute('morning-a', 'p1', 490);
    source.setVisitMinute('morning-a', 'p2', 500);
    source.setVisitMinute('morning-a', 'p3', 510);
    source.confirm();
    repo.snapshots['2026-11-12_morning'] = source.confirmed!;
    source.dispose();
    c = ScheduleController.remote(
      user: staffUser,
      repository: repo,
      clock: fixtureClock,
    );
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() async {
    c.dispose();
    await repo.changes.close();
    await repo.attendance.updates.close();
  });
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    bool interactive = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: ThemeData(fontFamily: capture ? 'StaffDemo' : null),
          home: interactive
              ? Scaffold(
                  body: ListenableBuilder(
                    listenable: c,
                    builder: (_, _) => StaffScheduleView(
                      controller: c,
                      photoPicker: () async => demoPhoto,
                    ),
                  ),
                )
              : ScheduleScreen(
                  user: staffUser,
                  controller: c,
                  onSignOut: () async {},
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, String kind) async {
    final button = find.byKey(Key('register-work-$kind'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-work-photo')));
    await tester.pumpAndSettle();
  }

  Future<void> photo(WorkPhotoKind kind, {String route = 'morning-a'}) async =>
      repo.attendance.register(
        user: staffUser,
        date: '2026-11-12',
        period: TransportPeriod.morning,
        routeId: route,
        kind: kind,
        photo: demoPhoto,
      );
  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!capture) return;
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('.local-tools/staff-ux').createSync(recursive: true);
      File('.local-tools/staff-ux/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(1280, 900),
  ]) {
    testWidgets(
      '${size.width}px: course and primary photo action are visible without scrolling',
      (tester) async {
        await open(tester, size: size);
        expect(find.text('햇살 A코스'), findsOneWidget);
        expect(find.text('이용자 3명'), findsOneWidget);
        expect(find.text('담당 차량 · 햇살 1호'), findsOneWidget);
        final action = find.byKey(const Key('register-work-start'));
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.getBottomRight(action).dy, lessThan(size.height));
        expect(find.byKey(const Key('register-work-end')), findsNothing);
        expect(find.text('오늘 · 11월 12일 (목) · 오전'), findsOneWidget);
        expect(find.textContaining('v1'), findsNothing);
        expect(find.text('가상 어르신 D'), findsNothing);
        await screenshot(tester, 'staff-${size.width.toInt()}');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'inline start → end → completed; photos expand without page navigation',
    (tester) async {
      await open(tester, interactive: true);
      await save(tester, 'start');
      expect(find.byKey(const Key('register-work-start')), findsNothing);
      expect(find.byKey(const Key('register-work-end')), findsOneWidget);
      expect(find.text('업무 시작 사진 등록 · 09:15:00'), findsOneWidget);
      await save(tester, 'end');
      expect(repo.attendance.records.length, 2);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('업무 시작·종료 사진을 모두 등록했습니다.'), findsOneWidget);
      await tester.tap(find.text('등록한 사진 보기'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.byType(BackButton), findsNothing);
    },
  );
  testWidgets(
    'notes are collapsed while order, expected time and address stay visible',
    (tester) async {
      await open(tester);
      final visit = find.byKey(const ValueKey('timeline-p1'));
      await tester.ensureVisible(visit);
      await tester.pumpAndSettle();
      expect(find.text('예상 08:10'), findsOneWidget);
      expect(find.text('가상마을 햇살길 1'), findsOneWidget);
      expect(find.text('승하차 시 천천히 안내'), findsNothing);
      await tester.tap(find.text('가상 어르신 A'));
      await tester.pumpAndSettle();
      expect(find.text('승하차 시 천천히 안내'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'absence hides operable course and upload without inventing handoff completion',
    (tester) async {
      c.absences = {
        's1': StaffAbsence(
          staffId: 's1',
          periods: {TransportPeriod.morning},
          version: 1,
        ),
      };
      await open(tester);
      expect(find.textContaining('결근으로 등록되어 있습니다'), findsOneWidget);
      expect(find.text('햇살 A코스'), findsNothing);
      expect(find.byKey(const Key('register-work-start')), findsNothing);
      expect(find.textContaining('인계 완료'), findsNothing);
    },
  );
  testWidgets(
    'no projection is described as unconfirmed, never a completed handoff',
    (tester) async {
      c.selectDate(DateTime(2026, 11, 13));
      await open(tester);
      expect(find.text('아직 확정된 일정이 없습니다. 관리자에게 확인해 주세요.'), findsOneWidget);
      expect(find.byKey(const Key('register-work-start')), findsNothing);
      expect(find.textContaining('인계 완료'), findsNothing);
    },
  );
  testWidgets(
    'date/period switches reset primary photo status and preserve selected date',
    (tester) async {
      await photo(WorkPhotoKind.start);
      await open(tester);
      expect(find.byKey(const Key('register-work-end')), findsOneWidget);
      await tester.tap(find.text('오후'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('register-work-end')), findsNothing);
      expect(find.text('업무 시작 사진 등록 · 09:15:00'), findsNothing);
      await tester.tap(find.text('오전'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('register-work-end')), findsOneWidget);
      expect(dateKey(c.selectedDate), '2026-11-12');
    },
  );
  testWidgets(
    'an older different course start never enables the current course end',
    (tester) async {
      await photo(WorkPhotoKind.start, route: 'previous-course');
      await open(tester);
      expect(find.byKey(const Key('register-work-start')), findsOneWidget);
      expect(find.byKey(const Key('register-work-end')), findsNothing);
    },
  );
  testWidgets('failed or stale inline registration never changes records', (
    tester,
  ) async {
    repo.attendance.fail = true;
    await open(tester, interactive: true);
    await save(tester, 'start');
    expect(repo.attendance.records, isEmpty);
    expect(find.textContaining('사진을 등록하지 못했습니다'), findsOneWidget);
    repo.attendance.fail = false;
    await tester.tap(find.byKey(const Key('register-work-start')));
    await tester.pumpAndSettle();
    c.selectPeriod(TransportPeriod.afternoon);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-work-photo')));
    await tester.pumpAndSettle();
    expect(repo.attendance.records, isEmpty);
  });
}
