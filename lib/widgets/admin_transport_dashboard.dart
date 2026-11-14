import 'package:flutter/material.dart';

import '../utils/display_wording.dart';

import '../models/transport.dart';

import '../services/schedule_controller.dart';
import '../utils/schedule_wording.dart';
import '../utils/staff_sort.dart';
import '../utils/admin_schedule_status.dart';
import 'admin_assignment_overview.dart';

/// Presentation only: all blocking decisions come from the existing controller.
class AdminTransportDashboard extends StatefulWidget {
  const AdminTransportDashboard({
    super.key,
    required this.controller,
    required this.onSelected,
    required this.onCheckProblems,
  });
  final ScheduleController controller;
  final ValueChanged<AdminScheduleSelection> onSelected;
  final VoidCallback onCheckProblems;
  @override
  State<AdminTransportDashboard> createState() =>
      _AdminTransportDashboardState();
}

class _AdminTransportDashboardState extends State<AdminTransportDashboard> {
  String query = '';
  ScheduleController get c => widget.controller;
  bool matches(String value) =>
      value.toLowerCase().contains(displayName(query.trim()).toLowerCase());
  int priority(String error) => error.contains('결근')
      ? 0
      : error.contains('누락') || error.contains('배정') || error.contains('정원')
      ? 1
      : 2;

  @override
  Widget build(BuildContext context) {
    if (c.loading ||
        c.dataError != null ||
        c.availabilityLoading ||
        c.availabilityError != null) {
      return const Center(
        child: Text('송영 정보를 확인하고 있습니다. 확인 전에는 일정을 확정할 수 없습니다.'),
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
    final errors = adminBlockingMessages(c).toSet().toList()
      ..sort((a, b) {
        final result = priority(a).compareTo(priority(b));
        return result == 0 ? a.compareTo(b) : result;
      });
    final staff =
        c.catalog.staff
            .where(
              (s) =>
                  matches(displayName(s.name)) ||
                  c
                      .routesForStaff(s.id)
                      .any(
                        (r) => r.passengerIds.any(
                          (id) => matches(displayName(c.passenger(id).name)),
                        ),
                      ) ||
                  // Unassigned/absent passengers remain findable through their baseline course.
                  c.catalog.baseRoutes
                      .where(
                        (r) =>
                            r.period == c.period &&
                            c.draft.routes.any(
                              (d) => d.baseRouteId == r.id && d.staffId == s.id,
                            ),
                      )
                      .any(
                        (r) => r.passengerIds.any(
                          (id) =>
                              !assigned.contains(id) &&
                              matches(displayName(c.passenger(id).name)),
                        ),
                      ),
            )
            .toList()
          ..sort(compareStaffNames);
    return CustomScrollView(
      key: const Key('admin-dashboard'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Row(
                      children: [
                        _metric(
                          '이용자',
                          '${expected.length}명',
                          'dashboard-passengers',
                        ),
                        const SizedBox(width: 8),
                        _metric(
                          '담당 직원',
                          '${c.draft.routes.map((r) => r.staffId).toSet().length}명',
                          'dashboard-staff-count',
                        ),
                        const SizedBox(width: 8),
                        _metric(
                          '해결할 문제',
                          '${errors.length}건',
                          'dashboard-problem-count',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '배정 ${assigned.length}명 · 결석 ${c.draft.absentIds.length}명 · 미배정 ${missing.length}명${c.draft.excludedIds.isEmpty ? '' : ' · 제외 ${c.draft.excludedIds.length}명'}',
                  key: const Key('dashboard-assignment-summary'),
                ),
                const SizedBox(height: 8),
                if (errors.isNotEmpty) ...[
                  const Text(
                    '확정 불가 · 먼저 해결해 주세요',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final error in errors.take(3)) _problem(error, missing),
                  if (errors.length > 3)
                    ExpansionTile(
                      title: Text('나머지 문제 ${errors.length - 3}건 보기'),
                      children: [
                        for (final error in errors.skip(3))
                          _problem(error, missing),
                      ],
                    ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: TextField(
                      key: const Key('dashboard-search'),
                      decoration: const InputDecoration(
                        labelText: '직원·이용자 이름 검색',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => setState(() => query = value),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '직원별 송영 일정',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        if (staff.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('검색 결과가 없습니다.'),
            ),
          ),
        if (MediaQuery.sizeOf(context).width >= 900)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _staffTable(staff),
            ),
          )
        else
          SliverList.builder(
            itemCount: staff.length,
            itemBuilder: (context, index) {
              final person = staff[index];
              final routes = c.routesForStaff(person.id);
              final passenger = query.trim().isEmpty
                  ? null
                  : c.catalog.passengers
                        .where(
                          (p) =>
                              matches(displayName(p.name)) &&
                              routes.any(
                                (r) =>
                                    r.passengerIds.contains(p.id) ||
                                    c
                                        .baseRoute(r.baseRouteId)
                                        .passengerIds
                                        .contains(p.id),
                              ),
                        )
                        .firstOrNull;
              final route = passenger == null
                  ? routes.firstOrNull
                  : routes
                            .where((r) => r.passengerIds.contains(passenger.id))
                            .firstOrNull ??
                        routes
                            .where(
                              (r) => c
                                  .baseRoute(r.baseRouteId)
                                  .passengerIds
                                  .contains(passenger.id),
                            )
                            .firstOrNull;
              final status = c.isStaffAbsent(person.id)
                  ? '결근${routes.isNotEmpty ? ' · 다른 직원 배정 필요' : ''}'
                  : c.staffAvailable(person)
                  ? (routes.isEmpty ? '담당 코스 없음' : '배정됨')
                  : '배정 불가';
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  key: ValueKey('dashboard-staff-${person.id}'),
                  title: Text(displayName(person.name)),
                  subtitle: Text(
                    [
                      if (routes.isEmpty)
                        '이용자 0명 · $status'
                      else
                        for (final r in routes)
                          '${displayName(c.baseRoute(r.baseRouteId).name)} · ${displayName(c.vehicle(r.vehicleId).name)}\n이용자 ${r.passengerIds.length}/${c.vehicle(r.vehicleId).passengerCapacity}명 · $status',
                      if (passenger != null)
                        '${displayName(passenger.name)} · ${assigned.contains(passenger.id)
                            ? '담당 이용자'
                            : c.draft.absentIds.contains(passenger.id)
                            ? '결석'
                            : c.draft.excludedIds.contains(passenger.id)
                            ? '제외'
                            : '미배정'}',
                    ].join('\n'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => widget.onSelected(
                    AdminScheduleSelection(
                      person.id,
                      passenger == null ? '' : route?.baseRouteId ?? '',
                      passenger?.id,
                    ),
                  ),
                ),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  Widget _metric(String label, String value, String key) => Expanded(
    child: Semantics(
      label: '$label $value',
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            key: Key(key),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  AdminScheduleSelection _selection(Staff person) {
    final routes = c.routesForStaff(person.id);
    final assigned = c.draft.routes.expand((r) => r.passengerIds).toSet();
    final passenger = query.trim().isEmpty
        ? null
        : c.catalog.passengers
              .where(
                (p) =>
                    matches(displayName(p.name)) &&
                    routes.any(
                      (r) =>
                          r.passengerIds.contains(p.id) ||
                          (!assigned.contains(p.id) &&
                              c
                                  .baseRoute(r.baseRouteId)
                                  .passengerIds
                                  .contains(p.id)),
                    ),
              )
              .firstOrNull;
    final route = passenger == null
        ? null
        : routes
              .where(
                (r) =>
                    r.passengerIds.contains(passenger.id) ||
                    c
                        .baseRoute(r.baseRouteId)
                        .passengerIds
                        .contains(passenger.id),
              )
              .firstOrNull;
    return AdminScheduleSelection(
      person.id,
      route?.baseRouteId ?? '',
      passenger?.id,
    );
  }

  Widget _staffTable(List<Staff> staff) => Table(
    key: const Key('dashboard-staff-table'),
    columnWidths: const {
      0: FlexColumnWidth(2),
      1: FlexColumnWidth(3),
      2: FlexColumnWidth(1.4),
      3: FlexColumnWidth(2.6),
    },
    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
    border: TableBorder(
      horizontalInside: BorderSide(color: Theme.of(context).dividerColor),
    ),
    children: [
      TableRow(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        children: [
          for (final title in ['직원 이름', '담당 코스 · 차량', '이용자 수', '배정 상태'])
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      for (final person in staff) _tableRow(person),
    ],
  );

  TableRow _tableRow(Staff person) {
    final routes = c.routesForStaff(person.id);
    final selection = _selection(person);
    final status = c.isStaffAbsent(person.id)
        ? '결근${routes.isEmpty ? '' : ' · 다른 직원 배정 필요'}'
        : !c.staffAvailable(person)
        ? '배정 불가'
        : routes.isEmpty
        ? '담당 코스 없음'
        : '배정됨';
    final cells = <Widget>[
      Column(
        key: ValueKey('dashboard-staff-${person.id}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(displayName(person.name)),
          if (selection.passengerId != null)
            Text(
              '${displayName(c.passenger(selection.passengerId!).name)} · ${c.draft.absentIds.contains(selection.passengerId)
                  ? '결석'
                  : c.draft.excludedIds.contains(selection.passengerId)
                  ? '제외'
                  : c.draft.routes.any((r) => r.passengerIds.contains(selection.passengerId))
                  ? '담당 이용자'
                  : '미배정'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      Text(
        routes.isEmpty
            ? '담당 코스 없음'
            : routes
                  .map(
                    (r) =>
                        '${displayName(c.baseRoute(r.baseRouteId).name)}\n${displayName(c.vehicle(r.vehicleId).name)}',
                  )
                  .join('\n'),
      ),
      Text(
        routes.isEmpty
            ? '0명'
            : routes
                  .map(
                    (r) =>
                        '${r.passengerIds.length}/${c.vehicle(r.vehicleId).passengerCapacity}명',
                  )
                  .join('\n'),
      ),
      Row(
        children: [
          Icon(
            c.isStaffAbsent(person.id) || !c.staffAvailable(person)
                ? Icons.warning_amber
                : routes.isEmpty
                ? Icons.person_outline
                : Icons.check_circle_outline,
            size: 18,
            color: c.isStaffAbsent(person.id) || !c.staffAvailable(person)
                ? Theme.of(context).colorScheme.error
                : routes.isEmpty
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : Colors.teal,
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(status)),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    ];
    return TableRow(
      children: [
        for (final cell in cells)
          TableCell(
            child: InkWell(
              onTap: () => widget.onSelected(selection),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Align(alignment: Alignment.centerLeft, child: cell),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _problem(String error, Set<String> missing) {
    final route = c.draft.routes
        .where((r) => error.startsWith('${c.baseRoute(r.baseRouteId).name}:'))
        .firstOrNull;
    final missingPerson =
        route == null && error.contains('누락') && missing.isNotEmpty
        ? missing.first
        : null;
    final target =
        route ??
        c.draft.routes
            .where(
              (r) =>
                  missingPerson != null &&
                  c
                      .baseRoute(r.baseRouteId)
                      .passengerIds
                      .contains(missingPerson),
            )
            .firstOrNull;
    final title = missingPerson != null
        ? '배정되지 않은 이용자 ${missing.length}명을 확인해 주세요.'
        : easyScheduleMessage(error);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.error_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: target == null
          ? widget.onCheckProblems
          : () => widget.onSelected(
              AdminScheduleSelection(
                target.staffId,
                target.baseRouteId,
                missingPerson,
              ),
            ),
    );
  }
}
