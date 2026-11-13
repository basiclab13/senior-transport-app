import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';
import 'package:senior_transport_app/widgets/bulk_visit_time_dialog.dart';

import 'support/fixtures.dart';

void main() {
  const admin = AppUser(uid: 'admin', role: UserRole.admin);
  late ScheduleController c;
  setUp(() => c = fixtureController(user: admin));
  tearDown(() => c.dispose());
  Future<void> open(WidgetTester tester, {bool small = false}) async {
    tester.view.physicalSize = small
        ? const Size(320, 568)
        : const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await showDialog<VisitTimeApplication>(
                  context: context,
                  builder: (_) => BulkVisitTimeDialog(
                    catalog: c.catalog,
                    snapshot: c.draft,
                    routeId: 'morning-a',
                  ),
                );
                if (result != null) {
                  c.applyVisitTimePreview(
                    result.preview,
                    manualOverwriteConfirmed: result.manualOverwriteConfirmed,
                  );
                }
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> calculate(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('bulk-first-minute')), '08:00');
    await tester.enterText(find.byKey(const Key('bulk-interval')), '5');
    await tester.ensureVisible(
      find.byKey(const Key('calculate-visit-preview')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calculate-visit-preview')));
    await tester.pumpAndSettle();
  }

  testWidgets('preview and cancel leave the draft unchanged', (tester) async {
    final original = c.draft;
    await open(tester);
    await calculate(tester);
    expect(find.textContaining('방문 사이 간격으로 예상 시간을 정합니다.'), findsOneWidget);
    expect(find.textContaining('바뀔 시간 08:10'), findsOneWidget);
    expect(c.draft, same(original));
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(c.draft, same(original));
  });
  testWidgets(
    'manual values need a second explicit confirmation; rejecting it makes no change',
    (tester) async {
      c.setVisitMinute('morning-a', 'p1', 475);
      final original = c.draft;
      await open(tester);
      await tester.tap(find.byKey(const Key('preview-manual-visit-overwrite')));
      await tester.pumpAndSettle();
      await calculate(tester);
      await tester.tap(find.byKey(const Key('apply-bulk-visit-times')));
      await tester.pumpAndSettle();
      expect(find.text('직접 입력한 방문 시간 변경 확인'), findsOneWidget);
      expect(c.draft, same(original));
      await tester.tap(find.text('유지'));
      await tester.pumpAndSettle();
      expect(c.draft, same(original));
      await tester.tap(find.byKey(const Key('apply-bulk-visit-times')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-manual-visit-overwrite')));
      await tester.pumpAndSettle();
      expect(c.draft.routes.first.estimatedVisitMinutes['p1'], 480);
      expect(c.confirmed, isNull);
    },
  );
  testWidgets(
    'manual conflict disables apply; changing an input invalidates a preview',
    (tester) async {
      c.setVisitMinute('morning-a', 'p2', 470);
      await open(tester);
      await calculate(tester);
      expect(find.textContaining('확인할 내용'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('apply-bulk-visit-times')),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const Key('bulk-first-minute')),
        '07:30',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('적용 예정'), findsNothing);
    },
  );
  testWidgets('small screen can calculate, review and apply with scrolling', (
    tester,
  ) async {
    await open(tester, small: true);
    await calculate(tester);
    await tester.tap(find.byKey(const Key('apply-bulk-visit-times')));
    await tester.pumpAndSettle();
    expect(c.draft.routes.first.estimatedVisitMinutes, {
      'p1': 480,
      'p2': 485,
      'p3': 490,
    });
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'employee-detail entry changes only the dated draft and confirmation summary includes times',
    (tester) async {
      c.confirm();
      tester.view.physicalSize = const Size(1280, 1000);
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
      await tester.ensureVisible(
        find.byKey(const ValueKey('bulk-time-morning-a')),
      );
      await tester.tap(find.byKey(const ValueKey('bulk-time-morning-a')));
      await tester.pumpAndSettle();
      await calculate(tester);
      await tester.tap(find.byKey(const Key('apply-bulk-visit-times')));
      await tester.pumpAndSettle();
      expect(c.confirmed!.routes.first.estimatedVisitMinutes, isEmpty);
      await tester.tap(find.byKey(const Key('confirm-schedule')));
      await tester.pumpAndSettle();
      expect(find.textContaining('예상 시각 변경'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
