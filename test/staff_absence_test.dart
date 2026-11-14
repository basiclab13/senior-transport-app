import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/staff_absence.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';
import 'package:senior_transport_app/services/schedule_repository.dart';
import 'package:senior_transport_app/services/staff_availability_diagnostics.dart';

import 'support/fixtures.dart';

class AbsenceRepository extends MemoryScheduleRepository
    implements StaffAvailabilityRepository {
  final days = <String, Map<String, StaffAbsence>>{};
  final availabilityChanges = StreamController<String>.broadcast();
  final receipts = <String, StaffAbsence>{};
  final absenceRequests = <Map<String, dynamic>>[];
  final publishVersions = <Map<String, int>>[];
  bool loseResponse = false;
  bool failAvailability = false;
  Object? availabilityFailure;
  bool controlledAvailability = false;
  final availabilityEvents =
      StreamController<Map<String, StaffAbsence>>.broadcast();
  Completer<void>? absenceHold;

  @override
  Stream<Map<String, StaffAbsence>> watchAbsences(
    AppUser user,
    DateTime date,
  ) async* {
    if (controlledAvailability) {
      yield* availabilityEvents.stream;
      return;
    }
    final day = dateKey(date);
    Map<String, StaffAbsence> values() => {
      for (final entry in (days[day] ?? <String, StaffAbsence>{}).entries)
        if (user.role == UserRole.admin || user.staffId == entry.key)
          entry.key: entry.value,
    };
    if (failAvailability) throw StateError('offline');
    if (availabilityFailure != null) throw availabilityFailure!;
    yield values();
    yield* availabilityChanges.stream
        .where((d) => d == day)
        .map((_) => values());
  }

  @override
  Future<StaffAbsence> setAbsence(Map<String, dynamic> request) async {
    absenceRequests.add(Map.of(request));
    if (absenceHold != null) await absenceHold!.future;
    final id = request['requestId'] as String;
    if (receipts.containsKey(id)) return receipts[id]!;
    final day = days.putIfAbsent(request['date'] as String, () => {});
    final staffId = request['staffId'] as String;
    final current = day[staffId];
    if ((current?.version ?? 0) != request['expectedVersion']) {
      throw FirebaseFunctionsException(code: 'aborted', message: 'conflict');
    }
    final periods = {...?current?.periods};
    for (final name in request['periods'] as List) {
      final period = TransportPeriod.values.byName(name as String);
      if (request['absent'] == true) {
        periods.add(period);
      } else {
        periods.remove(period);
      }
    }
    final result = StaffAbsence(
      staffId: staffId,
      periods: periods,
      version: (current?.version ?? 0) + 1,
    );
    day[staffId] = result;
    receipts[id] = result;
    availabilityChanges.add(request['date'] as String);
    if (loseResponse) {
      throw FirebaseFunctionsException(
        code: 'unavailable',
        message: 'lost acknowledgement',
      );
    }
    return result;
  }

  @override
  Future<void> publishWithAvailability(
    ScheduleSnapshot snapshot,
    String catalogVersion,
    int expectedVersion,
    String requestId,
    Map<String, int> versions,
  ) {
    publishVersions.add(Map.of(versions));
    return publish(snapshot, catalogVersion, expectedVersion, requestId);
  }
}

void main() {
  const admin = AppUser(uid: 'admin', role: UserRole.admin);
  const employee = AppUser(uid: 'staff', role: UserRole.staff, staffId: 's1');
  const am = TransportPeriod.morning;
  const pm = TransportPeriod.afternoon;
  late AbsenceRepository repo;
  late ScheduleController c;
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  ScheduleController controller([AppUser user = admin]) =>
      ScheduleController.remote(
        user: user,
        repository: repo,
        clock: fixtureClock,
      );
  setUp(() async {
    repo = AbsenceRepository();
    c = controller();
    await settle();
  });
  tearDown(() async {
    c.dispose();
    await repo.changes.close();
    await repo.availabilityChanges.close();
    await repo.availabilityEvents.close();
  });

  test('empty server collection or missing own document is verified absence, not a lookup failure', () {
    final values = decodeStaffAvailability(
      '2026-11-12',
      {},
      isFromCache: false,
      hasPendingWrites: false,
    );
    expect(values, isEmpty);
  });

  test('cache and pending writes never become a verified empty result', () {
    for (final flags in [(true, false), (false, true), (true, true)]) {
      expect(
        () => decodeStaffAvailability(
          '2026-11-12',
          {},
          isFromCache: flags.$1,
          hasPendingWrites: flags.$2,
        ),
        throwsA(isA<StaffAvailabilityUnverified>()),
      );
    }
  });

  test('malformed server documents do not fall back to absence of records', () {
    expect(
      () => decodeStaffAvailability(
        '2026-11-12',
        {
          's1': {'role': 'staff'},
        },
        isFromCache: false,
        hasPendingWrites: false,
      ),
      throwsFormatException,
    );
  });

  for (final code in ['permission-denied', 'unavailable', 'unauthenticated']) {
    test(
      'lookup $code logs the original Firebase type/code/message and blocks confirmation',
      () async {
        c.dispose();
        repo.availabilityFailure = FirebaseException(
          plugin: 'cloud_firestore',
          code: code,
          message: 'diagnostic Firebase message',
        );
        final logs = <String>[];
        c = ScheduleController.remote(
          user: admin,
          repository: repo,
          clock: fixtureClock,
          diagnosticLogger: logs.add,
        );
        await settle();
        expect(c.availabilityLoading, isFalse);
        expect(c.availabilityError, isNotNull);
        expect(
          logs.singleWhere((l) => l.contains('read_failed')),
          allOf(
            contains('type=FirebaseException'),
            contains('code=$code'),
            contains('message=diagnostic Firebase message'),
          ),
        );
        if (code == 'permission-denied') {
          expect(c.availabilityError, contains('게시된 Firestore Rules'));
        }
        await expectLater(c.publish(), throwsStateError);
        expect(repo.requests, isEmpty);
      },
    );
  }

  test('format failure logs the type without the document source and remains blocked', () async {
    c.dispose();
    repo.availabilityFailure = const FormatException('Invalid staff absence', {
      'name': 'private fixture data',
    });
    final logs = <String>[];
    c = ScheduleController.remote(
      user: admin,
      repository: repo,
      clock: fixtureClock,
      diagnosticLogger: logs.add,
    );
    await settle();
    expect(c.availabilityError, contains('형식'));
    expect(
      logs.join(),
      allOf(
        contains('FormatException'),
        contains('Invalid staff absence'),
        isNot(contains('private fixture data')),
      ),
    );
    await expectLater(c.publish(), throwsStateError);
  });

  testWidgets(
    'initial cache waits for the server; server empty clears waiting without an error',
    (tester) async {
      c.dispose();
      repo.controlledAvailability = true;
      final logs = <String>[];
      c = ScheduleController.remote(
        user: admin,
        repository: repo,
        clock: fixtureClock,
        diagnosticLogger: logs.add,
      );
      await tester.pump();
      repo.availabilityEvents.addError(
        const StaffAvailabilityUnverified(pendingWrites: false),
      );
      await tester.pump();
      expect(c.availabilityLoading, isTrue);
      expect(c.availabilityError, isNull);
      await expectLater(c.publish(), throwsStateError);
      repo.availabilityEvents.add({});
      await tester.pump();
      expect(c.availabilityLoading, isFalse);
      expect(c.availabilityError, isNull);
      expect(logs.join(), contains('state=verified-empty'));
      expect(await c.publish(), isTrue);
    },
  );

  testWidgets(
    'server verification timeout blocks confirmation and a later server result recovers',
    (tester) async {
      c.dispose();
      repo.controlledAvailability = true;
      c = ScheduleController.remote(
        user: admin,
        repository: repo,
        clock: fixtureClock,
      );
      await tester.pump(ScheduleController.availabilityVerificationTimeout);
      expect(c.availabilityLoading, isFalse);
      expect(c.availabilityError, contains('시간이 초과'));
      await expectLater(c.publish(), throwsStateError);
      repo.availabilityEvents.add({});
      await tester.pump();
      expect(c.availabilityError, isNull);
      expect(c.availabilityLoading, isFalse);
    },
  );

  testWidgets(
    'cache after a verified read revokes confirmation readiness until reverified',
    (tester) async {
      c.dispose();
      repo.controlledAvailability = true;
      c = ScheduleController.remote(
        user: admin,
        repository: repo,
        clock: fixtureClock,
      );
      await tester.pump();
      repo.availabilityEvents.add({});
      await tester.pump();
      expect(c.availabilityLoading, isFalse);
      repo.availabilityEvents.addError(
        const StaffAvailabilityUnverified(pendingWrites: false),
      );
      await tester.pump();
      expect(c.availabilityLoading, isTrue);
      await expectLater(c.publish(), throwsStateError);
      repo.availabilityEvents.addError(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
          message: 'network offline',
        ),
      );
      await tester.pump();
      expect(c.availabilityLoading, isFalse);
      expect(c.availabilityError, contains('네트워크'));
      await expectLater(c.publish(), throwsStateError);
      repo.availabilityEvents.add({});
      await tester.pump();
      expect(c.availabilityError, isNull);
    },
  );

  test('morning, afternoon and whole-day cancellation survive reload and preserve other days', () async {
    expect(await c.setStaffAbsence('s1', {am}, true, 0), isTrue);
    expect(c.isStaffAbsent('s1'), isTrue);
    expect(c.reassignmentNeeded, isTrue);
    expect(await c.setStaffAbsence('s1', {pm}, true, 1), isTrue);
    c.selectDate(DateTime(2026, 11, 13));
    await settle();
    expect(c.isStaffAbsent('s1'), isFalse);
    await c.setStaffAbsence('s1', {am, pm}, true, 0);
    c.selectDate(DateTime(2026, 11, 12));
    await settle();
    await c.setStaffAbsence('s1', {am}, false, 2);
    expect(c.isStaffAbsent('s1'), isFalse);
    c.selectPeriod(pm);
    await settle();
    expect(c.isStaffAbsent('s1'), isTrue);
    await c.setStaffAbsence('s1', {am, pm}, false, 3);
    c.dispose();
    c = controller();
    await settle();
    expect(c.absences['s1']!.version, 4);
    expect(c.absences['s1']!.periods, isEmpty);
    expect(repo.days['2026-11-13']!['s1']!.periods, {am, pm});
    expect(c.staff('s1').isAvailable(c.selectedDate, am), isTrue);
  });

  test(
    'absence stream preserves unsaved edits and blocks confirming absent staff',
    () async {
      c.markAbsent('p2');
      final draft = c.draft;
      await c.setStaffAbsence('s1', {am}, true, 0);
      await settle();
      expect(c.draft, same(draft));
      expect(c.hasPendingChanges, isTrue);
      expect(c.validationErrors.any((e) => e.contains('결근 직원')), isTrue);
      expect(await c.publish(), isFalse);
      expect(repo.requests, isEmpty);
    },
  );

  test('existing confirmation remains history after absence and reload, cancellation restores usability', () async {
    expect(await c.publish(), isTrue);
    final confirmed = c.confirmed;
    await c.setStaffAbsence('s1', {am}, true, 0);
    expect(c.confirmedReassignmentNeeded, isTrue);
    expect(c.confirmed, same(confirmed));
    expect(c.hasPendingChanges, isFalse);
    c.retryLoad();
    await settle();
    expect(c.dataError, isNull);
    expect(c.confirmedReassignmentNeeded, isTrue);
    await c.setStaffAbsence('s1', {am}, false, 1);
    expect(c.confirmedReassignmentNeeded, isFalse);
    expect(c.validationErrors, isEmpty);
  });

  test('stale administrator dialog version is rejected without replacing latest status', () async {
    await c.setStaffAbsence('s1', {am}, true, 0);
    expect(await c.setStaffAbsence('s1', {pm}, true, 0), isFalse);
    expect(c.absences['s1']!.periods, {am});
    expect(c.absenceError, contains('다른 관리자'));
  });

  test('lost absence acknowledgement retries the original request id without duplicate changes', () async {
    repo.loseResponse = true;
    expect(await c.setStaffAbsence('s1', {am}, true, 0), isFalse);
    await settle();
    expect(c.absences['s1']!.version, 1);
    repo.loseResponse = false;
    expect(await c.setStaffAbsence('s1', {am}, true, 1), isTrue);
    expect(repo.absenceRequests.map((r) => r['requestId']).toSet().length, 1);
    expect(c.absences['s1']!.version, 1);
  });

  test(
    'absence save locks date and draft mutations until acknowledgement',
    () async {
      repo.absenceHold = Completer<void>();
      final saving = c.setStaffAbsence('s1', {am, pm}, true, 0);
      expect(c.absenceSaving, isTrue);
      c.selectPeriod(pm);
      expect(c.period, am);
      expect(() => c.markAbsent('p1'), throwsStateError);
      repo.absenceHold!.complete();
      await saving;
      expect(c.absenceSaving, isFalse);
    },
  );

  test('availability lookup failure fails closed without manufacturing a normal confirmation', () async {
    repo.failAvailability = true;
    c.retryLoad();
    await settle();
    expect(c.availabilityError, isNotNull);
    await expectLater(c.publish(), throwsStateError);
    repo.failAvailability = false;
    c.retryLoad();
    await settle();
    expect(c.availabilityError, isNull);
  });

  test('confirmation sends reviewed absence versions and preserves them for uncertain retries', () async {
    await c.setStaffAbsence('s1', {pm}, true, 0);
    repo.publishFailure = FirebaseFunctionsException(
      code: 'unavailable',
      message: 'offline',
    );
    expect(await c.publish(), isFalse);
    await c.setStaffAbsence('s1', {pm}, false, 1);
    expect(await c.publish(), isFalse);
    expect(repo.publishVersions[0]['s1'], 1);
    expect(repo.publishVersions[1], repo.publishVersions[0]);
    expect(repo.requests.toSet().length, 1);
  });

  test('staff sees own absence but cannot register or cancel it', () async {
    await c.publish();
    await c.setStaffAbsence('s1', {am}, true, 0);
    final staff = controller(employee);
    await settle();
    expect(staff.isStaffAbsent('s1'), isTrue);
    expect(staff.confirmedReassignmentNeeded, isTrue);
    await expectLater(
      staff.setStaffAbsence('s1', {am}, false, 1),
      throwsStateError,
    );
    staff.dispose();
  });

  test('malformed Firestore absence payload is rejected', () {
    for (final data in [
      {
        'version': 1,
        'unavailablePeriods': ['morning', 'morning'],
      },
      {
        'version': 1,
        'unavailablePeriods': ['other'],
      },
      {'version': '1', 'unavailablePeriods': []},
    ]) {
      expect(() => StaffAbsence.fromJson('s1', data), throwsFormatException);
    }
    expect(
      () => StaffAbsence.fromJson('s1', {
        'schemaVersion': 1,
        'date': '2026-11-12',
        'staffId': 's2',
        'version': 1,
        'unavailablePeriods': [],
      }, date: '2026-11-12'),
      throwsFormatException,
    );
  });

  Future<void> open(WidgetTester tester) async {
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
  }

  testWidgets(
    'admin registers all-day absence, sees list/overview warning and cancels in detail',
    (tester) async {
      await open(tester);
      await openStaffInfo(tester, 's1');
      await tester.tap(find.byKey(const ValueKey('staff-absence-s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('종일'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('register-staff-absence')));
      await tester.pumpAndSettle();
      expect(c.absences['s1']!.periods, {am, pm});
      expect(find.byKey(const Key('staff-absence-warning')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('staff-s1')),
          matching: find.textContaining('다른 직원 배정 필요'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('admin-overview')));
      await tester.pumpAndSettle();
      expect(find.text('해결할 문제'), findsOneWidget);
      expect(find.textContaining('다른 직원에게 코스를 넘겨주세요.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('admin-editor')));
      await tester.pumpAndSettle();
      await openStaffInfo(tester, 's1');
      await tester.tap(find.byKey(const ValueKey('staff-absence-s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('종일'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancel-staff-absence')));
      await tester.pumpAndSettle();
      expect(c.absences['s1']!.periods, isEmpty);
      expect(find.byKey(const Key('staff-absence-warning')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('absence dialog and status fit a small administrator screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
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
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('dashboard-staff-s1')),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dashboard-staff-s1')));
    await tester.pumpAndSettle();
    await openStaffInfo(tester, 's1');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('staff-absence-s1')),
      80,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('staff-absence-s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('종일'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('register-staff-absence')));
    await tester.pumpAndSettle();
    expect(c.absences['s1']!.periods, {am, pm});
    expect(find.byKey(const Key('staff-absence-warning')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'previously confirmed staff schedule is explicitly marked non-operational without edit actions',
    (tester) async {
      await c.publish();
      await c.setStaffAbsence('s1', {am}, true, 0);
      final staff = controller(employee);
      await tester.pump();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleScreen(
            user: employee,
            controller: staff,
            onSignOut: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('staff-absence-warning')), findsOneWidget);
      expect(find.textContaining('결근으로 등록되어 있습니다'), findsOneWidget);
      expect(find.byKey(const ValueKey('staff-absence-s1')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      staff.dispose();
    },
  );
}
