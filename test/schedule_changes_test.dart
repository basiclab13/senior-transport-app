import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/schedule_changes.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';
import 'package:senior_transport_app/utils/staff_sort.dart';

import 'support/fixtures.dart';

void main() {
  late ScheduleController c;
  setUp(
    () => c = fixtureController(
      user: const AppUser(uid: 'fictional-admin', role: UserRole.admin),
      initialDate: DateTime(2026, 11, 12),
    ),
  );
  tearDown(() => c.dispose());
  ScheduleChanges changes(ScheduleSnapshot before) =>
      ScheduleChanges.compare(before, c.draft, c.catalog);

  test('natural employee names and duplicate-name tie breaks do not depend on document ID order', () {
    final staff = [
      const Staff('s1', '직원 10'),
      const Staff('s10', '직원 2'),
      const Staff('s2', '직원 1'),
    ];
    staff.sort(compareStaffNames);
    expect(staff.map((s) => s.name), ['직원 1', '직원 2', '직원 10']);
    expect(
      compareStaffNames(const Staff('s2', '김다정'), const Staff('s10', '김다정')),
      lessThan(0),
    );
    expect(
      compareNaturalNames(
        '직원 999999999999999999999',
        '직원 1000000000000000000000',
      ),
      lessThan(0),
    );
    expect(compareNaturalNames('직원 2팀 3', '직원 2팀 10'), lessThan(0));
    expect(compareNaturalNames('김다정', '박여유'), lessThan(0));
  });

  test('first confirmation and no semantic changes are distinct; version metadata is ignored', () {
    expect(ScheduleChanges.compare(null, c.draft, c.catalog).initial, isTrue);
    c.confirm();
    final before = c.confirmed!;
    final result = ScheduleChanges.compare(
      before,
      before.copyWith(version: 99, confirmedAt: DateTime(2030)),
      c.catalog,
    );
    expect(result.initial, isFalse);
    expect(result.items, isEmpty);
  });

  test('transfer, absence, exclusion and vehicle changes preserve visit estimates without false order changes', () {
    c.setVisitMinute('morning-a', 'p1', 490);
    c.confirm();
    final before = c.confirmed!;
    c.movePassenger('p1', 'morning-b');
    c.markAbsent('p2');
    c.excludePassenger('p5');
    c.assign('morning-a', vehicleId: 'v3');
    final result = changes(before);
    expect(
      result.items.map((i) => i.kind),
      containsAll([
        ScheduleChangeKind.assignment,
        ScheduleChangeKind.absence,
        ScheduleChangeKind.exclusion,
        ScheduleChangeKind.vehicle,
      ]),
    );
    expect(
      result.items.any((i) => i.kind == ScheduleChangeKind.order),
      isFalse,
    );
    expect(
      result.items.any(
        (i) => i.description.contains('김다정 · 햇살 A코스 → 이온유 · 나무 B코스'),
      ),
      isTrue,
    );
    expect(
      result.items.any((i) => i.description.contains('08:10 → 미입력')),
      isFalse,
    );
    expect(before.routes.first.passengerIds, ['p1', 'p2', 'p3']);
    expect(before.absentIds, isEmpty);
    expect(before.excludedIds, isEmpty);
  });

  test(
    'relative visit order changes include readable before and after sequences',
    () {
      c.confirm();
      final before = c.confirmed!;
      c.reorder('morning-a', 0, 1);
      final result = changes(before);
      expect(result.items.single.kind, ScheduleChangeKind.order);
      expect(
        result.items.single.description,
        contains('이전: 가상 어르신 A → 가상 어르신 B'),
      );
      expect(
        result.items.single.description,
        contains('변경: 가상 어르신 B → 가상 어르신 A'),
      );
    },
  );

  test('course staff reassignment identifies old and new staff plus affected passengers', () {
    c.confirm();
    final before = c.confirmed!;
    c.assign('morning-a', staffId: 's3');
    final result = changes(before);
    expect(
      result.items
          .where((i) => i.kind == ScheduleChangeKind.staff)
          .single
          .description,
      contains('김다정 → 박여유'),
    );
    expect(
      result.items.where((i) => i.kind == ScheduleChangeKind.assignment).length,
      3,
    );
  });

  test('appointment edits are summarized while legacy operating records stay hidden', () {
    c.setOperatingWindow('morning-a', 480, 540);
    c.setVisitMinute('morning-a', 'p1', 490);
    c.confirm();
    final before = c.confirmed!;
    c.setOperatingWindow('morning-a', null, null);
    c.setVisitMinute('morning-a', 'p1', null);
    final result = changes(before);
    expect(
      result.items.where((i) => i.kind == ScheduleChangeKind.time).length,
      1,
    );
    expect(
      result.items.any((i) => i.description.contains('08:00–09:00 → 미입력–미입력')),
      isFalse,
    );
  });

  test('absence and exclusion restoration show status removal and restored assignments', () {
    c.markAbsent('p1');
    c.excludePassenger('p2');

    c.confirm();
    final before = c.confirmed!;
    c.restorePassenger('p1');
    c.restorePassenger('p2');
    final result = changes(before);
    expect(
      result.items.any((i) => i.description.contains('가상 어르신 A: 결석 해제')),
      isTrue,
    );
    expect(
      result.items.any((i) => i.description.contains('가상 어르신 B: 제외 해제')),
      isTrue,
    );
    expect(
      result.items.where((i) => i.kind == ScheduleChangeKind.assignment).length,
      2,
    );
  });

  test('comparison rejects a different date or time slot', () {
    c.confirm();
    final before = c.confirmed!;
    expect(
      () => ScheduleChanges.compare(
        before,
        ScheduleSnapshot(
          date: before.date,
          period: TransportPeriod.afternoon,
          routes: [],
        ),
        c.catalog,
      ),
      throwsArgumentError,
    );
  });
}
