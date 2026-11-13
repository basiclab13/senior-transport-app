import 'package:flutter/foundation.dart';

import 'schedule_catalog.dart';
import 'transport.dart';
import '../utils/staff_sort.dart';

enum ScheduleChangeKind {
  assignment('이용자 배정 변경'),
  staff('담당 직원 변경'),
  order('방문 순서 변경'),
  absence('결석 변경'),
  exclusion('제외 변경'),
  vehicle('차량 변경'),
  time('예상 시각 변경'),
  route('코스 변경');

  const ScheduleChangeKind(this.label);
  final String label;
}

class ScheduleChange {
  const ScheduleChange(this.kind, this.description, {this.routeIds = const {}});
  final ScheduleChangeKind kind;
  final String description;
  // UI grouping only. Never included in schedule payloads or Firestore.
  final Set<String> routeIds;
}

/// Presentation-only diff. It never mutates drafts, versions or publish payloads.
class ScheduleChanges {
  ScheduleChanges._(this.initial, List<ScheduleChange> changes)
    : items = List.unmodifiable(changes);
  final bool initial;
  final List<ScheduleChange> items;

  factory ScheduleChanges.compare(
    ScheduleSnapshot? before,
    ScheduleSnapshot after,
    ScheduleCatalog catalog,
  ) {
    if (before == null) {
      return ScheduleChanges._(true, [
        for (final route in after.routes)
          if (catalog.baseRoutes.any(
            (base) =>
                base.id == route.baseRouteId && base.staffId != route.staffId,
          ))
            ScheduleChange(
              ScheduleChangeKind.staff,
              '${catalog.baseRoutes.firstWhere((base) => base.id == route.baseRouteId).name}: ${catalog.staff.firstWhere((s) => s.id == catalog.baseRoutes.firstWhere((base) => base.id == route.baseRouteId).staffId).name} → ${catalog.staff.firstWhere((s) => s.id == route.staffId).name} (기본 배정 대비)',
              routeIds: {route.baseRouteId},
            ),
      ]);
    }
    if (dateKey(before.date) != dateKey(after.date) ||
        before.period != after.period) {
      throw ArgumentError('같은 날짜·시간대의 일정만 비교할 수 있습니다.');
    }
    final changes = <ScheduleChange>[];
    void add(
      ScheduleChangeKind kind,
      String description,
      Set<String> routeIds,
    ) => changes.add(ScheduleChange(kind, description, routeIds: routeIds));
    String person(String id) =>
        catalog.passengers.where((p) => p.id == id).firstOrNull?.name ?? id;
    String staff(String id) =>
        catalog.staff.where((s) => s.id == id).firstOrNull?.name ?? id;
    String vehicle(String id) =>
        catalog.vehicles.where((v) => v.id == id).firstOrNull?.name ?? id;
    String routeName(String id) =>
        catalog.baseRoutes.where((r) => r.id == id).firstOrNull?.name ?? id;
    String location(RouteAssignment route) =>
        '${staff(route.staffId)} · ${routeName(route.baseRouteId)}';
    String order(List<String> ids) =>
        ids.isEmpty ? '없음' : ids.map(person).join(' → ');
    final oldRoutes = {for (final r in before.routes) r.baseRouteId: r};
    final newRoutes = {for (final r in after.routes) r.baseRouteId: r};
    for (final id in {...oldRoutes.keys, ...newRoutes.keys}) {
      final old = oldRoutes[id];
      final next = newRoutes[id];
      if (old == null || next == null) {
        add(
          ScheduleChangeKind.route,
          '${routeName(id)}: ${old == null ? '코스 추가' : '코스 제거'}',
          {id},
        );
        continue;
      }
      if (old.staffId != next.staffId) {
        add(
          ScheduleChangeKind.staff,
          '${routeName(id)}: ${staff(old.staffId)} → ${staff(next.staffId)}',
          {id},
        );
      }
      if (old.vehicleId != next.vehicleId) {
        add(
          ScheduleChangeKind.vehicle,
          '${routeName(id)}: ${vehicle(old.vehicleId)} → ${vehicle(next.vehicleId)}',
          {id},
        );
      }
      // A transfer/absence alone is not a relative order change of remaining stops.
      final commonOld = old.passengerIds
          .where(next.passengerIds.contains)
          .toList();
      final commonNew = next.passengerIds
          .where(old.passengerIds.contains)
          .toList();
      if (!listEquals(commonOld, commonNew)) {
        add(
          ScheduleChangeKind.order,
          '${location(next)}\n이전: ${order(old.passengerIds)}\n변경: ${order(next.passengerIds)}',
          {id},
        );
      }
      if (old.startMinute != next.startMinute ||
          old.endMinute != next.endMinute) {
        add(
          ScheduleChangeKind.time,
          '${location(next)} 운행: ${minuteLabel(old.startMinute)}–${minuteLabel(old.endMinute)} → ${minuteLabel(next.startMinute)}–${minuteLabel(next.endMinute)}',
          {id},
        );
      }
    }
    final ids = {
      ...before.routes.expand((r) => r.passengerIds),
      ...after.routes.expand((r) => r.passengerIds),
      ...before.absentIds,
      ...after.absentIds,
      ...before.excludedIds,
      ...after.excludedIds,
    }.toList()..sort((a, b) => compareNaturalNames(person(a), person(b)));
    String assignment(List<RouteAssignment> routes) =>
        routes.isEmpty ? '미배정' : routes.map(location).join(' / ');
    for (final id in ids) {
      final old = before.routes
          .where((r) => r.passengerIds.contains(id))
          .toList();
      final next = after.routes
          .where((r) => r.passengerIds.contains(id))
          .toList();
      final affectedRoutes = {
        for (final r in [...old, ...next]) r.baseRouteId,
      };
      if (affectedRoutes.isEmpty) {
        affectedRoutes.addAll(
          catalog.baseRoutes
              .where(
                (r) => r.period == after.period && r.passengerIds.contains(id),
              )
              .map((r) => r.id),
        );
      }
      final oldLocations =
          old.map((r) => '${r.staffId}/${r.baseRouteId}').toList()..sort();
      final newLocations =
          next.map((r) => '${r.staffId}/${r.baseRouteId}').toList()..sort();
      if (!listEquals(oldLocations, newLocations) &&
          !(next.isEmpty &&
              (after.absentIds.contains(id) ||
                  after.excludedIds.contains(id)))) {
        add(
          ScheduleChangeKind.assignment,
          '${person(id)}: ${assignment(old)} → ${assignment(next)}'
          '${old.length == 1 && next.length == 1 ? ' (방문 ${old.single.passengerIds.indexOf(id) + 1}번째 → ${next.single.passengerIds.indexOf(id) + 1}번째)' : ''}',
          affectedRoutes,
        );
      }
      if (before.absentIds.contains(id) != after.absentIds.contains(id)) {
        add(
          ScheduleChangeKind.absence,
          '${person(id)}: ${after.absentIds.contains(id) ? '결석 처리' : '결석 해제'}',
          affectedRoutes,
        );
      }
      if (before.excludedIds.contains(id) != after.excludedIds.contains(id)) {
        add(
          ScheduleChangeKind.exclusion,
          '${person(id)}: ${after.excludedIds.contains(id) ? '제외 처리' : '제외 해제'}',
          affectedRoutes,
        );
      }
      if (old.length == 1 &&
          next.length == 1 &&
          old.single.estimatedVisitMinutes[id] !=
              next.single.estimatedVisitMinutes[id]) {
        add(
          ScheduleChangeKind.time,
          '${person(id)} 방문: ${minuteLabel(old.single.estimatedVisitMinutes[id])} → ${minuteLabel(next.single.estimatedVisitMinutes[id])} · ${assignment(next)}',
          affectedRoutes,
        );
      } else if (old.length == 1 &&
          next.length == 1 &&
          old.single.estimatedVisitMinutes.containsKey(id) &&
          next.single.estimatedVisitMinutes.containsKey(id) &&
          old.single.isManualEstimate(id) != next.single.isManualEstimate(id)) {
        add(
          ScheduleChangeKind.time,
          '${person(id)} 예상 시각 출처: ${old.single.isManualEstimate(id) ? '수동' : '고정 간격'} → ${next.single.isManualEstimate(id) ? '수동' : '고정 간격'} · ${assignment(next)}',
          affectedRoutes,
        );
      }
    }
    return ScheduleChanges._(false, changes);
  }
}
