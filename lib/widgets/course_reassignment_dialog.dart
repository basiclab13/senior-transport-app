import 'package:flutter/material.dart';

import '../utils/display_wording.dart';

import '../models/course_reassignment.dart';
import '../models/schedule_catalog.dart';
import '../models/transport.dart';
import '../utils/staff_sort.dart';

class CourseReassignmentDialog extends StatefulWidget {
  const CourseReassignmentDialog({
    super.key,
    required this.catalog,
    required this.snapshot,
    required this.route,
    required this.absentStaffIds,
  });
  final ScheduleCatalog catalog;
  final ScheduleSnapshot snapshot;
  final RouteAssignment route;
  final Set<String> absentStaffIds;

  @override
  State<CourseReassignmentDialog> createState() =>
      _CourseReassignmentDialogState();
}

class _CourseReassignmentDialogState extends State<CourseReassignmentDialog> {
  String _query = '';
  bool _eligibleOnly = false;
  ScheduleCatalog get catalog => widget.catalog;
  String course(String id) =>
      displayName(catalog.baseRoutes.firstWhere((r) => r.id == id).name);
  String? reason(Staff staff) => courseReassignmentBlockReason(
    catalog,
    widget.snapshot,
    widget.route,
    staff,
    widget.absentStaffIds,
  );

  @override
  Widget build(BuildContext context) {
    final candidates =
        catalog.staff
            .where(
              (s) =>
                  s.id != widget.route.staffId &&
                  displayName(s.name)
                      .toLowerCase()
                      .contains(displayName(_query.trim()).toLowerCase()) &&
                  (!_eligibleOnly || reason(s) == null),
            )
            .toList()
          ..sort(compareStaffNames);
    final vehicle = catalog.vehicles.firstWhere(
      (v) => v.id == widget.route.vehicleId,
    );
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 680,
        height: MediaQuery.sizeOf(context).height * .8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('대신 담당할 직원 선택', style: TextStyle(fontSize: 20)),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${dateKey(widget.snapshot.date)} · ${widget.snapshot.period.label} · ${course(widget.route.baseRouteId)}\n${displayName(vehicle.name)} · ${widget.route.passengerIds.length}/${vehicle.passengerCapacity}명 · 차량·방문 순서 유지',
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                key: const Key('course-transfer-search'),
                decoration: const InputDecoration(
                  labelText: '직원 이름 검색',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                children: [
                  FilterChip(
                    label: const Text('재배정 가능만'),
                    selected: _eligibleOnly,
                    onSelected: (value) =>
                        setState(() => _eligibleOnly = value),
                  ),
                ],
              ),
            ),
            Expanded(
              child: candidates.isEmpty
                  ? const Center(
                      child: Text('검색·필터에 맞는 대상이 없습니다. 재배정 필요 상태가 유지됩니다.'),
                    )
                  : ListView.builder(
                      key: const Key('course-transfer-results'),
                      itemCount: candidates.length,
                      itemBuilder: (context, index) {
                        final person = candidates[index];
                        final routes = widget.snapshot.routes
                            .where((r) => r.staffId == person.id)
                            .toList();
                        final count = routes.fold<int>(
                          0,
                          (sum, r) => sum + r.passengerIds.length,
                        );
                        final blocked = reason(person);
                        final available =
                            person.isAvailable(
                              widget.snapshot.date,
                              widget.snapshot.period,
                            ) &&
                            !widget.absentStaffIds.contains(person.id);
                        return ListTile(
                          key: ValueKey('course-transfer-target-${person.id}'),
                          enabled: blocked == null,
                          title: Text(displayName(person.name)),
                          subtitle: Text(
                            '${available ? '근무 가능' : '근무 불가'} · 현재 이용자 $count명\n${routes.isEmpty ? '기존 코스 없음 · 차량 미배정' : routes.map((r) => '${course(r.baseRouteId)} · ${displayName(catalog.vehicles.firstWhere((v) => v.id == r.vehicleId).name)}').join(' / ')}\n${blocked ?? '인계 가능 · ${displayName(vehicle.name)} 유지 · 이동 후 ${widget.route.passengerIds.length}명'}',
                          ),
                          trailing: Icon(
                            blocked == null ? Icons.chevron_right : Icons.block,
                          ),
                          onTap: blocked == null
                              ? () => Navigator.pop(context, person.id)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
