import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/ai_schedule_suggestion.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';
import 'package:senior_transport_app/services/schedule_repository.dart';
import 'package:senior_transport_app/services/visit_time_calculator.dart';

import 'staff_absence_test.dart' show AbsenceRepository;
import 'support/fixtures.dart';

class FixedSuggestionRepository extends AbsenceRepository
    implements ScheduleSuggestionRepository {
  @override
  bool get allowsAiSuggestions => true;
  final suggestionRequests = <Map<String, dynamic>>[];
  Completer<void>? aiHold;
  Object? aiFailure;
  Map<String, dynamic> Function(Map<String, dynamic>)? respond;

  static Map<String, dynamic> fixed(Map<String, dynamic> request) => {
    'date': request['date'],
    'period': request['period'],
    'catalogVersion': request['catalogVersion'],
    'expectedVersion': request['expectedVersion'],
    'routes': [
      for (final r in request['routes'] as List)
        {
          'baseRouteId': r['baseRouteId'],
          'staffId': r['staffId'],
          'passengerIds': r['baseRouteId'] == 'morning-a'
              ? (r['passengerIds'] as List).reversed.toList()
              : r['passengerIds'],
        },
    ],
    'reasons': ['고정 테스트 응답: 방문 순서 조정'],
    'warnings': <String>[],
  };
  @override
  Future<Map<String, dynamic>> suggestSchedule(
    Map<String, dynamic> request,
  ) async {
    final copy = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(request)) as Map,
    );
    suggestionRequests.add(copy);
    if (aiHold != null) await aiHold!.future;
    if (aiFailure != null) throw aiFailure!;
    return (respond ?? fixed)(copy);
  }
}

void main() {
  const admin = AppUser(uid: 'admin', role: UserRole.admin);
  late FixedSuggestionRepository repo;
  late ScheduleController c;
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  setUp(() async {
    repo = FixedSuggestionRepository();
    c = ScheduleController.remote(
      user: admin,
      repository: repo,
      clock: fixtureClock,
    );
    await settle();
  });
  tearDown(() async {
    c.dispose();
    await repo.changes.close();
    await repo.availabilityChanges.close();
    await repo.availabilityEvents.close();
  });

  test('request/preview is read-only; approved batch preserves all protected fields and enters B-2', () async {
    c.setVisitMinute('morning-a', 'p1', 490);
    c.setVisitMinute('morning-a', 'p2', 500);
    final origin = c.draft;
    final suggestion = await c.requestAiSuggestion();
    expect(c.draft, same(origin));
    expect(c.suggesting, isFalse);
    expect(repo.requests, isEmpty);
    var notifications = 0;
    c.addListener(() => notifications++);
    c.applyAiSuggestion(suggestion);
    expect(notifications, 1);
    expect(c.draft.routes.first.passengerIds, ['p3', 'p2', 'p1']);
    expect(c.draft.routes.first.vehicleId, origin.routes.first.vehicleId);
    expect(
      c.draft.routes.first.estimatedVisitMinutes,
      origin.routes.first.estimatedVisitMinutes,
    );
    expect(
      c.draft.routes.first.estimatedVisitSources,
      origin.routes.first.estimatedVisitSources,
    );
    expect(c.draft.absentIds, origin.absentIds);
    expect(c.draft.excludedIds, origin.excludedIds);
    expect(c.pendingTimeReviewRouteIds, {'morning-a'});
    expect(() => c.keepVisitTimes('morning-a'), throwsStateError);
    expect(await c.publish(), isFalse);
    expect(repo.requests, isEmpty);
    c.applyVisitTimePreview(
      previewVisitTimes(c.draft, 'morning-a', 480, 5, replaceManual: true),
      manualOverwriteConfirmed: true,
    );
    expect(await c.publish(), isTrue);
    expect(c.confirmed!.version, 1);
  });

  test('passenger transfer marks both routes and carries legacy time without adding provenance', () async {
    // A legacy source is represented by a loaded confirmed schedule.
    final original = c.draft;
    repo.snapshots[repo.key(c.selectedDate, c.period)] = original.copyWith(
      version: 1,
      confirmedAt: DateTime(2026),
      routes: [
        original.routes.first.copyWith(estimatedVisitMinutes: {'p1': 490}),
        original.routes.last,
      ],
    );
    await c.reloadDiscardingDraft();
    await settle();
    repo.respond = (request) {
      final result = FixedSuggestionRepository.fixed(request);
      final routes = result['routes'] as List;
      routes[0]['passengerIds'] = ['p2', 'p3'];
      routes[1]['passengerIds'] = ['p4', 'p5', 'p1'];
      return result;
    };
    final suggestion = await c.requestAiSuggestion();
    c.applyAiSuggestion(suggestion);
    expect(c.pendingTimeReviewRouteIds, {'morning-a', 'morning-b'});
    expect(c.draft.routes.last.estimatedVisitMinutes['p1'], 490);
    expect(
      c.draft.routes.last.estimatedVisitSources.containsKey('p1'),
      isFalse,
    );
  });

  test('duplicate passenger, absent owner, missing course, unknown staff and protected fields cannot apply', () async {
    final origin = c.draft;
    final mutations = <void Function(Map<String, dynamic>)>[
      (r) => (r['routes'] as List).removeLast(),
      (r) => (r['routes'] as List)[1]['passengerIds'] = ['p4', 'p1'],
      (r) => (r['routes'] as List)[0]['staffId'] = 'unknown',
      (r) => (r['routes'] as List)[0]['vehicleId'] = 'v3',
      (r) => (r['routes'] as List)[0]['estimatedVisitMinutes'] = {},
    ];
    for (final mutate in mutations) {
      repo.respond = (request) {
        final result = FixedSuggestionRepository.fixed(request);
        mutate(result);
        return result;
      };
      await expectLater(c.requestAiSuggestion(), throwsStateError);
      expect(c.draft, same(origin));
      expect(c.suggesting, isFalse);
    }
    await c.setStaffAbsence('s1', {TransportPeriod.morning}, true, 0);
    repo.respond = FixedSuggestionRepository.fixed;
    await expectLater(c.requestAiSuggestion(), throwsStateError);
    expect(repo.requests, isEmpty);
  });

  test(
    'API error leaves draft and confirmed schedule intact and permits retry',
    () async {
      final origin = c.draft;
      repo.aiFailure = FirebaseFunctionsException(
        code: 'unavailable',
        message: 'fixed offline response',
      );
      await expectLater(c.requestAiSuggestion(), throwsStateError);
      expect(c.draft, same(origin));
      expect(c.confirmed, isNull);
      expect(c.suggesting, isFalse);
      repo.aiFailure = null;
      expect(await c.requestAiSuggestion(), isNotNull);
    },
  );

  test('unjustified course moves explain how to keep the existing assignment without changing the draft', () async {
    final origin = c.draft;
    repo.aiFailure = FirebaseFunctionsException(
      code: 'invalid-argument',
      message: 'fixed response',
      details: {'violation': 'REASSIGNMENT_NOT_JUSTIFIED'},
    );
    await expectLater(
      c.requestAiSuggestion(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'guidance',
          contains('기존 코스를 유지'),
        ),
      ),
    );
    expect(c.draft, same(origin));
    expect(repo.requests, isEmpty);
  });
  for (final change in ['draft', 'absence', 'date']) {
    test('$change changed during request rejects stale response', () async {
      repo.aiHold = Completer<void>();
      final future = c.requestAiSuggestion();
      final expectation = expectLater(future, throwsStateError);
      expect(c.suggesting, isTrue);
      if (change == 'draft') c.markAbsent('p2');
      if (change == 'absence') {
        await c.setStaffAbsence('s3', {TransportPeriod.morning}, true, 0);
      }
      if (change == 'date') {
        c.selectDate(DateTime(2026, 11, 13));
        await settle();
      }
      repo.aiHold!.complete();
      await expectation;
      expect(c.suggesting, isFalse);
      expect(repo.requests, isEmpty);
    });
  }

  test('draft or absence change after response blocks approval; employee role cannot request', () async {
    final suggestion = await c.requestAiSuggestion();
    await c.setStaffAbsence('s3', {TransportPeriod.morning}, true, 0);
    expect(() => c.applyAiSuggestion(suggestion), throwsStateError);
    final latest = await c.requestAiSuggestion();
    c.reorder('morning-a', 0, 1);
    expect(() => c.applyAiSuggestion(latest), throwsStateError);
    c.dispose();
    c = ScheduleController.remote(
      user: const AppUser(uid: 'staff', role: UserRole.staff, staffId: 's1'),
      repository: repo,
      clock: fixtureClock,
    );
    await settle();
    await expectLater(c.requestAiSuggestion(), throwsStateError);
  });

  Future<void> open(WidgetTester tester, {bool small = false}) async {
    tester.view.physicalSize = small
        ? const Size(390, 844)
        : const Size(1280, 1000);
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

  testWidgets(
    'AI button previews differences, cancellation preserves draft, explicit approval enters B-2',
    (tester) async {
      await open(tester);
      final origin = c.draft;
      await tester.tap(find.byKey(const Key('suggest-schedule')));
      await tester.pumpAndSettle();
      expect(find.text('AI 일정 제안 검토'), findsOneWidget);
      expect(c.draft, same(origin));
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(c.draft, same(origin));
      await tester.tap(find.byKey(const Key('suggest-schedule')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('approve-ai-suggestion')));
      await tester.pumpAndSettle();
      expect(c.pendingTimeReviewRouteIds, {'morning-a'});
      expect(repo.requests, isEmpty);
      expect(c.hasPendingChanges, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'small-screen preview disables approval if draft changes while dialog is open',
    (tester) async {
      await open(tester, small: true);
      await tester.tap(find.byKey(const Key('suggest-schedule')));
      await tester.pumpAndSettle();
      c.markAbsent('p2');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('approve-ai-suggestion')),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('닫고 다시 요청'), findsOneWidget);
      expect(repo.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'loading is visible and API failure shows a retryable message without modifying draft',
    (tester) async {
      repo.aiHold = Completer<void>();
      repo.aiFailure = FirebaseFunctionsException(
        code: 'unavailable',
        message: 'fixed offline response',
      );
      await open(tester);
      final origin = c.draft;
      await tester.tap(find.byKey(const Key('suggest-schedule')));
      await tester.pump();
      expect(find.text('AI 제안 생성 중…'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('suggest-schedule')))
            .onPressed,
        isNull,
      );
      repo.aiHold!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('AI 요청에 실패'), findsOneWidget);
      expect(c.draft, same(origin));
      expect(tester.takeException(), isNull);
    },
  );

  test('distance comparison guards malformed values, zero baseline and rounding boundaries', () {
    ScheduleDistanceComparison compare(double before, double after) =>
        ScheduleDistanceComparison.fromJson({
          'method': 'fictional-euclidean-round-trip-v1',
          'beforeKm': before,
          'afterKm': after,
        });
    expect(compare(10, 5).summary, contains('50.00%'));
    expect(compare(10, 12).summary, contains('거리 개선안이 아닙니다'));
    expect(compare(0, 0).summary, contains('개선이 없습니다'));
    expect(compare(0, 5).summary, contains('비율 계산 불가'));
    expect(compare(1000, 999.998).summary, contains('0.01% 미만'));
    expect(compare(2, 1.9995).improved, isFalse);
    expect(() => compare(-1, 1), throwsFormatException);
    expect(() => compare(double.nan, 1), throwsFormatException);
  });
  for (final outcome in ['improved', 'worse', 'unchanged']) {
    testWidgets(
      'existing review dialog reports $outcome distance truthfully without automatic application',
      (tester) async {
        repo.respond = (request) {
          final result = FixedSuggestionRepository.fixed(request);
          if (outcome == 'unchanged') {
            result['routes'] = [
              for (final r in request['routes'] as List)
                {
                  'baseRouteId': r['baseRouteId'],
                  'staffId': r['staffId'],
                  'passengerIds': r['passengerIds'],
                },
            ];
          }
          result['distanceComparison'] = {
            'method': 'fictional-euclidean-round-trip-v1',
            'beforeKm': 10.0,
            'afterKm': outcome == 'improved'
                ? 8.0
                : outcome == 'worse'
                ? 12.0
                : 10.0,
          };
          result['reasons'] = ['프로그램 계산에 따른 테스트 설명'];
          return result;
        };
        await open(tester, small: outcome == 'worse');
        final origin = c.draft;
        await tester.tap(find.byKey(const Key('suggest-schedule')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('ai-distance-comparison')), findsOneWidget);
        final summary = tester
            .widget<Text>(find.byKey(const Key('ai-distance-change')))
            .data!;
        expect(
          summary,
          contains(
            outcome == 'improved'
                ? '감소 2.000 km · 20.00%'
                : outcome == 'worse'
                ? '거리 개선안이 아닙니다'
                : '개선이 없습니다',
          ),
        );
        expect(find.text('계산으로 확인한 추천 설명'), findsNothing);
        expect(find.byKey(const Key('ai-distance-limit')), findsOneWidget);
        expect(c.draft, same(origin));
        expect(repo.requests, isEmpty);
        if (outcome == 'unchanged') {
          expect(find.text('현재 일정과 변경사항이 없습니다.'), findsOneWidget);
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const Key('approve-ai-suggestion')),
                )
                .onPressed,
            isNull,
          );
        }
        await tester.tap(find.text('취소'));
        await tester.pumpAndSettle();
        expect(c.draft, same(origin));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
