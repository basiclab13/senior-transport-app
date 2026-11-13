import 'schedule_catalog.dart';
import 'transport.dart';

/// Shared by the candidate list and command; does not change any assignment.
String? courseReassignmentBlockReason(
  ScheduleCatalog catalog,
  ScheduleSnapshot snapshot,
  RouteAssignment route,
  Staff target,
  Set<String> absentStaffIds,
) {
  if (!absentStaffIds.contains(route.staffId)) {
    return '현재 시간대에 결근한 직원의 코스가 아닙니다.';
  }
  if (target.id == route.staffId) return '현재 담당 직원입니다.';
  if (absentStaffIds.contains(target.id)) return '해당 날짜·시간대 결근';
  if (!target.isAvailable(snapshot.date, snapshot.period)) {
    return '근무 불가 (비활성 또는 기본 휴무)';
  }
  if (snapshot.routes.any((r) => r.staffId == target.id)) {
    return '기존 코스 배정 중 · 직원당 시간대별 1개 코스';
  }
  final vehicle = catalog.vehicles
      .where((v) => v.id == route.vehicleId)
      .firstOrNull;
  if (vehicle == null) return '담당 차량 정보를 확인해 주세요.';
  if (route.passengerIds.length > vehicle.passengerCapacity) {
    return '기존 코스의 차량 정원 초과';
  }
  if (snapshot.routes.any(
    (r) => r.baseRouteId != route.baseRouteId && r.vehicleId == route.vehicleId,
  )) {
    return '같은 시간대 차량 중복 배정';
  }
  return null;
}
