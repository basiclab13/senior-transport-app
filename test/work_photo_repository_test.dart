import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/attendance_record.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/services/work_photo_repository.dart';

void main() {
  const user = AppUser(uid: 'staff', role: UserRole.staff, staffId: 's1');
  final bytes = Uint8List.fromList([255, 216, 255, 217]);
  Map<String, dynamic> record() => {
    'recordId': 'record',
    'staffId': 's1',
    'date': '2026-11-14',
    'period': 'morning',
    'routeId': 'route',
    'kind': 'start',
    'registeredAt': '2026-11-14T00:01:02.000Z',
    'photoBase64': base64Encode(bytes),
  };
  Future<AttendanceRecord> register(
    WorkPhotoRepository repo, {
    AppUser actor = user,
  }) => repo.register(
    user: actor,
    date: '2026-11-14',
    period: TransportPeriod.morning,
    routeId: 'route',
    kind: WorkPhotoKind.start,
    photo: bytes,
    expectedVersion: 3,
    expectedAvailabilityVersion: 2,
  );

  test(
    'Storage API is opt-in and requires an employee and version context',
    () async {
      var calls = 0;
      final disabled = WorkPhotoRepository(
        enabled: false,
        call: (name, input) async {
          calls++;
          return {};
        },
      );
      await expectLater(register(disabled), throwsStateError);
      final enabled = WorkPhotoRepository(
        enabled: true,
        call: (name, input) async {
          calls++;
          return {};
        },
      );
      await expectLater(
        register(
          enabled,
          actor: const AppUser(uid: 'admin', role: UserRole.admin),
        ),
        throwsStateError,
      );
      await expectLater(
        enabled.register(
          user: user,
          date: '2026-11-14',
          period: TransportPeriod.morning,
          routeId: 'route',
          kind: WorkPhotoKind.start,
          photo: bytes,
        ),
        throwsStateError,
      );
      expect(calls, 0);
    },
  );
  test('admin summary pages never download images; photo lookup uses the existing protected Callable', () async {
    final requests = <Map<String, dynamic>>[];
    final repo = WorkPhotoRepository(
      enabled: true,
      call: (name, input) async {
        expect(name, 'getWorkPhotos');
        requests.add(input);
        if (input.containsKey('recordId')) return record();
        return {
          'records': [record()..remove('photoBase64')],
          'nextCursor': null,
        };
      },
    );
    final summaries = await repo.summaries(
      's1',
      '2026-11-14',
      TransportPeriod.morning,
    );
    expect(requests.length, 1);
    expect(requests.single.containsKey('recordId'), false);
    expect(summaries.single.koreaTime, '2026-11-14 09:01:02');
    expect(await repo.photo(summaries.single), bytes);
    expect(requests.last['recordId'], 'record');
  });
  test(
    'summary pagination is complete and wrong employee results fail closed',
    () async {
      var pages = 0;
      final repo = WorkPhotoRepository(
        enabled: true,
        call: (name, input) async {
          expect(input.containsKey('recordId'), false);
          pages++;
          return input['cursor'] == null
              ? {
                  'records': [record()..remove('photoBase64')],
                  'nextCursor': 'next',
                }
              : {'records': [], 'nextCursor': null};
        },
      );
      expect(
        await repo.summaries('s1', '2026-11-14', TransportPeriod.morning),
        hasLength(1),
      );
      expect(pages, 2);
      await expectLater(
        repo.summaries('s2', '2026-11-14', TransportPeriod.morning),
        throwsStateError,
      );
    },
  );
  test('one explicit attempt, same request ID after uncertain failure, server time and private byte lookup', () async {
    final requests = <Map<String, dynamic>>[];
    var fail = true;
    final repo = WorkPhotoRepository(
      enabled: true,
      call: (name, input) async {
        if (name == 'registerWorkPhoto') {
          requests.add(input);
          if (fail) throw StateError('network');
          return {'recordId': 'record'};
        }
        expect(name, 'getWorkPhotos');
        expect(input['recordId'], 'record');
        return record();
      },
    );
    await expectLater(register(repo), throwsStateError);
    expect(requests.length, 1);
    fail = false;
    final saved = await register(repo);
    expect(requests.length, 2);
    expect(requests[0]['requestId'], requests[1]['requestId']);
    expect(requests[0]['expectedVersion'], 3);
    expect(requests[0]['expectedAvailabilityVersion'], 2);
    expect(requests[0].containsKey('staffId'), false);
    expect(requests[0].containsKey('uid'), false);
    expect(saved.koreaTime, '2026-11-14 09:01:02');
    expect(saved.photo, bytes);
  });
  test('read failure remains an error; explicit refresh can recover without registering', () async {
    var fail = true, uploads = 0;
    final repo = WorkPhotoRepository(
      enabled: true,
      call: (name, input) async {
        if (name == 'registerWorkPhoto') uploads++;
        if (fail) throw StateError('network');
        if (input.containsKey('recordId')) return record();
        return {
          'records': [
            {'recordId': 'record'},
          ],
          'nextCursor': null,
        };
      },
    );
    final errors = <Object>[];
    final done = Completer<List<AttendanceRecord>>();
    final sub = repo
        .watch('s1', '2026-11-14', TransportPeriod.morning)
        .listen(
          done.complete,
          onError: (Object e) {
            errors.add(e);
          },
        );
    await Future<void>.delayed(Duration.zero);
    expect(errors.length, 1);
    fail = false;
    repo.refresh();
    expect((await done.future).single.staffId, 's1');
    expect(uploads, 0);
    await sub.cancel();
  });
}
