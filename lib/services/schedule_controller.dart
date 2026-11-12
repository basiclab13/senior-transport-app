import 'package:flutter/foundation.dart';

import '../data/demo_data.dart';
import '../models/transport.dart';

class ScheduleController extends ChangeNotifier {
  ScheduleController({DateTime? initialDate}) {
    final date = initialDate ?? DateTime.now();
    selectedDate = DateTime(date.year, date.month, date.day);
    _ensureDraft();
  }

  late DateTime selectedDate;
  TransportPeriod period = TransportPeriod.morning;
  DemoRole role = DemoRole.admin;
  String staffId = 's1';
  final Map<String, ScheduleSnapshot> _drafts = {};
  final Map<String, ScheduleSnapshot> _confirmed = {};
  final Set<String> _dirty = {};

  String _key(DateTime date, TransportPeriod period) =>
      '${dateKey(date)}/${period.name}';
  String get _currentKey => _key(selectedDate, period);
  ScheduleSnapshot get draft => _drafts[_currentKey]!;
  ScheduleSnapshot? get confirmed => _confirmed[_currentKey];
  bool get hasPendingChanges => _dirty.contains(_currentKey);

  BaseRoute baseRoute(String id) =>
      DemoData.baseRoutes.firstWhere((r) => r.id == id);
  Staff staff(String id) => DemoData.staff.firstWhere((s) => s.id == id);
  Passenger passenger(String id) =>
      DemoData.passengers.firstWhere((p) => p.id == id);
  Vehicle vehicle(String id) => DemoData.vehicles.firstWhere((v) => v.id == id);

  void _ensureDraft() {
    _drafts.putIfAbsent(
      _currentKey,
      () => ScheduleSnapshot(
        date: selectedDate,
        period: period,
        routes: [
          for (final r in DemoData.baseRoutes.where((r) => r.period == period))
            RouteAssignment(
              baseRouteId: r.id,
              staffId: r.staffId,
              vehicleId: r.vehicleId,
              passengerIds: r.passengerIds,
            ),
        ],
      ),
    );
  }

  void selectDate(DateTime date) {
    selectedDate = DateTime(date.year, date.month, date.day);
    _ensureDraft();
    notifyListeners();
  }

  void selectPeriod(TransportPeriod value) {
    period = value;
    _ensureDraft();
    notifyListeners();
  }

  void selectRole(DemoRole value) {
    role = value;
    notifyListeners();
  }

  void selectStaff(String value) {
    staff(value);
    staffId = value;
    notifyListeners();
  }

  void _requireAdmin() {
    if (role != DemoRole.admin) {
      throw StateError('관리자만 일정을 수정하고 확정할 수 있습니다.');
    }
  }

  void _update(ScheduleSnapshot snapshot) {
    _requireAdmin();
    _drafts[_currentKey] = snapshot;
    _dirty.add(_currentKey);
    notifyListeners();
  }

  void markAbsent(String passengerId) {
    _requireAdmin();
    passenger(passengerId);
    if (!draft.routes.any((r) => r.passengerIds.contains(passengerId))) {
      throw StateError('현재 일정에 배정된 이용자만 결석 처리할 수 있습니다.');
    }
    _update(
      draft.copyWith(
        absentIds: {...draft.absentIds, passengerId},
        routes: [
          for (final r in draft.routes)
            r.copyWith(
              passengerIds: r.passengerIds
                  .where((id) => id != passengerId)
                  .toList(),
            ),
        ],
      ),
    );
  }

  void restorePassenger(String passengerId) {
    _requireAdmin();
    if (!draft.absentIds.contains(passengerId)) return;
    final original = DemoData.baseRoutes.firstWhere(
      (r) => r.period == period && r.passengerIds.contains(passengerId),
    );
    _update(
      draft.copyWith(
        absentIds: {...draft.absentIds}..remove(passengerId),
        routes: [
          for (final r in draft.routes)
            if (r.baseRouteId == original.id)
              r.copyWith(passengerIds: [...r.passengerIds, passengerId])
            else
              r,
        ],
      ),
    );
  }

  void movePassenger(String passengerId, String targetRouteId) {
    _requireAdmin();
    if (!draft.routes.any((r) => r.baseRouteId == targetRouteId) ||
        !draft.routes.any((r) => r.passengerIds.contains(passengerId)) ||
        draft.absentIds.contains(passengerId)) {
      throw StateError('이용자와 이동할 코스를 확인해 주세요.');
    }
    if (draft.routes
        .firstWhere((r) => r.baseRouteId == targetRouteId)
        .passengerIds
        .contains(passengerId)) {
      return;
    }
    _update(
      draft.copyWith(
        routes: [
          for (final r in draft.routes)
            r.copyWith(
              passengerIds: [
                ...r.passengerIds.where((id) => id != passengerId),
                if (r.baseRouteId == targetRouteId) passengerId,
              ],
            ),
        ],
      ),
    );
  }

  void reorder(String routeId, int index, int delta) {
    _requireAdmin();
    final route = draft.routes.firstWhere((r) => r.baseRouteId == routeId);
    final ids = [...route.passengerIds];
    final target = index + delta;
    if (index < 0 ||
        index >= ids.length ||
        target < 0 ||
        target >= ids.length) {
      return;
    }
    final id = ids.removeAt(index);
    ids.insert(target, id);
    _replaceRoute(route.copyWith(passengerIds: ids));
  }

  void assign(String routeId, {String? staffId, String? vehicleId}) {
    _requireAdmin();
    final route = draft.routes.firstWhere((r) => r.baseRouteId == routeId);
    _replaceRoute(route.copyWith(staffId: staffId, vehicleId: vehicleId));
  }

  void _replaceRoute(RouteAssignment route) => _update(
    draft.copyWith(
      routes: [
        for (final r in draft.routes)
          if (r.baseRouteId == route.baseRouteId) route else r,
      ],
    ),
  );

  /// Demo routes overlap for the entire period; sequential reuse is out of scope.
  List<String> validate(ScheduleSnapshot snapshot) {
    final errors = <String>[];
    final staffIds = <String>{};
    final vehicleIds = <String>{};
    final passengerIds = <String>{};
    final routeIds = <String>{};
    final expected = DemoData.baseRoutes.where(
      (r) => r.period == snapshot.period,
    );
    final expectedPassengers = expected.expand((r) => r.passengerIds).toSet();
    for (final id in snapshot.absentIds) {
      if (!expectedPassengers.contains(id)) {
        errors.add('대상 시간대에 없는 결석 이용자입니다: $id');
      }
    }
    for (final r in snapshot.routes) {
      final bases = expected.where((b) => b.id == r.baseRouteId);
      final label = bases.isEmpty ? r.baseRouteId : bases.first.name;
      if (bases.isEmpty) errors.add('$label: 기본 코스와 시간대를 확인해 주세요.');
      if (!routeIds.add(r.baseRouteId)) errors.add('$label: 코스가 중복되었습니다.');
      final employees = DemoData.staff.where((s) => s.id == r.staffId);
      if (employees.isEmpty) {
        errors.add('$label: 존재하지 않는 직원입니다.');
      } else if (!employees.first.isAvailable(snapshot.date, snapshot.period)) {
        errors.add('$label: ${employees.first.name} 직원은 해당 날짜에 근무할 수 없습니다.');
      }
      if (!staffIds.add(r.staffId)) {
        errors.add('$label: 직원이 같은 시간대에 중복 배정되었습니다.');
      }
      final vehicles = DemoData.vehicles.where((v) => v.id == r.vehicleId);
      if (vehicles.isEmpty) {
        errors.add('$label: 존재하지 않는 차량입니다.');
      } else if (r.passengerIds.length > vehicles.first.passengerCapacity) {
        errors.add(
          '$label: 차량 정원 ${vehicles.first.passengerCapacity}명을 초과했습니다.',
        );
      }
      if (!vehicleIds.add(r.vehicleId)) {
        errors.add('$label: 차량이 같은 시간대에 중복 배정되었습니다.');
      }
      for (final id in r.passengerIds) {
        if (!expectedPassengers.contains(id)) {
          errors.add('$label: 대상 시간대에 없는 이용자입니다: $id');
        }
        if (!passengerIds.add(id)) errors.add('$label: 이용자가 중복 배정되었습니다.');
        if (snapshot.absentIds.contains(id)) {
          errors.add('$label: 결석한 이용자가 포함되어 있습니다.');
        }
      }
    }
    if (!setEquals(routeIds, expected.map((r) => r.id).toSet())) {
      errors.add('기본 코스가 누락되었거나 다른 시간대의 코스가 포함되어 있습니다.');
    }
    if (!setEquals(
      passengerIds,
      expectedPassengers.difference(snapshot.absentIds),
    )) {
      errors.add('송영 대상 이용자의 누락 또는 잘못된 배정을 확인해 주세요.');
    }
    return errors;
  }

  List<String> get validationErrors => validate(draft);

  void confirm() {
    _requireAdmin();
    final errors = validationErrors;
    if (errors.isNotEmpty) throw StateError(errors.join('\n'));
    final snapshot = draft.copyWith(
      version: (confirmed?.version ?? 0) + 1,
      confirmedAt: DateTime.now(),
    );
    _confirmed[_currentKey] = snapshot;
    _drafts[_currentKey] = snapshot;
    _dirty.remove(_currentKey);
    notifyListeners();
  }

  List<RouteAssignment> get staffRoutes =>
      confirmed?.routes.where((r) => r.staffId == staffId).toList() ?? [];
}
