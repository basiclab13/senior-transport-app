import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';
import 'package:senior_transport_app/services/schedule_repository.dart';

import 'support/fixtures.dart';

class MissingDataRepository extends MemoryScheduleRepository {
  @override
  Stream<ScheduleViewData> watch(
    AppUser user,
    DateTime date,
    TransportPeriod period,
  ) => Stream.error(StateError('Missing Firestore catalog'));
}

void main() {
  const admin = AppUser(uid: 'fictional-admin', role: UserRole.admin);
  late MemoryScheduleRepository repository;
  late ScheduleController c;
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  setUp(() async {
    repository = MemoryScheduleRepository();
    c = ScheduleController.remote(
      user: admin,
      repository: repository,
      clock: fixtureClock,
    );
    await settle();
  });
  tearDown(() async {
    c.dispose();
    await repository.changes.close();
  });

  test('save failure preserves draft and reuses request ID on retry', () async {
    c.markAbsent('p2');
    final edited = c.draft;
    repository.publishFailure = FirebaseFunctionsException(
      code: 'unavailable',
      message: 'offline',
    );
    expect(await c.publish(), isFalse);
    expect(c.draft, same(edited));
    expect(c.confirmed, isNull);
    expect(c.hasPendingChanges, isTrue);
    expect(c.saveError, isNotNull);
    repository.publishFailure = null;
    expect(await c.publish(), isTrue);
    expect(repository.requests.length, 2);
    expect(repository.requests.toSet().length, 1);
    expect(c.confirmed!.version, 1);
    expect(c.hasPendingChanges, isFalse);
  });

  test(
    'another admin update preserves local edits and blocks blind overwrite',
    () async {
      c.markAbsent('p2');
      final edited = c.draft;
      final latest = edited.copyWith(version: 1, confirmedAt: DateTime.now());
      repository.snapshots[repository.key(c.selectedDate, c.period)] = latest;
      repository.changes.add(ScheduleViewData(demoCatalog(), latest));
      await settle();
      expect(c.conflict, isTrue);
      expect(c.draft, same(edited));
      expect(await c.publish(), isFalse);
      expect(repository.requests, isEmpty);
      await c.reloadDiscardingDraft();
      expect(c.conflict, isFalse);
      expect(c.draft, same(latest));
      expect(c.hasPendingChanges, isFalse);
    },
  );

  test(
    'saving locks mutations/date changes until server acknowledgement',
    () async {
      c.markAbsent('p2');
      repository.hold = Completer<void>();
      final save = c.publish();
      expect(c.saving, isTrue);
      final previousPeriod = c.period;
      c.selectPeriod(TransportPeriod.afternoon);
      expect(c.period, previousPeriod);
      expect(() => c.assign('morning-a', staffId: 's3'), throwsStateError);
      expect(awaitLater(c.publish()), completion(isFalse));
      repository.hold!.complete();
      expect(await save, isTrue);
      expect(c.saving, isFalse);
    },
  );

  test(
    'Firestore load failure does not synthesize a local demo catalog',
    () async {
      final missing = MissingDataRepository();
      final controller = ScheduleController.remote(
        user: admin,
        repository: missing,
      );
      addTearDown(controller.dispose);
      addTearDown(missing.changes.close);
      await settle();
      expect(controller.loading, isFalse);
      expect(controller.dataError, isNotNull);
      expect(controller.catalog.staff, isEmpty);
      expect(controller.catalog.baseRoutes, isEmpty);
    },
  );

  test('lost response is resolved only by a server commit receipt', () async {
    c.markAbsent('p2');
    repository.snapshots[repository.key(c.selectedDate, c.period)] = c.draft
        .copyWith(version: 1, confirmedAt: DateTime.now());
    repository.receipt = true;
    repository.publishFailure = FirebaseFunctionsException(
      code: 'unavailable',
      message: 'lost response',
    );
    expect(await c.publish(), isTrue);
    expect(c.confirmed!.version, 1);
    expect(c.hasPendingChanges, isFalse);
    expect(c.saveError, isNull);
  });

  test(
    'own realtime commit is not mistaken for another administrator conflict',
    () async {
      c.markAbsent('p2');
      repository.hold = Completer<void>();
      final publish = c.publish();
      repository.changes.add(
        ScheduleViewData(
          demoCatalog(),
          c.draft.copyWith(version: 1, confirmedAt: DateTime.now()),
          lastRequestId: repository.requests.single,
        ),
      );
      await settle();
      expect(c.conflict, isFalse);
      repository.hold!.complete();
      expect(await publish, isTrue);
    },
  );

  test('date/period-specific edits survive navigation without mixing catalog versions', () async {
    c.markAbsent('p2');
    final date = c.selectedDate;
    c.selectPeriod(TransportPeriod.afternoon);
    await settle();
    expect(c.draft.absentIds, isEmpty);
    c.selectPeriod(TransportPeriod.morning);
    await settle();
    expect(c.draft.absentIds, {'p2'});
    expect(c.catalog.version, 'test-v1');
    c.selectDate(date.add(const Duration(days: 1)));
    await settle();
    expect(c.draft.absentIds, isEmpty);
    expect(c.confirmed, isNull);
  });
}

Future<bool> awaitLater(Future<bool> future) async {
  try {
    return await future;
  } on StateError {
    return false;
  }
}
