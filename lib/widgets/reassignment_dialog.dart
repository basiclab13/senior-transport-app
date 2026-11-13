import 'package:flutter/material.dart';

import '../models/schedule_catalog.dart';
import '../models/transport.dart';
import '../utils/staff_sort.dart';

/// Displays the captured draft only. The caller validates snapshot identity
/// before invoking the existing controller command.
class ReassignmentDialog extends StatefulWidget {
  const ReassignmentDialog({
    super.key,
    required this.catalog,
    required this.snapshot,
    required this.sourceStaffId,
    required this.passengerId,
    this.absentStaffIds = const {},
  });
  final ScheduleCatalog catalog;
  final ScheduleSnapshot snapshot;
  final String sourceStaffId;
  final String passengerId;
  final Set<String> absentStaffIds;
  @override
  State<ReassignmentDialog> createState() => _ReassignmentDialogState();
}

class _ReassignmentDialogState extends State<ReassignmentDialog> {
  String _query = '';
  bool _availableOnly = false;
  bool _spaceOnly = false;
  ScheduleCatalog get catalog => widget.catalog;
  ScheduleSnapshot get snapshot => widget.snapshot;
  Vehicle vehicle(RouteAssignment route) =>
      catalog.vehicles.firstWhere((v) => v.id == route.vehicleId);
  String routeName(RouteAssignment route) =>
      catalog.baseRoutes.firstWhere((r) => r.id == route.baseRouteId).name;
  bool hasSpace(RouteAssignment route) =>
      route.passengerIds.length + 1 <= vehicle(route).passengerCapacity;

  @override
  Widget build(BuildContext context) {
    final staff = catalog.staff.where((s) {
      final routes = snapshot.routes.where((r) => r.staffId == s.id);
      return s.id != widget.sourceStaffId &&
          s.name.toLowerCase().contains(_query.trim().toLowerCase()) &&
          (!_availableOnly ||
              (s.isAvailable(snapshot.date, snapshot.period) &&
                  !widget.absentStaffIds.contains(s.id))) &&
          (!_spaceOnly || routes.any(hasSpace));
    }).toList()..sort(compareStaffNames);
    final passenger = catalog.passengers.firstWhere(
      (p) => p.id == widget.passengerId,
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
                  Expanded(
                    child: Text(
                      '${passenger.name} 재배정',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
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
                '${dateKey(snapshot.date)} · ${snapshot.period.label} · 이동 후 예상 시각은 다시 입력해 주세요.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                key: const Key('reassignment-search'),
                decoration: const InputDecoration(
                  labelText: '재배정 직원 이름 검색',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    key: const Key('reassignment-available'),
                    label: const Text('근무 가능만'),
                    selected: _availableOnly,
                    onSelected: (value) =>
                        setState(() => _availableOnly = value),
                  ),
                  FilterChip(
                    key: const Key('reassignment-space'),
                    label: const Text('정원 여유만'),
                    selected: _spaceOnly,
                    onSelected: (value) => setState(() => _spaceOnly = value),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('${staff.length}명 · 코스가 없는 직원은 먼저 기존 코스를 배정해 주세요.'),
            ),
            Expanded(
              child: staff.isEmpty
                  ? const Center(child: Text('검색·필터에 맞는 재배정 대상이 없습니다.'))
                  : ListView.builder(
                      key: const Key('reassignment-results'),
                      itemCount: staff.length,
                      itemBuilder: (context, index) {
                        final person = staff[index];
                        final routes =
                            snapshot.routes
                                .where((r) => r.staffId == person.id)
                                .toList()
                              ..sort(
                                (a, b) => compareNaturalNames(
                                  routeName(a),
                                  routeName(b),
                                ),
                              );
                        final total = routes.fold<int>(
                          0,
                          (sum, r) => sum + r.passengerIds.length,
                        );
                        final available =
                            !widget.absentStaffIds.contains(person.id) &&
                            person.isAvailable(snapshot.date, snapshot.period);
                        return Column(
                          children: [
                            if (routes.isEmpty)
                              ListTile(
                                enabled: false,
                                title: Text(person.name),
                                subtitle: Text(
                                  '${available ? '근무 가능' : '근무 불가'} · 미배정 · 차량 미배정',
                                ),
                              ),
                            for (final route in routes.where(
                              (r) => !_spaceOnly || hasSpace(r),
                            ))
                              ListTile(
                                key: ValueKey(
                                  'reassign-target-${widget.passengerId}-${route.baseRouteId}',
                                ),
                                isThreeLine: true,
                                title: Text(
                                  '${person.name} · ${routeName(route)}',
                                ),
                                subtitle: Text(
                                  '직원 총 $total명 · ${vehicle(route).name} · ${available ? '근무 가능' : '근무 불가'}\n'
                                  '현재 ${route.passengerIds.length}/${vehicle(route).passengerCapacity}명 · 이동 후 ${route.passengerIds.length + 1}명${hasSpace(route) ? '' : ' · 정원 초과'}',
                                ),
                                trailing: Icon(
                                  hasSpace(route) && available
                                      ? Icons.chevron_right
                                      : Icons.warning_amber,
                                  color: hasSpace(route) && available
                                      ? null
                                      : Theme.of(context).colorScheme.error,
                                ),
                                onTap: () =>
                                    Navigator.pop(context, route.baseRouteId),
                              ),
                            const Divider(height: 1),
                          ],
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
