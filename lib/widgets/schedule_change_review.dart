import 'package:flutter/material.dart';

import '../models/schedule_catalog.dart';
import '../models/schedule_changes.dart';
import '../models/transport.dart';
import '../services/schedule_selection_policy.dart';
import 'course_change_details.dart';

class ScheduleChangeReview extends StatelessWidget {
  const ScheduleChangeReview({
    super.key,
    required this.catalog,
    required this.snapshot,
    required this.baseline,
    required this.changes,
    required this.remote,
    required this.warnings,
  });
  final ScheduleCatalog catalog;
  final ScheduleSnapshot snapshot;
  final ScheduleSnapshot? baseline;
  final ScheduleChanges changes;
  final bool remote;
  final List<String> warnings;
  String staff(String id) => catalog.staff.firstWhere((s) => s.id == id).name;
  String route(String id) =>
      catalog.baseRoutes.firstWhere((r) => r.id == id).name;
  String person(String id) =>
      catalog.passengers.firstWhere((p) => p.id == id).name;

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Text(
        '확정 대상: ${dateKey(snapshot.date)} (${ScheduleSelectionPolicy.weekday(snapshot.date)}) · ${snapshot.period.label} · ${snapshot.routes.length}개 코스',
        key: const Key('confirmation-target'),
      ),
      const SizedBox(height: 8),
      Text(
        remote ? '최종 일정 확정 후 직원에게 공유됩니다.' : '테스트 데이터 · 최종 확정 전 변경 내용을 확인해 주세요.',
      ),
      Text(
        '${changes.initial ? '처음 확정할' : '변경할'} 코스 ${changedCourseIds(changes, snapshot).length}개',
        key: const Key('changed-course-count'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      Text(
        changes.initial
            ? '이전 확정 일정이 없습니다. 첫 확정입니다.'
            : changes.items.isEmpty
            ? '기존 확정 일정과 변경사항이 없습니다.'
            : '공유된 일정에서 ${changes.items.length}항목이 바뀝니다.',
        key: const Key('change-summary'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final kind in ScheduleChangeKind.values)
            if (changes.items.any((item) => item.kind == kind))
              Chip(
                label: Text(
                  '${kind.label} (${changes.items.where((item) => item.kind == kind).length})',
                ),
              ),
        ],
      ),
      CourseChangeDetails(
        catalog: catalog,
        before: baseline,
        after: snapshot,
        changes: changes,
      ),
      const Divider(height: 24),
      ExpansionTile(
        key: const Key('review-all-schedules'),
        title: Text('전체 일정 ${snapshot.routes.length}개 코스 보기'),
        children: [
          for (final r in snapshot.routes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${staff(r.staffId)} · ${route(r.baseRouteId)}'),
              subtitle: Text(
                '${catalog.vehicles.firstWhere((v) => v.id == r.vehicleId).name} · 예상 ${minuteLabel(r.startMinute)}–${minuteLabel(r.endMinute)}\n'
                '${r.passengerIds.map((id) => '${person(id)} (${minuteLabel(r.estimatedVisitMinutes[id])})').join(' → ')}',
              ),
            ),
        ],
      ),
      Text(
        '결석 ${snapshot.absentIds.length}명 · 제외 ${snapshot.excludedIds.length}명',
      ),
      for (final warning in warnings) Text(warning),
    ],
  );
}
