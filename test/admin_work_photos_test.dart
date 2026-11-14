import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/services/work_photo_repository.dart';
import 'package:senior_transport_app/widgets/admin_work_photos.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j6R0AAAAASUVORK5CYII=';

void main() {
  var metadataReads = 0, imageReads = 0;
  var empty = false, metadataFail = false, imageFail = false;
  Completer<Map<String, dynamic>>? delayed;
  late WorkPhotoRepository repo;
  Map<String, dynamic> entry(Map<String, dynamic> input, String kind) => {
    'recordId': '${input['staffId']}_${input['date']}_${input['period']}_$kind',
    'staffId': input['staffId'],
    'date': input['date'],
    'period': input['period'],
    'routeId': 'route',
    'kind': kind,
    'registeredAt': kind == 'start'
        ? '2026-11-14T00:01:02Z'
        : '2026-11-14T01:01:02Z',
  };
  setUp(() {
    metadataReads = 0;
    imageReads = 0;
    empty = false;
    metadataFail = false;
    imageFail = false;
    delayed = null;
    repo = WorkPhotoRepository(
      enabled: true,
      call: (name, input) async {
        expect(name, 'getWorkPhotos');
        if (input.containsKey('recordId')) {
          imageReads++;
          if (imageFail) throw StateError('network');
          return {
            ...entry(
              input,
              (input['recordId'] as String).endsWith('start') ? 'start' : 'end',
            ),
            'photoBase64': _png,
          };
        }
        metadataReads++;
        if (metadataFail) throw StateError('permission denied');
        if (delayed != null) return delayed!.future;
        return {
          'records': empty ? [] : [entry(input, 'start'), entry(input, 'end')],
          'nextCursor': null,
        };
      },
    );
  });
  Future<void> open(
    WidgetTester tester, {
    String staffId = 's1',
    String date = '2026-11-14',
    TransportPeriod period = TransportPeriod.morning,
    UserRole role = UserRole.admin,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminWorkPhotos(
              repository: repo,
              user: AppUser(uid: 'viewer', role: role),
              staffId: staffId,
              date: date,
              period: period,
              routeNames: const {'route': '햇살 코스'},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'inline Korean timestamps, metadata only until opened, cached reopen and refresh',
    (tester) async {
      await open(tester);
      expect(find.text('등록 · 2026-11-14 09:01:02'), findsOneWidget);
      expect(find.text('등록 · 2026-11-14 10:01:02'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(metadataReads, 1);
      expect(imageReads, 0);
      await tester.tap(find.text('사진 보기').first);
      await tester.pumpAndSettle();
      expect(imageReads, 1);
      expect(find.byType(Image), findsOneWidget);
      expect(tester.getSize(find.byType(Image)).height, 100);
      await tester.tap(find.text('크게 보기'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(Image)).height, 300);
      expect(imageReads, 1);
      await tester.ensureVisible(find.text('작게 보기'));
      await tester.tap(find.text('작게 보기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('사진 접기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('사진 보기').first);
      await tester.pumpAndSettle();
      expect(imageReads, 1);
      await tester.tap(find.byKey(const Key('refresh-admin-photos')));
      await tester.pumpAndSettle();
      expect(metadataReads, 2);
      expect(imageReads, 1);
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'empty is unregistered; metadata failure never claims unregistered and can recover',
    (tester) async {
      empty = true;
      await open(tester);
      expect(find.text('미등록'), findsNWidgets(2));
      metadataFail = true;
      await tester.tap(find.byKey(const Key('refresh-admin-photos')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-photo-record-error')), findsOneWidget);
      expect(find.text('미등록'), findsNothing);
      metadataFail = false;
      empty = false;
      await tester.tap(find.byKey(const Key('refresh-admin-photos')));
      await tester.pumpAndSettle();
      expect(find.textContaining('09:01:02'), findsOneWidget);
      expect(imageReads, 0);
    },
  );
  testWidgets(
    'image failure keeps registration status and retries only on explicit request',
    (tester) async {
      imageFail = true;
      await open(tester);
      await tester.tap(find.text('사진 보기').first);
      await tester.pumpAndSettle();
      expect(find.text('등록 기록은 있지만 사진을 불러오지 못했습니다.'), findsOneWidget);
      expect(find.textContaining('09:01:02'), findsOneWidget);
      expect(imageReads, 1);
      imageFail = false;
      await tester.tap(find.text('사진 다시 불러오기'));
      await tester.pumpAndSettle();
      expect(imageReads, 2);
      expect(find.byType(Image), findsOneWidget);
    },
  );
  testWidgets(
    'employee/date/period changes clear displayed image scope; staff cannot use admin panel',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('사진 보기').first);
      await tester.pumpAndSettle();
      await open(tester, staffId: 's2');
      expect(find.byType(Image), findsNothing);
      await open(tester, staffId: 's2', date: '2026-11-15');
      await open(
        tester,
        staffId: 's2',
        date: '2026-11-15',
        period: TransportPeriod.afternoon,
      );
      expect(metadataReads, 4);
      expect(imageReads, 1);
      await open(tester, role: UserRole.staff);
      expect(find.text('업무 시작·종료 기록'), findsNothing);
      expect(metadataReads, 4);
    },
  );
  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    testWidgets('start/end layout at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester);
      final start = tester.getRect(
        find.byKey(const ValueKey('admin-photo-start')),
      );
      final end = tester.getRect(find.byKey(const ValueKey('admin-photo-end')));
      if (width < 560) {
        expect(end.top, greaterThan(start.bottom));
      } else {
        expect(end.top, start.top);
        expect(end.left, greaterThan(start.right));
      }
      expect(tester.takeException(), isNull);
      expect(imageReads, 0);
    });
  }
  testWidgets(
    'late result from previous staff does not replace new selection',
    (tester) async {
      delayed = Completer<Map<String, dynamic>>();
      final first = delayed!;
      await open(tester);
      expect(find.text('미등록'), findsNothing);
      delayed = null;
      empty = true;
      await open(tester, staffId: 's2');
      expect(find.text('미등록'), findsNWidgets(2));
      first.complete({
        'records': [
          entry({
            'staffId': 's1',
            'date': '2026-11-14',
            'period': 'morning',
          }, 'start'),
        ],
        'nextCursor': null,
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('09:01:02'), findsNothing);
      expect(imageReads, 0);
    },
  );
}
