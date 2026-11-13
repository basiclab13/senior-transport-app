import 'package:flutter/material.dart';

import '../models/transport.dart';
import '../services/schedule_controller.dart';
import '../utils/staff_sort.dart';

class AdminScheduleSelection {
  const AdminScheduleSelection(this.staffId, this.routeId, [this.passengerId]);
  final String staffId;
  final String routeId;
  final String? passengerId;
}

/// Read-only view of the same dated draft used by the employee editor.
class AdminAssignmentOverview extends StatefulWidget {
  const AdminAssignmentOverview({
    super.key,
    required this.controller,
    this.passengerSearch = false,
  });
  final ScheduleController controller;
  final bool passengerSearch;

  @override
  State<AdminAssignmentOverview> createState() =>
      _AdminAssignmentOverviewState();
}

class _AdminAssignmentOverviewState extends State<AdminAssignmentOverview> {
  late bool _passengers = widget.passengerSearch;
  String _query = '';
  ScheduleController get c => widget.controller;
  bool _matches(String name) =>
      name.toLowerCase().contains(_query.trim().toLowerCase());

  void _open(RouteAssignment route, [String? passengerId]) => Navigator.pop(
    context,
    AdminScheduleSelection(route.staffId, route.baseRouteId, passengerId),
  );

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(12),
    child: SizedBox(
      width: 1160,
      height: MediaQuery.sizeOf(context).height * .85,
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          if (c.loading ||
              c.dataError != null ||
              c.availabilityLoading ||
              c.availabilityError != null) {
            return Column(
              children: [
                const Expanded(
                  child: Center(child: Text('일정을 다시 불러오는 중이거나 조회할 수 없습니다.')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('닫기'),
                ),
              ],
            );
          }
          final expected = c.catalog.baseRoutes
              .where((r) => r.period == c.period)
              .expand((r) => r.passengerIds)
              .toSet();
          final assigned = c.draft.routes.expand((r) => r.passengerIds).toSet();
          final missing = expected.difference({
            ...assigned,
            ...c.draft.absentIds,
            ...c.draft.excludedIds,
          });
          final people = c.catalog.passengers
              .where(
                (p) =>
                    (expected.contains(p.id) || assigned.contains(p.id)) &&
                    (_matches(p.name) ||
                        c.draft.routes.any(
                          (r) =>
                              r.passengerIds.contains(p.id) &&
                              _matches(c.staff(r.staffId).name),
                        )),
              )
              .toList();
          final staff =
              c.catalog.staff
                  .where(
                    (s) =>
                        _matches(s.name) ||
                        c
                            .routesForStaff(s.id)
                            .any(
                              (r) => r.passengerIds.any(
                                (id) => _matches(c.passenger(id).name),
                              ),
                            ),
                  )
                  .toList()
                ..sort(compareStaffNames);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '전체 배정 현황',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const Key('close-overview'),
                      tooltip: '닫기',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                flex: 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '${dateKey(c.selectedDate)} · ${c.period.label} · ${c.hasPendingChanges
                        ? '변경 중인 일정'
                        : c.confirmed == null
                        ? '아직 확정하지 않은 일정'
                        : c.confirmedReassignmentNeeded
                        ? '공유된 일정 · 다른 직원 배정 필요'
                        : '확정 일정'}\n'
                    '직원 ${c.catalog.staff.length}명 · 코스 ${c.draft.routes.length}개 · 배정 ${assigned.length}/${expected.length}명 · 결석 ${c.draft.absentIds.length}명 · 제외 ${c.draft.excludedIds.length}명 · 미배정 ${missing.length}명',
                    key: const Key('overview-summary'),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '직원 결근 ${c.catalog.staff.where((s) => c.isStaffAbsent(s.id)).length}명 · 다른 직원 배정 필요 ${c.draft.routes.where((r) => c.isStaffAbsent(r.staffId)).length}코스',
                  key: const Key('overview-staff-absence'),
                ),
              ),
              if (c.pendingTimeReviewRouteIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '방문 시간 확인 필요 ${c.pendingTimeReviewRouteIds.length}코스 · 직원 상세에서 검토해 주세요.',
                  ),
                ),
              if (c.validationErrors.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '확인할 문제 ${c.validationErrors.length}건 · 전체 일정 검증에서 상세 내용을 확인하세요.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  key: const Key('assignment-search'),
                  decoration: const InputDecoration(
                    labelText: '직원·이용자 이름 검색',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('직원별 현황')),
                    ButtonSegment(value: true, label: Text('이용자 찾기')),
                  ],
                  selected: {_passengers},
                  onSelectionChanged: (values) =>
                      setState(() => _passengers = values.single),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 850;
                    return Column(
                      children: [
                        if (!_passengers && wide)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                SizedBox(width: 140, child: Text('직원 / 근무')),
                                SizedBox(width: 160, child: Text('코스 / 차량')),
                                SizedBox(width: 90, child: Text('인원 / 정원')),
                                Expanded(child: Text('방문 순서 · 이용자 (선택하여 편집)')),
                              ],
                            ),
                          ),
                        Expanded(
                          child: (_passengers ? people.isEmpty : staff.isEmpty)
                              ? const Center(child: Text('검색 결과가 없습니다.'))
                              : ListView.builder(
                                  key: const Key('assignment-results'),
                                  itemCount: _passengers
                                      ? people.length
                                      : staff.length,
                                  itemBuilder: (context, index) => _passengers
                                      ? _person(people[index])
                                      : _staff(staff[index], wide),
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _staff(Staff staff, bool wide) {
    final routes = c.routesForStaff(staff.id);
    final work = c.isStaffAbsent(staff.id)
        ? '결근${routes.isNotEmpty ? ' · 다른 직원 배정 필요' : ''}'
        : c.staffAvailable(staff)
        ? '근무 가능'
        : '근무 불가';
    return Container(
      key: ValueKey('overview-staff-${staff.id}'),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: routes.isEmpty
          ? ListTile(
              dense: true,
              title: Text(staff.name),
              subtitle: Text('$work · 미배정'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.pop(context, AdminScheduleSelection(staff.id, '')),
            )
          : Column(
              children: [
                for (final r in routes)
                  InkWell(
                    onTap: () => _open(r),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 140,
                                  child: Text('${staff.name}\n$work'),
                                ),
                                SizedBox(
                                  width: 160,
                                  child: Text(
                                    '${c.baseRoute(r.baseRouteId).name}\n${c.vehicle(r.vehicleId).name}',
                                  ),
                                ),
                                SizedBox(width: 90, child: _capacity(r)),
                                Expanded(
                                  child: Text(
                                    r.passengerIds
                                        .map((id) => c.passenger(id).name)
                                        .join(' → '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.chevron_right, size: 18),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${staff.name} · $work'),
                                Text(
                                  '${c.baseRoute(r.baseRouteId).name} · ${c.vehicle(r.vehicleId).name}',
                                ),
                                _capacity(r),
                                Text(
                                  r.passengerIds
                                      .map((id) => c.passenger(id).name)
                                      .join(' → '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _capacity(RouteAssignment route) => Text(
    '${route.passengerIds.length}/${c.vehicle(route.vehicleId).passengerCapacity}명',
    style: TextStyle(
      color:
          route.passengerIds.length >
              c.vehicle(route.vehicleId).passengerCapacity
          ? Theme.of(context).colorScheme.error
          : null,
    ),
  );

  Widget _person(Passenger passenger) {
    final routes = c.draft.routes
        .where((r) => r.passengerIds.contains(passenger.id))
        .toList();
    final removed = c.draft.absentIds.contains(passenger.id)
        ? '결석'
        : c.draft.excludedIds.contains(passenger.id)
        ? '제외'
        : '미배정';
    final originals = c.draft.routes
        .where(
          (r) => c.baseRoute(r.baseRouteId).passengerIds.contains(passenger.id),
        )
        .toList();
    return Column(
      children: [
        for (final route in routes.isEmpty ? originals : routes)
          ListTile(
            key: ValueKey(
              'find-passenger-${passenger.id}-${route.baseRouteId}',
            ),
            title: Text(passenger.name),
            subtitle: Text(
              '${routes.isEmpty ? '$removed · 기본 코스 담당 ' : ''}${c.staff(route.staffId).name} · ${c.baseRoute(route.baseRouteId).name}\n${passenger.address}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(route, passenger.id),
          ),
        if (routes.isEmpty && originals.isEmpty)
          ListTile(
            title: Text(passenger.name),
            subtitle: Text('$removed · 연결된 코스 없음'),
          ),
      ],
    );
  }
}
