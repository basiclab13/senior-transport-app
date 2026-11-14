import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/ai_schedule_suggestion.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/schedule_codec.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';
import 'package:senior_transport_app/utils/display_wording.dart';
import 'package:senior_transport_app/utils/schedule_wording.dart';
import 'package:senior_transport_app/widgets/ai_schedule_suggestion_dialog.dart';

import 'support/fixtures.dart';

const admin = AppUser(uid: 'language-admin', role: UserRole.admin);
AiScheduleSuggestion recommendation(
  ScheduleController c, {
  bool changed = true,
  bool staffOnly = false,
}) => AiScheduleSuggestion.fromJson(
  {
    ...scheduleToJson(c.draft),
    'catalogVersion': c.catalog.version,
    'expectedVersion': c.confirmed?.version ?? 0,
    'routes': [
      for (final r in c.draft.routes)
        {
          'baseRouteId': r.baseRouteId,
          'staffId': staffOnly && r == c.draft.routes.first ? 's3' : r.staffId,
          'passengerIds': changed && !staffOnly && r == c.draft.routes.first
              ? r.passengerIds.reversed.toList()
              : r.passengerIds,
        },
    ],
    'reasons': ['가상 좌표 직선거리 추정 설명'],
    'warnings': <String>[],
    'distanceComparison': {
      'method': 'fictional-euclidean-round-trip-v1',
      'beforeKm': 10,
      'afterKm': 12,
    },
  },
  origin: c.draft,
  catalog: c.catalog,
  confirmed: c.confirmed,
  absenceRevision: c.absenceRevisionKey,
  generation: 0,
);

void main() {
  const capture = bool.fromEnvironment('CAPTURE_EASY_LANGUAGE');
  setUpAll(() async {
    if (capture && Platform.isWindows) {
      final font = FontLoader('EasyLanguageDemo')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File('C:/Windows/Fonts/malgun.ttf').readAsBytes(),
            ),
          ),
        );
      await font.load();
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
  test('display labels do not change identifiers, names or raw diagnostic messages', () {
    final c = fixtureController(user: admin);
    addTearDown(c.dispose);
    final raw = c.catalog.passengers.first.name;
    expect(displayName(raw), '어르신 A');
    expect(c.catalog.passengers.first.name, raw);
    expect(c.catalog.passengers.first.id, 'p1');
    const diagnostic =
        '결근 정보 읽기 권한이 없습니다 (permission-denied). Firestore Rules를 확인해 주세요.';
    final visible = easyScheduleMessage(diagnostic);
    expect(visible, contains('관리자에게 계정 확인'));
    expect(visible, contains('일정을 확정할 수 없습니다'));
    expect(
      visible,
      isNot(matches(RegExp('Firestore|Rules|permission-denied'))),
    );
    expect(diagnostic, contains('permission-denied'));
    expect(displayMessage('직원 계정의 staffId가 없습니다.'), contains('담당 직원 정보'));
  });

  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    for (final changed in [false, true]) {
      testWidgets(
        '$width recommendation changed=$changed is concise, reviewed and never auto-confirmed',
        (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final c = fixtureController(user: admin);
          addTearDown(c.dispose);
          c.setVisitMinute('morning-a', 'p1', 490);
          final before = scheduleToJson(c.draft);
          final suggestion = recommendation(c, changed: changed);
          bool? accepted;
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                theme: ThemeData(
                  fontFamily: capture ? 'EasyLanguageDemo' : null,
                ),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () async {
                        accepted = await showDialog<bool>(
                          context: context,
                          builder: (_) => AiScheduleSuggestionDialog(
                            controller: c,
                            suggestion: suggestion,
                          ),
                        );
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          if (capture) {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              Directory('.local-tools/friendly-ui').createSync(recursive: true);
              File(
                '.local-tools/friendly-ui/${changed ? 'recommendation' : 'no-change'}-${width.toInt()}.png',
              ).writeAsBytesSync(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          expect(find.text('추천 일정 확인'), findsOneWidget);
          expect(scheduleToJson(c.draft), before);
          expect(find.byKey(const Key('ai-distance-comparison')), findsNothing);
          expect(find.textContaining('추정'), findsNothing);
          if (!changed) {
            expect(find.text('현재 일정 그대로 사용해도 됩니다'), findsOneWidget);
            expect(find.byKey(const Key('ai-more-details')), findsNothing);
            expect(
              find.byKey(const Key('approve-ai-suggestion')),
              findsNothing,
            );
            expect(
              tester
                      .getRect(find.byKey(const Key('close-ai-suggestion')))
                      .bottom -
                  tester.getRect(find.text('추천 일정 확인')).top,
              lessThan(260),
            );
            await tester.tap(find.byKey(const Key('close-ai-suggestion')));
            await tester.pumpAndSettle();
            expect(accepted, false);
            expect(scheduleToJson(c.draft), before);
          } else {
            expect(find.text('방문 순서 변경 1코스'), findsOneWidget);
            expect(find.textContaining('이용자 이동'), findsNothing);
            expect(find.text('약속 시간 조정이 필요할 수 있으니 확인해 주세요.'), findsOneWidget);
            final more = find.byKey(const Key('ai-more-details'));
            await tester.scrollUntilVisible(
              more,
              100,
              scrollable: find.byType(Scrollable).last,
            );
            await tester.tap(more);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const Key('ai-distance-comparison')),
              findsOneWidget,
            );
            expect(find.textContaining('거리 개선안이 아닙니다'), findsOneWidget);
            expect(find.textContaining('절감 효과가 아닙니다'), findsOneWidget);
            expect(find.textContaining('직선거리'), findsNothing);
            expect(find.textContaining('추정'), findsNothing);
            final approve = find.byKey(const Key('approve-ai-suggestion'));
            expect(tester.getRect(approve).right, lessThanOrEqualTo(width));
            await tester.tap(approve);
            await tester.pumpAndSettle();
            expect(accepted, true);
            // The caller, not the dialog itself, applies an approved draft.
            expect(scheduleToJson(c.draft), before);
            expect(c.draft.routes.first.estimatedVisitMinutes['p1'], 490);
            expect(c.draft.routes.first.estimatedVisitSources['p1'], 'manual');
          }
          expect(c.confirmed, isNull);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      '$width ordinary schedule moves demonstration notice into app information',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = fixtureController(user: admin);
        addTearDown(c.dispose);
        final before = scheduleToJson(c.draft);
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
        expect(find.text('테스트 데이터'), findsNothing);
        expect(find.textContaining('가상 어르신'), findsNothing);
        await tester.tap(find.byKey(const Key('app-info')));
        await tester.pumpAndSettle();
        expect(find.textContaining('시연용 데이터'), findsOneWidget);
        await tester.tap(find.text('확인'));
        await tester.pumpAndSettle();
        expect(scheduleToJson(c.draft), before);
        expect(c.hasPendingChanges, false);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'staff-only AI change does not claim passengers moved; stale approval remains blocked',
    (tester) async {
      final c = fixtureController(user: admin);
      addTearDown(c.dispose);
      final suggestion = recommendation(c, staffOnly: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiScheduleSuggestionDialog(
              controller: c,
              suggestion: suggestion,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('담당 직원 변경 1코스'), findsOneWidget);
      expect(find.textContaining('이용자 이동'), findsNothing);
      c.markAbsent('p1');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('approve-ai-suggestion')),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('닫고 다시 추천받아'), findsOneWidget);
      expect(c.confirmed, isNull);
    },
  );
}
