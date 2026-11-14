import 'package:flutter/foundation.dart';

import '../models/transport.dart';
import '../services/schedule_controller.dart';

List<String> adminBlockingMessages(ScheduleController c) => [
  ...c.confirmationErrors,
  if (c.conflict) '다른 관리자가 변경했습니다. 최신 일정을 다시 불러와 주세요.',
];

/// Presentation only. Never changes dirty tracking, server versions or publish.
bool hasScheduleContentChanges(ScheduleController controller) {
  final before = controller.confirmed, after = controller.draft;
  if (before == null) return false;
  if (dateKey(before.date) != dateKey(after.date) ||
      before.period != after.period ||
      !setEquals(before.absentIds, after.absentIds) ||
      !setEquals(before.excludedIds, after.excludedIds) ||
      !setEquals(
        before.routes.map((r) => r.baseRouteId).toSet(),
        after.routes.map((r) => r.baseRouteId).toSet(),
      ) ||
      before.routes.length != after.routes.length) {
    return true;
  }
  for (final next in after.routes) {
    final old = before.routes
        .where((r) => r.baseRouteId == next.baseRouteId)
        .firstOrNull;
    if (old == null ||
        old.staffId != next.staffId ||
        old.vehicleId != next.vehicleId ||
        old.startMinute != next.startMinute ||
        old.endMinute != next.endMinute ||
        !listEquals(old.passengerIds, next.passengerIds) ||
        !mapEquals(old.estimatedVisitMinutes, next.estimatedVisitMinutes) ||
        !mapEquals(old.estimatedVisitSources, next.estimatedVisitSources)) {
      return true;
    }
  }
  return false;
}

String adminScheduleStatus(ScheduleController c) {
  if (c.conflict) return '다른 관리자의 변경 확인 필요';
  if (c.confirmed == null) return '미확정 일정';
  if (hasScheduleContentChanges(c)) return '변경사항 있음';
  return c.confirmedReassignmentNeeded ? '확정 일정 · 다른 직원 배정 필요' : '확정된 일정';
}
