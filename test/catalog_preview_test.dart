import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/schedule_codec.dart';
import 'package:senior_transport_app/models/schedule_catalog.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/catalog_preview_screen.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/catalog_preview_repository.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';

class FixedCatalogPreviewSource implements CatalogPreviewSource {
  FixedCatalogPreviewSource(this.data, {this.enabled = true});
  final CatalogPreviewData data;
  bool enabled;
  int loads = 0;
  final requests = <Map<String, dynamic>>[];
  Completer<void>? hold;
  bool omitContext = false;
  @override
  bool get allowsPreviewRequests => enabled;
  @override
  Future<CatalogPreviewData> load(AppUser user) async {
    loads++;
    return data;
  }

  @override
  Future<Map<String, dynamic>> suggest(Map<String, dynamic> request) async {
    requests.add(request);
    if (hold != null) await hold!.future;
    return {
      'date': request['date'],
      'period': request['period'],
      'catalogVersion': request['catalogVersion'],
      'expectedVersion': 0,
      'reasons': ['고정 미리보기 응답'],
      'warnings': <String>[],
      if (!omitContext) 'previewContext': request['previewContext'],
      'routes': [
        for (final raw in request['routes'] as List)
          {
            'baseRouteId': raw['baseRouteId'],
            'staffId': raw['staffId'],
            'passengerIds': raw['baseRouteId'] == 'morning-ai-01'
                ? (List<String>.from(raw['passengerIds'] as List)..sort())
                : raw['passengerIds'],
          },
      ],
    };
  }
}

void main() {
  const admin = AppUser(uid: 'preview-admin', role: UserRole.admin);
  const staff = AppUser(
    uid: 'preview-staff',
    role: UserRole.staff,
    staffId: 's1',
  );
  late CatalogPreviewData data;
  late FixedCatalogPreviewSource source;
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    final manifest = jsonDecode(
      File('docs/fixtures/ai-test-25x80-v1.baseline.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final metadata = Map<String, dynamic>.from(manifest['metadata'] as Map)
      ..['manifestSha256'] = previewManifestHash;
    // Firestore returns lexicographic document order, not staffing order.
    final collections = Map<String, dynamic>.from(
      manifest['collections'] as Map,
    );
    (collections['staff'] as List).sort(
      (a, b) => (a['id'] as String).compareTo(b['id'] as String),
    );
    data = CatalogPreviewData.fromJson(metadata, collections);
    source = FixedCatalogPreviewSource(data);
  });
  Future<ScheduleController> controller(String scenario) async {
    final c = ScheduleController.remote(
      user: admin,
      repository: CatalogPreviewRepository(
        data: data,
        source: source,
        user: admin,
        scenario: scenario,
      ),
    );
    c.selectDate(DateTime(2026, 12, 7));
    c.selectPeriod(TransportPeriod.morning);
    await settle();
    return c;
  }

  test('all scenario drafts reproduce the server fixture without loading any confirmed schedule', () async {
    for (final scenario in previewScenarios.keys) {
      final c = await controller(scenario);
      try {
        expect(c.isCatalogPreview, isTrue);
        expect(c.confirmed, isNull);
        expect(c.draft.version, 0);
        expect(c.draft.routes.length, 20);
        expect(c.previewReserveStaffIds, {'s21', 's22', 's23', 's24', 's25'});
        final stored = jsonDecode(
          File('docs/fixtures/ai-test-25x80-v1-scenarios/$scenario.json')
              .readAsStringSync(),
        ) as Map;
        final expected = Map<String, dynamic>.from(stored['input'] as Map),
            actual = scheduleToJson(c.draft);
        for (final key in actual.keys) {
          expect(actual[key], expected[key], reason: '$scenario: $key');
        }
        if (scenario == 'five-staff-absent') {
          expect(c.absences.keys.toSet(), {'s1', 's2', 's3', 's4', 's5'});
        }
        if (scenario == 'six-staff-absent') {
          expect(c.supportsAiSuggestions, isFalse);
        }
        c.selectPeriod(TransportPeriod.afternoon);
        await settle();
        expect(c.draft.period, TransportPeriod.afternoon);
        expect(c.draft.routes.length, 20);
        expect(c.confirmed, isNull);
      } finally {
        c.dispose();
      }
    }
    expect(source.requests, isEmpty);
  });
  test('staff cannot construct preview repository and all publishing/absence methods reject', () async {
    expect(
      () => CatalogPreviewRepository(
        data: data,
        source: source,
        user: staff,
        scenario: 'unchanged',
      ),
      throwsStateError,
    );
    final repo = CatalogPreviewRepository(
      data: data,
      source: source,
      user: admin,
      scenario: 'unchanged',
    );
    final view = await repo.load(
      admin,
      DateTime(2026, 12, 7),
      TransportPeriod.morning,
    );
    expect(view.confirmed, isNull);
    await expectLater(
      repo.publish(view.previewDraft!, previewCatalogVersion, 0, 'id'),
      throwsStateError,
    );
    await expectLater(
      repo.publishWithAvailability(
        view.previewDraft!,
        previewCatalogVersion,
        0,
        'id',
        {},
      ),
      throwsStateError,
    );
    await expectLater(
      repo.committed(DateTime(2026, 12, 7), TransportPeriod.morning, 'id'),
      throwsStateError,
    );
    await expectLater(repo.setAbsence({}), throwsStateError);
    await expectLater(
      repo.load(staff, DateTime(2026, 12, 7), TransportPeriod.morning),
      throwsStateError,
    );
    final c = await controller('staff-absence');
    try {
      expect(c.isStaffAbsent('s1'), isTrue);
      c.reassignAbsentCourse('morning-ai-01', 's21');
      expect(c.draft.routes.first.staffId, 's21');
      expect(c.draft.routes.first.vehicleId, 'v1');
      expect(c.draft.routes.first.passengerIds, ['p1', 'p2', 'p3', 'p4']);
      expect(await c.publish(), isFalse);
      expect(c.confirmed, isNull);
      expect(c.confirm, throwsStateError);
      expect(
        await c.setStaffAbsence('s2', {TransportPeriod.morning}, true, 0),
        isFalse,
      );
      expect(source.requests, isEmpty);
    } finally {
      c.dispose();
    }
  });
  test('preview AI requires approval to apply, binds context, enters B-2 and can never publish', () async {
    final c = await controller('order-improvement');
    try {
      final before = c.draft, proposal = await c.requestAiSuggestion();
      expect(c.draft, same(before));
      expect(c.confirmed, isNull);
      expect(source.requests.single['previewContext'], {
        'kind': 'ai25-catalog-preview',
        'scenario': 'order-improvement',
        'manifestSha256': previewManifestHash,
      });
      c.applyAiSuggestion(proposal);
      expect(c.draft.routes.first.passengerIds, ['p1', 'p2', 'p3', 'p4']);
      expect(
        c.draft.routes.first.estimatedVisitMinutes,
        before.routes.first.estimatedVisitMinutes,
      );
      expect(c.confirmationErrors, isEmpty);
      expect(await c.publish(), isFalse);
      expect(c.confirmed, isNull);
    } finally {
      c.dispose();
    }
  });
  test(
    'missing response scope and date changes reject stale previews',
    () async {
      final c = await controller('order-improvement');
      try {
        source.omitContext = true;
        await expectLater(c.requestAiSuggestion(), throwsStateError);
        source.omitContext = false;
        source.hold = Completer<void>();
        final pending = c.requestAiSuggestion();
        final rejected = expectLater(pending, throwsStateError);
        await settle();
        c.selectDate(DateTime(2026, 12, 8));
        await settle();
        source.hold!.complete();
        await rejected;
        expect(c.selectedDate, DateTime(2026, 12, 8));
        expect(c.confirmed, isNull);
      } finally {
        c.dispose();
      }
    },
  );
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(1280, 900),
  ]) {
    testWidgets(
      'preview controls are isolated and never show confirmation at $size',
      (tester) async {
        source.enabled = false;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: CatalogPreviewScreen(
              user: admin,
              source: source,
              onSignOut: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('AI 테스트 · 실제 일정과 분리 · 저장되지 않음'), findsOneWidget);
        expect(find.byKey(const Key('confirm-schedule')), findsNothing);
        expect(find.byKey(const Key('suggest-schedule')), findsNothing);
        final normal = find.byType(ScheduleScreen);
        final c = tester.widget<ScheduleScreen>(normal).controller!;
        expect(c.isCatalogPreview, isTrue);
        expect(c.catalog.staff.length, 25);
        final picker = find.byKey(const ValueKey('preview-scenario-unchanged'));
        tester.widget<DropdownButtonFormField<String>>(picker).onChanged!(
          'five-staff-absent',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('상황 불러오기'));
        await tester.pumpAndSettle();
        final updated = tester
            .widget<ScheduleScreen>(find.byType(ScheduleScreen))
            .controller!;
        expect(updated.absences.keys.toSet(), {'s1', 's2', 's3', 's4', 's5'});
        expect(find.byKey(const Key('confirm-schedule')), findsNothing);
        expect(source.requests, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('staff preview route fails before reading the catalog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CatalogPreviewScreen(
          user: staff,
          source: source,
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(source.loads, 0);
    expect(source.requests, isEmpty);
    expect(find.textContaining('테스트 일정을 불러오지 못했습니다.'), findsOneWidget);
  });
  testWidgets(
    'leaving preview restores the untouched operational catalog, date and draft',
    (tester) async {
      source.enabled = false;
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final baseline = jsonDecode(
        File('docs/fixtures/deploy-test-v2.baseline.json').readAsStringSync(),
      ) as Map;
      final live = ScheduleController(
        user: admin,
        catalog: ScheduleCatalog.fromJson(
          'deploy-test-v2',
          Map<String, dynamic>.from(baseline['collections'] as Map),
        ),
        initialDate: DateTime(2026, 12, 7),
      );
      addTearDown(live.dispose);
      final original = live.draft;
      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleScreen(
            user: admin,
            controller: live,
            catalogPreviewSource: source,
            onSignOut: () async {},
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-catalog-preview')));
      await tester.pumpAndSettle();
      final preview = tester
          .widget<ScheduleScreen>(find.byType(ScheduleScreen))
          .controller!;
      preview.selectDate(DateTime(2026, 12, 8));
      preview.selectPeriod(TransportPeriod.morning);
      await tester.pumpAndSettle();
      preview.setVisitMinute('morning-ai-01', 'p1', 539);
      await tester.pump();
      Navigator.of(tester.element(find.byType(CatalogPreviewScreen))).pop();
      await tester.pumpAndSettle();
      expect(live.catalog.version, 'deploy-test-v2');
      expect(live.selectedDate, DateTime(2026, 12, 7));
      expect(live.draft, same(original));
      expect(source.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
