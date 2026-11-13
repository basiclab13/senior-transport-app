import 'package:flutter/material.dart';

import '../models/schedule_catalog.dart';
import '../models/schedule_changes.dart';
import '../models/transport.dart';
import '../utils/schedule_wording.dart';

Set<String> changedCourseIds(
  ScheduleChanges changes,
  ScheduleSnapshot snapshot,
) => changes.initial
    ? snapshot.routes.map((r) => r.baseRouteId).toSet()
    : changes.items.expand((item) => item.routeIds).toSet();

class CourseChangeDetails extends StatelessWidget {
  const CourseChangeDetails({
    super.key,
    required this.catalog,
    required this.before,
    required this.after,
    required this.changes,
    this.expand = false,
    this.showVisitTimes = true,
    this.afterLabel = '변경 순서',
  });
  final ScheduleCatalog catalog;
  final ScheduleSnapshot? before;
  final ScheduleSnapshot after;
  final ScheduleChanges changes;
  final bool expand;
  final bool showVisitTimes;
  final String afterLabel;
  String staff(String? id) =>
      catalog.staff.where((s) => s.id == id).firstOrNull?.name ?? '담당 없음';
  String name(String id) =>
      catalog.passengers.where((p) => p.id == id).firstOrNull?.name ?? id;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final id in changedCourseIds(changes, after)) _course(context, id),
    ],
  );
  Widget _course(BuildContext context, String id) {
    final old = before?.routes.where((r) => r.baseRouteId == id).firstOrNull;
    final next = after.routes.where((r) => r.baseRouteId == id).firstOrNull;
    final title =
        catalog.baseRoutes.where((r) => r.id == id).firstOrNull?.name ?? id;
    final items = changes.items
        .where((item) => item.routeIds.contains(id))
        .toList();
    return ExpansionTile(
      key: ValueKey('course-review-$id'),
      initiallyExpanded: expand,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      title: Text('$title · ${staff(next?.staffId ?? old?.staffId)}'),
      subtitle: Text(
        old != null && next != null && old.staffId != next.staffId
            ? '담당 직원: ${staff(old.staffId)} → ${staff(next.staffId)}'
            : before == null
            ? '처음 확정하는 코스'
            : '변경 ${items.length}항목',
      ),
      children: [
        LayoutBuilder(
          builder: (context, size) {
            final previous = _order('기존 순서', old?.passengerIds ?? []);
            final proposed = _order(afterLabel, next?.passengerIds ?? []);
            return size.maxWidth >= 500
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: previous),
                      const SizedBox(width: 16),
                      Expanded(child: proposed),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [previous, const SizedBox(height: 12), proposed],
                  );
          },
        ),
        for (final item in items.where(
          (i) => i.kind != ScheduleChangeKind.order,
        ))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(easyScheduleMessage(item.description)),
          ),
        if (showVisitTimes && next != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${catalog.vehicles.where((v) => v.id == next.vehicleId).firstOrNull?.name ?? next.vehicleId} · 예상 ${minuteLabel(next.startMinute)}–${minuteLabel(next.endMinute)}\n'
              '${next.passengerIds.map((id) => '${name(id)} (${minuteLabel(next.estimatedVisitMinutes[id])})').join(' → ')}',
            ),
          ),
      ],
    );
  }

  Widget _order(String label, List<String> ids) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      if (ids.isEmpty)
        const Text('방문 이용자 없음')
      else
        for (var i = 0; i < ids.length; i++) Text('${i + 1}. ${name(ids[i])}'),
    ],
  );
}
