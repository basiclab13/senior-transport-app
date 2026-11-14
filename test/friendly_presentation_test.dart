import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/data/emulator_display_names.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/ai_schedule_suggestion.dart';
import 'package:senior_transport_app/models/schedule_catalog.dart';
import 'package:senior_transport_app/models/schedule_changes.dart';
import 'package:senior_transport_app/models/schedule_codec.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';
import 'package:senior_transport_app/widgets/ai_schedule_suggestion_dialog.dart';
import 'package:senior_transport_app/widgets/schedule_change_review.dart';
import 'package:senior_transport_app/widgets/course_change_details.dart';

import 'admin_overview_test.dart' show operatingCatalog;
import 'support/fixtures.dart' show fixtureClock;

ScheduleCatalog legacyCatalog() {
  final c = operatingCatalog();
  return ScheduleCatalog(
    version: 'operations-20x80-v1',
    staff: c.staff,
    passengers: c.passengers,
    vehicles: c.vehicles,
    baseRoutes: c.baseRoutes,
  );
}

ScheduleCatalog friendly(ScheduleCatalog c) => emulatorDisplayCatalog(
  c,
  enabled: true,
  projectId: 'demo-senior-transport',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('CAPTURE_FRIENDLY');
  setUpAll(() async {
    if (capture && Platform.isWindows) {
      for (final entry in {
        'FriendlyDemo': 'C:/Windows/Fonts/malgun.ttf',
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
  test('20/80 aliases preserve every ID, account mapping, availability, route and schedule payload', () {
    final old = legacyCatalog(), next = friendly(legacyCatalog());
    expect(next.staff.length, 20);
    expect(next.passengers.length, 80);
    expect(next.staff.map((s) => s.name).toSet().length, 20);
    expect(next.passengers.map((p) => p.name).toSet().length, 80);
    expect(next.staff.map((s) => s.id), old.staff.map((s) => s.id));
    expect(next.passengers.map((p) => p.id), old.passengers.map((p) => p.id));
    for (var i = 0; i < 20; i++) {
      expect(next.staff[i].active, old.staff[i].active);
      expect(
        next.staff[i].unavailableWeekdays,
        old.staff[i].unavailableWeekdays,
      );
    }
    for (var i = 0; i < 80; i++) {
      expect(next.passengers[i].address, old.passengers[i].address);
      expect(next.passengers[i].note, old.passengers[i].note);
      expect(next.passengers[i].name, matches(RegExp(r'^[가-힣]{3}$')));
    }
    expect(old.staff.first.name, '가상 직원 01');
    expect(next.staff.first.name, '김다정');
    final c = ScheduleController(
      user: const AppUser(uid: 'a', role: UserRole.admin),
      catalog: old,
      clock: fixtureClock,
    );
    final payload = jsonEncode(scheduleToJson(c.draft));
    c.catalog = friendly(old);
    expect(jsonEncode(scheduleToJson(c.draft)), payload);
    expect(
      next.baseRoutes.map((r) => r.staffId),
      old.baseRoutes.map((r) => r.staffId),
    );
    c.dispose();
  });
  test('production and other fixture versions retain original names; staff projection uses the same aliases', () {
    final old = legacyCatalog();
    expect(
      emulatorDisplayCatalog(
        old,
        enabled: false,
        projectId: 'demo-senior-transport',
      ),
      same(old),
    );
    expect(
      emulatorDisplayCatalog(
        old,
        enabled: true,
        projectId: 'senior-transport-app',
      ),
      same(old),
    );
    final other = operatingCatalog();
    expect(friendly(other), same(other));
    final projection = ScheduleCatalog(
      version: old.version,
      staff: [old.staff.last],
      passengers: [old.passengers.last],
      vehicles: [],
      baseRoutes: [],
    );
    expect(
      friendly(projection).staff.single.name,
      friendly(old).staff.last.name,
    );
    expect(
      friendly(projection).passengers.single.name,
      friendly(old).passengers.last.name,
    );
  });
  test('legacy serialized catalog remains unchanged; its display aliases are stable across repeated loads', () {
    final raw = <String, dynamic>{
      'staff': [
        {
          'id': 's20',
          'name': '가상 직원 20',
          'active': true,
          'unavailableWeekdays': [5],
        },
      ],
      'passengers': [
        {'id': 'p80', 'name': '가상 이용자 80', 'address': '가상 주소', 'note': '테스트'},
      ],
      'vehicles': [],
      'baseRoutes': [],
    };
    final original = jsonEncode(raw);
    final a = friendly(ScheduleCatalog.fromJson('operations-20x80-v1', raw));
    final b = friendly(ScheduleCatalog.fromJson('operations-20x80-v1', raw));
    expect(jsonEncode(raw), original);
    expect(a.staff.single.name, b.staff.single.name);
    expect(a.passengers.single.name, '임종수');
    expect(a.staff.single.unavailableWeekdays, {5});
  });
  test('a transfer belongs to both courses but is counted once in the type summary', () {
    final c = ScheduleController(
      user: const AppUser(uid: 'a', role: UserRole.admin),
      catalog: friendly(legacyCatalog()),
      clock: fixtureClock,
    );
    final before = c.draft;
    c.movePassenger('p1', 'morning-2');
    final changes = ScheduleChanges.compare(before, c.draft, c.catalog);
    final transfer = changes.items
        .where((i) => i.kind == ScheduleChangeKind.assignment)
        .single;
    expect(transfer.routeIds, {'morning-1', 'morning-2'});
    expect(changedCourseIds(changes, c.draft), {'morning-1', 'morning-2'});
    c.dispose();
  });
  final boundary = GlobalKey();
  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!capture) return;
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('.local-tools/friendly-ui').createSync(recursive: true);
      File('.local-tools/friendly-ui/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      '$width AI: effects and order comparison first; details hidden, no draft mutation',
      (tester) async {
        final c = ScheduleController(
          user: const AppUser(uid: 'a', role: UserRole.admin),
          catalog: friendly(legacyCatalog()),
          clock: fixtureClock,
        );
        addTearDown(c.dispose);
        final original = c.draft;
        final suggestion = AiScheduleSuggestion.fromJson(
          {
            'date': '2026-11-12',
            'period': 'morning',
            'catalogVersion': c.catalog.version,
            'expectedVersion': 0,
            'routes': [
              for (final r in original.routes)
                {
                  'baseRouteId': r.baseRouteId,
                  'staffId': r.staffId,
                  'passengerIds': r.baseRouteId == 'morning-1'
                      ? r.passengerIds.reversed.toList()
                      : r.passengerIds,
                },
            ],
            'reasons': ['접힌 추천 근거'],
            'warnings': [],
            'distanceComparison': {
              'method': 'fictional-euclidean-round-trip-v1',
              'beforeKm': 10,
              'afterKm': 8,
            },
          },
          origin: original,
          catalog: c.catalog,
          confirmed: null,
          absenceRevision: c.absenceRevisionKey,
          generation: 0,
        );
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: ThemeData(fontFamily: capture ? 'FriendlyDemo' : null),
              home: Scaffold(
                body: AiScheduleSuggestionDialog(
                  controller: c,
                  suggestion: suggestion,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('접힌 추천 근거'), findsNothing);
        expect(find.byKey(const Key('ai-distance-limit')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('course-review-morning-1')));
        await tester.pumpAndSettle();
        expect(find.text('기존 순서'), findsOneWidget);
        expect(find.text('추천 순서'), findsOneWidget);
        expect(find.text('1코스 · 김다정'), findsOneWidget);
        expect(c.draft, same(original));
        await screenshot(tester, 'ai-${width.toInt()}');
        final more = find.byKey(const Key('ai-more-details'));
        await tester.scrollUntilVisible(
          more,
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(more);
        await tester.pumpAndSettle();
        expect(find.text('접힌 추천 근거'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '$width confirmation: summary first and per-course details folded',
      (tester) async {
        final c = ScheduleController(
          user: const AppUser(uid: 'a', role: UserRole.admin),
          catalog: friendly(legacyCatalog()),
          clock: fixtureClock,
        );
        addTearDown(c.dispose);
        final before = c.draft;
        c.movePassenger('p1', 'morning-2');
        final changes = ScheduleChanges.compare(before, c.draft, c.catalog);
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: ThemeData(fontFamily: capture ? 'FriendlyDemo' : null),
              home: Scaffold(
                appBar: AppBar(title: const Text('송영도우미 · 테스트 데이터')),
                body: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: ScheduleChangeReview(
                      catalog: c.catalog,
                      snapshot: c.draft,
                      baseline: before,
                      changes: changes,
                      remote: true,
                      warnings: [],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('변경할 코스 2개'), findsOneWidget);
        expect(find.text('이용자 배정 변경 (1)'), findsOneWidget);
        expect(find.text('기존 순서'), findsNothing);
        await screenshot(tester, 'confirm-${width.toInt()}');
        await tester.tap(find.byKey(const ValueKey('course-review-morning-1')));
        await tester.pumpAndSettle();
        expect(find.text('기존 순서'), findsOneWidget);
        expect(find.textContaining('김영숙: 김다정'), findsOneWidget);
        expect(c.confirmed, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
