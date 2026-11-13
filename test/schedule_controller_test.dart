import 'support/fixtures.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/data/demo_data.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';

void main() {
  late ScheduleController c;
  setUp(
    () => c = fixtureController(
      user: const AppUser(uid: 'fictional-admin', role: UserRole.admin),
      initialDate: DateTime(2026, 11, 12),
    ),
  );
  tearDown(() => c.dispose());

  test('기본 코스에서 날짜별 초안을 생성하며 직원에게 미확정본을 숨긴다', () {
    expect(c.draft.routes.length, 2);
    expect(c.validationErrors, isEmpty);
    expect(c.confirmed, isNull);
    expect(c.staffRoutes, isEmpty);
  });

  test('결석은 선택한 날짜·시간대에만 적용되며 기본 코스를 유지한다', () {
    c.markAbsent('p2');
    expect(c.draft.routes.first.passengerIds, ['p1', 'p3']);
    expect(c.draft.absentIds, {'p2'});
    expect(DemoData.baseRoutes.first.passengerIds, ['p1', 'p2', 'p3']);
    c.selectPeriod(TransportPeriod.afternoon);
    expect(c.draft.absentIds, isEmpty);
    expect(c.draft.routes.first.passengerIds, contains('p2'));
    c.selectPeriod(TransportPeriod.morning);
    c.selectDate(DateTime(2026, 11, 13));
    expect(c.draft.routes.first.passengerIds, ['p1', 'p2', 'p3']);
    c.selectDate(DateTime(2026, 11, 12));
    expect(c.draft.routes.first.passengerIds, ['p1', 'p3']);
  });

  test('코스 이동과 순서 변경은 누락·중복 없이 동작한다', () {
    c.markAbsent('p2');
    c.movePassenger('p4', 'morning-a');
    c.reorder('morning-a', 2, -1);
    expect(c.draft.routes.first.passengerIds, ['p1', 'p4', 'p3']);
    expect(c.draft.routes.last.passengerIds, ['p5']);
    expect(c.validationErrors, isEmpty);
    c.restorePassenger('p2');
    expect(c.draft.absentIds, isEmpty);
    expect(c.validationErrors.join(), contains('정원'));
  });

  test('확정본은 수정 중에도 유지되고 재확정 시에만 교체된다', () {
    c.confirm();
    final previous = c.confirmed;
    c.markAbsent('p2');
    expect(c.confirmed!.routes.first.passengerIds, contains('p2'));
    expect(c.confirmed, same(previous));
    keepReviewedTimes(c);
    c.confirm();
    expect(c.confirmed!.version, 2);
    expect(c.confirmed!.routes.first.passengerIds, ['p1', 'p3']);
    expect(previous!.routes.first.passengerIds, ['p1', 'p2', 'p3']);
    expect(c.hasPendingChanges, isFalse);
  });

  test('정원 초과 시 확정을 막고 기존 확정본을 보존한다', () {
    c.confirm();
    final previous = c.confirmed;
    c.movePassenger('p4', 'morning-a');
    expect(c.validationErrors.join(), contains('정원'));
    expect(c.confirm, throwsStateError);
    expect(c.confirmed, same(previous));
  });

  test('직원·차량 중복과 근무 불가를 검증한다', () {
    c.assign('morning-b', staffId: 's1', vehicleId: 'v1');
    expect(c.validationErrors.join(), contains('직원이 같은 시간대에 중복'));
    expect(c.validationErrors.join(), contains('차량이 같은 시간대에 중복'));
    expect(c.confirm, throwsStateError);
    c.selectDate(DateTime(2026, 11, 13));
    c.assign('morning-a', staffId: 's3');
    expect(c.validationErrors.join(), contains('근무할 수 없습니다'));
    expect(c.confirm, throwsStateError);
  });

  test('이용자 중복·누락·결석자 포함·잘못된 참조를 검증한다', () {
    final first = c.draft.routes.first;
    final last = c.draft.routes.last;
    final invalid = c.draft.copyWith(
      absentIds: {'p1', 'unknown'},
      routes: [
        first.copyWith(
          staffId: 'unknown',
          vehicleId: 'unknown',
          passengerIds: ['p1', 'p1', 'unknown'],
        ),
        last,
      ],
    );
    final errors = c.validate(invalid).join();
    expect(errors, contains('존재하지 않는 직원'));
    expect(errors, contains('존재하지 않는 차량'));
    expect(errors, contains('이용자가 중복'));
    expect(errors, contains('결석한 이용자'));
    expect(errors, contains('누락'));
    expect(errors, contains('없는 이용자'));
    expect(
      c.validate(c.draft.copyWith(routes: [last])).join(),
      contains('기본 코스가 누락'),
    );
  });

  test('직원 역할에서는 모든 일정 변경 및 확정을 차단한다', () {
    c.dispose();
    c = fixtureController(
      user: const AppUser(
        uid: 'fictional-staff',
        role: UserRole.staff,
        staffId: 's1',
      ),
    );
    expect(() => c.markAbsent('p1'), throwsStateError);
    expect(() => c.restorePassenger('p1'), throwsStateError);
    expect(() => c.movePassenger('p1', 'morning-b'), throwsStateError);
    expect(() => c.reorder('morning-a', 0, 1), throwsStateError);
    expect(() => c.assign('morning-a', staffId: 's3'), throwsStateError);
    expect(c.confirm, throwsStateError);
  });

  test('기본 코스와 일정의 목록을 외부에서 변경할 수 없다', () {
    expect(() => c.draft.routes.clear(), throwsUnsupportedError);
    expect(
      () => c.draft.routes.first.passengerIds.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => DemoData.baseRoutes.first.passengerIds.clear(),
      throwsUnsupportedError,
    );
  });

  test('직원 간 재배정은 예상 시각을 보존하고 검토 후 전체 변경을 함께 확정한다', () {
    c.setVisitMinute('morning-b', 'p4', 490);
    c.markAbsent('p2');
    c.movePassenger('p4', 'morning-a');
    expect(c.routesForStaff('s1').single.passengerIds, ['p1', 'p3', 'p4']);
    expect(c.routesForStaff('s2').single.passengerIds, ['p5']);
    expect(c.draft.routes.first.estimatedVisitMinutes['p4'], 490);
    expect(c.validationErrors, isEmpty);
    keepReviewedTimes(c);
    c.confirm();
    expect(c.confirmed!.routes.first.passengerIds, ['p1', 'p3', 'p4']);
    expect(c.confirmed!.routes.last.passengerIds, ['p5']);
    expect(DemoData.baseRoutes.first.passengerIds, ['p1', 'p2', 'p3']);
  });

  test('제외와 결석을 구분하며 원하는 직원에게 중복 없이 복귀시킨다', () {
    c.excludePassenger('p2');
    expect(c.draft.excludedIds, {'p2'});
    expect(c.draft.absentIds, isEmpty);
    expect(c.validationErrors, isEmpty);
    c.addPassenger('p2', 'morning-b');
    expect(c.draft.excludedIds, isEmpty);
    expect(c.draft.routes.last.passengerIds, ['p4', 'p5', 'p2']);
    c.addPassenger('p2', 'morning-b');
    expect(
      c.draft.routes.last.passengerIds.where((id) => id == 'p2').length,
      1,
    );
    expect(c.validationErrors, isEmpty);
  });

  test('예상 시각은 날짜·시간대별로 보존되고 순서 역전·범위 이탈을 차단한다', () {
    c.setOperatingWindow('morning-a', 480, 570);
    c.setVisitMinute('morning-a', 'p1', 490);
    c.setVisitMinute('morning-a', 'p2', 500);
    c.setVisitMinute('morning-a', 'p3', 510);
    c.confirm();
    final previous = c.confirmed;
    c.reorder('morning-a', 0, 1);
    expect(c.validationErrors.join(), contains('예상 방문 시각이 충돌'));
    expect(c.confirm, throwsStateError);
    expect(c.confirmed, same(previous));
    c.reorder('morning-a', 0, 1);
    c.setVisitMinute('morning-a', 'p3', 600);
    expect(c.validationErrors.join(), contains('운행 시간 범위'));
    c.setVisitMinute('morning-a', 'p3', null);
    expect(c.validationErrors, isEmpty);
    c.selectPeriod(TransportPeriod.afternoon);
    expect(c.draft.routes.first.estimatedVisitMinutes, isEmpty);
    c.selectPeriod(TransportPeriod.morning);
    expect(c.draft.routes.first.estimatedVisitMinutes['p1'], 490);
    expect(
      () => c.draft.routes.first.estimatedVisitMinutes.clear(),
      throwsUnsupportedError,
    );
    c.selectDate(DateTime(2026, 11, 13));
    expect(c.draft.routes.first.startMinute, isNull);
  });

  test('직원은 예상 시각 수정·추가·제외도 수행할 수 없다', () {
    final staffController = fixtureController(
      user: const AppUser(
        uid: 'fictional-staff',
        role: UserRole.staff,
        staffId: 's1',
      ),
    );
    addTearDown(staffController.dispose);
    expect(
      () => staffController.setVisitMinute('morning-a', 'p1', 490),
      throwsStateError,
    );
    expect(
      () => staffController.setOperatingWindow('morning-a', 480, 570),
      throwsStateError,
    );
    expect(() => staffController.excludePassenger('p1'), throwsStateError);
    expect(
      () => staffController.addPassenger('p4', 'morning-a'),
      throwsStateError,
    );
  });
}
