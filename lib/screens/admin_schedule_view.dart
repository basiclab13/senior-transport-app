import 'package:flutter/material.dart';

import '../widgets/passenger_details_dialog.dart';

import '../utils/schedule_wording.dart';
import '../utils/display_wording.dart';

import '../widgets/admin_work_photos.dart';

import '../models/transport.dart';
import '../services/schedule_controller.dart';
import '../widgets/estimated_time_dialog.dart';
import '../widgets/route_timeline.dart';
import '../widgets/admin_assignment_overview.dart';
import '../widgets/admin_transport_dashboard.dart';
import '../widgets/reassignment_dialog.dart';
import '../widgets/course_reassignment_dialog.dart';
import '../utils/staff_sort.dart';

enum _WorkFilter { all, available, unavailable }

enum _AssignmentFilter { all, assigned, unassigned }

class AdminScheduleView extends StatefulWidget {
  const AdminScheduleView({super.key, required this.controller});
  final ScheduleController controller;

  @override
  State<AdminScheduleView> createState() => _AdminScheduleViewState();
}

class _AdminScheduleViewState extends State<AdminScheduleView> {
  ScheduleController get c => widget.controller;
  String _query = '';
  final _search = TextEditingController();
  String? _selectedId;
  bool _mobileDetail = false;
  bool _overview = true;
  String? _focusedPassengerId;
  String? _focusedRouteId;
  final _focusedRouteKey = GlobalKey();
  final _assignmentEditors = <String>{};
  String _editorScope(String routeId) =>
      '${dateKey(c.selectedDate)}_${c.period.name}_$routeId';
  _WorkFilter _work = _WorkFilter.all;
  _AssignmentFilter _assignment = _AssignmentFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Staff> get _filtered => c.catalog.staff.where((staff) {
    final available = c.staffAvailable(staff);
    final assigned = c.routesForStaff(staff.id).isNotEmpty;
    return displayName(staff.name).contains(displayName(_query.trim())) &&
        (_work == _WorkFilter.all ||
            available == (_work == _WorkFilter.available)) &&
        (_assignment == _AssignmentFilter.all ||
            assigned == (_assignment == _AssignmentFilter.assigned));
  }).toList()..sort(compareStaffNames);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            TextButton(
              key: const Key('admin-overview'),
              onPressed: () => setState(() => _overview = true),
              child: Text(
                '전체 현황',
                style: TextStyle(
                  fontWeight: _overview ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            TextButton(
              key: const Key('admin-editor'),
              onPressed: () => setState(() => _overview = false),
              child: Text(
                '직원별 일정',
                style: TextStyle(
                  fontWeight: !_overview ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
      if (_overview)
        Expanded(
          child: AdminTransportDashboard(
            controller: c,
            onSelected: _select,
            onCheckProblems: () => _openOverview(),
          ),
        )
      else ...[
        Expanded(
          child: LayoutBuilder(
            builder: (context, size) {
              final wide = size.maxWidth >= 900;
              final filtered = _filtered;
              _selectedId ??= filtered.firstOrNull?.id;
              final selected = filtered.any((staff) => staff.id == _selectedId)
                  ? _selectedId
                  : null;
              final list = _staffList(filtered);
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 320, child: list),
                    const VerticalDivider(width: 1),
                    Expanded(child: _detail(selected)),
                  ],
                );
              }
              if (!_mobileDetail || selected == null) return list;
              return Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('back-to-staff'),
                      onPressed: () => setState(() => _mobileDetail = false),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('직원 목록으로'),
                    ),
                  ),
                  Expanded(child: _detail(selected)),
                ],
              );
            },
          ),
        ),
      ],
    ],
  );

  Widget _staffList(List<Staff> staff) => CustomScrollView(
    key: const Key('staff-list'),
    slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                key: const Key('staff-search'),
                controller: _search,
                decoration: const InputDecoration(
                  labelText: '직원 이름 검색',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<_WorkFilter>(
                      key: const Key('work-filter'),
                      initialValue: _work,
                      decoration: const InputDecoration(labelText: '근무 여부'),
                      items: const [
                        DropdownMenuItem(
                          value: _WorkFilter.all,
                          child: Text('전체'),
                        ),
                        DropdownMenuItem(
                          value: _WorkFilter.available,
                          child: Text('근무 가능'),
                        ),
                        DropdownMenuItem(
                          value: _WorkFilter.unavailable,
                          child: Text('근무 불가'),
                        ),
                      ],
                      onChanged: (value) => setState(() => _work = value!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<_AssignmentFilter>(
                      key: const Key('assignment-filter'),
                      initialValue: _assignment,
                      decoration: const InputDecoration(labelText: '배정 상태'),
                      items: const [
                        DropdownMenuItem(
                          value: _AssignmentFilter.all,
                          child: Text('전체'),
                        ),
                        DropdownMenuItem(
                          value: _AssignmentFilter.assigned,
                          child: Text('배정됨'),
                        ),
                        DropdownMenuItem(
                          value: _AssignmentFilter.unassigned,
                          child: Text('미배정'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _assignment = value!),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('${staff.length}명 · ${c.period.label} 배정 기준'),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 8)),
      if (staff.isEmpty)
        const SliverToBoxAdapter(
          child: Center(child: Text('검색·필터에 맞는 직원이 없습니다.')),
        )
      else
        SliverList.builder(
          itemCount: staff.length,
          itemBuilder: (context, index) {
            final person = staff[index];
            final routes = c.routesForStaff(person.id);
            final available = c.staffAvailable(person);
            return ListTile(
              key: ValueKey('staff-${person.id}'),
              selected: person.id == _selectedId,
              leading: Icon(
                available ? Icons.person_outline : Icons.person_off_outlined,
              ),
              title: Text(displayName(person.name)),
              subtitle: Text(
                '${c.isStaffAbsent(person.id)
                    ? '결근'
                    : available
                    ? '근무 가능'
                    : '근무 불가'} · ${routes.isEmpty ? '미배정' : '${routes.length}개 코스 배정'}${c.isStaffAbsent(person.id) && routes.isNotEmpty ? ' · 다른 직원 배정 필요' : ''}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() {
                _selectedId = person.id;
                _focusedPassengerId = null;
                _focusedRouteId = null;
                _mobileDetail = true;
              }),
            );
          },
        ),
    ],
  );

  Future<void> _openOverview({bool passengerSearch = false}) async {
    final selection = await showDialog<AdminScheduleSelection>(
      context: context,
      useRootNavigator: false,
      builder: (_) => AdminAssignmentOverview(
        controller: c,
        passengerSearch: passengerSearch,
      ),
    );
    if (!mounted ||
        selection == null ||
        !c.catalog.staff.any((s) => s.id == selection.staffId)) {
      return;
    }
    _select(selection);
  }

  void _select(AdminScheduleSelection selection) {
    setState(() {
      _overview = false;
      _search.clear();
      _query = '';
      _work = _WorkFilter.all;
      _assignment = _AssignmentFilter.all;
      _selectedId = selection.staffId;
      _mobileDetail = true;
      _focusedPassengerId = selection.passengerId;
      _focusedRouteId = selection.routeId;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _focusedRouteKey.currentContext;
      if (mounted && target != null) Scrollable.ensureVisible(target);
    });
  }

  Widget _detail(String? staffId) {
    if (staffId == null) return const Center(child: Text('목록에서 직원을 선택해 주세요.'));
    final staff = c.staff(staffId);
    final routes = c.routesForStaff(staffId);
    return ListView(
      key: ValueKey('staff-detail-$staffId'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          displayName(staff.name),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(
          c.isStaffAbsent(staffId)
              ? '결근'
              : c.staffAvailable(staff)
              ? '근무 가능'
              : '근무 불가',
        ),
        if (c.supportsAbsences && !c.isCatalogPreview)
          Wrap(
            key: ValueKey('staff-info-$staffId'),
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('직원 정보 및 결근 관리'),
              if (c.supportsAbsences && !c.isCatalogPreview)
                OutlinedButton.icon(
                  key: ValueKey('staff-absence-$staffId'),
                  onPressed: c.busy ? null : () => _editAbsence(staffId),
                  icon: const Icon(Icons.event_busy),
                  label: const Text('결근 등록·취소'),
                ),
            ],
          ),
        if (c.attendanceRepository?.enabled == true)
          AdminWorkPhotos(
            key: ValueKey('attendance-$staffId'),
            repository: c.attendanceRepository!,
            user: c.user,
            staffId: staffId,
            date: dateKey(c.selectedDate),
            period: c.period,
            routeNames: {
              for (final r in c.catalog.baseRoutes) r.id: displayName(r.name),
            },
          ),
        if (c.isStaffAbsent(staffId) && routes.isNotEmpty)
          const Text(
            '결근 직원의 코스 · 다른 직원 배정 필요',
            style: TextStyle(color: Colors.red),
          ),
        const SizedBox(height: 12),
        if (routes.isEmpty) ...[
          const SizedBox(height: 24),
          const Text('이 직원에게 배정된 코스가 없습니다. 기존 코스의 담당 직원을 변경할 수 있습니다.'),
          PopupMenuButton<String>(
            key: ValueKey('assign-course-$staffId'),
            tooltip: '기존 코스 배정',
            onSelected: (routeId) => c.assign(routeId, staffId: staffId),
            itemBuilder: (_) => [
              for (final route in c.draft.routes)
                PopupMenuItem(
                  value: route.baseRouteId,
                  child: Text(
                    '${displayName(c.baseRoute(route.baseRouteId).name)} · 현재 ${displayName(c.staff(route.staffId).name)}',
                  ),
                ),
            ],
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('기존 코스 배정 →'),
            ),
          ),
        ],
        for (final route in routes) _routeEditor(route),
        if (c.draft.absentIds.isNotEmpty || c.draft.excludedIds.isNotEmpty) ...[
          const Divider(),
          const Text('이 시간대 결석·제외 이용자 · 이용자 추가로 선택한 코스에 복귀 가능'),
          Wrap(
            spacing: 8,
            children: [
              for (final id in {...c.draft.absentIds, ...c.draft.excludedIds})
                ActionChip(
                  label: Text(
                    '${displayName(c.passenger(id).name)} · ${c.draft.absentIds.contains(id) ? '결석' : '제외'}',
                  ),
                  tooltip: '기본 코스로 복귀',
                  onPressed: () => c.restorePassenger(id),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _routeEditor(RouteAssignment route) {
    final scope = _editorScope(route.baseRouteId);
    final editing = _assignmentEditors.contains(scope);
    final capacityExceeded =
        route.passengerIds.length >
        c.vehicle(route.vehicleId).passengerCapacity;
    final assignmentConflict =
        !c.staffAvailable(c.staff(route.staffId)) ||
        c.draft.routes.any(
          (r) =>
              r.baseRouteId != route.baseRouteId &&
              (r.staffId == route.staffId || r.vehicleId == route.vehicleId),
        );
    return Card(
      key: _focusedRouteId == route.baseRouteId ? _focusedRouteKey : null,
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              displayName(c.baseRoute(route.baseRouteId).name),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '이용자 ${route.passengerIds.length}/${c.vehicle(route.vehicleId).passengerCapacity}명',
            ),
            Text(
              '담당 직원 · ${displayName(c.staff(route.staffId).name)}',
              key: ValueKey('assigned-staff-${route.baseRouteId}'),
            ),
            Text(
              '담당 차량 · ${displayName(c.vehicle(route.vehicleId).name)}',
              key: ValueKey('assigned-vehicle-${route.baseRouteId}'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ValueKey('edit-assignment-${route.baseRouteId}'),
                onPressed: () => setState(
                  () => editing
                      ? _assignmentEditors.remove(scope)
                      : _assignmentEditors.add(scope),
                ),
                icon: Icon(editing ? Icons.close : Icons.edit_outlined),
                label: Text(editing ? '변경 닫기' : '담당 직원·차량 변경'),
              ),
            ),
            if (capacityExceeded || assignmentConflict)
              TextButton.icon(
                key: ValueKey('fix-assignment-${route.baseRouteId}'),
                onPressed: () => setState(() => _assignmentEditors.add(scope)),
                icon: const Icon(Icons.warning_amber),
                label: Text(
                  capacityExceeded ? '정원 초과 · 차량 변경하기' : '직원·차량 배정 확인하기',
                ),
              ),
            if (c.isStaffAbsent(route.staffId))
              FilledButton.icon(
                key: ValueKey('transfer-course-${route.baseRouteId}'),
                onPressed: c.busy || c.conflict
                    ? null
                    : () => _transferCourse(route),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('코스 넘기기'),
              ),
            if (editing)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 230,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: ValueKey(
                        '${route.baseRouteId}-staff-${route.staffId}',
                      ),
                      initialValue: route.staffId,
                      decoration: const InputDecoration(labelText: '담당 직원'),
                      items: [
                        for (final staff
                            in (c.catalog.staff.toList()
                              ..sort(compareStaffNames)))
                          DropdownMenuItem(
                            value: staff.id,
                            child: Text(
                              '${displayName(staff.name)}${c.staffAvailable(staff) ? '' : ' (근무 불가)'}',
                            ),
                          ),
                      ],
                      onChanged: (id) {
                        if (id != null) {
                          c.assign(route.baseRouteId, staffId: id);
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: 230,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: ValueKey(
                        '${route.baseRouteId}-vehicle-${route.vehicleId}',
                      ),
                      initialValue: route.vehicleId,
                      decoration: const InputDecoration(labelText: '담당 차량'),
                      items: [
                        for (final vehicle in c.catalog.vehicles)
                          DropdownMenuItem(
                            value: vehicle.id,
                            child: Text(
                              '${displayName(vehicle.name)} (${vehicle.passengerCapacity}명)',
                            ),
                          ),
                      ],
                      onChanged: (id) {
                        if (id != null) {
                          c.assign(route.baseRouteId, vehicleId: id);
                        }
                      },
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            const Divider(height: 16),
            Text(
              c.period == TransportPeriod.morning ? '방문 순서 · 약속 시간' : '방문 순서',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            RouteTimeline(
              controller: c,
              route: route,
              compact: true,
              focusedPassengerId: _focusedPassengerId,
              actionsBuilder: (id, index) => Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  if (c.canEditPassengerDetails)
                    TextButton.icon(
                      key: ValueKey('passenger-details-$id'),
                      onPressed: () => _editPassengerDetails(id),
                      icon: const Icon(Icons.person_outline, size: 18),
                      label: const Text('기본 시간·특이사항'),
                    ),
                  if (c.period == TransportPeriod.morning)
                    TextButton.icon(
                      key: ValueKey('time-$id'),
                      onPressed: () => _editTime(route, passengerId: id),
                      icon: const Icon(Icons.schedule, size: 18),
                      label: const Text('이 날짜 시간 변경'),
                    ),
                  IconButton(
                    key: ValueKey('up-$id'),
                    tooltip: '방문 순서 위로',
                    onPressed: index == 0
                        ? null
                        : () => c.reorder(route.baseRouteId, index, -1),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    key: ValueKey('down-$id'),
                    tooltip: '방문 순서 아래로',
                    onPressed: index == route.passengerIds.length - 1
                        ? null
                        : () => c.reorder(route.baseRouteId, index, 1),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  TextButton(
                    key: ValueKey('move-$id'),
                    onPressed: () => _reassign(route, id),
                    child: const Text('재배정 →'),
                  ),
                  TextButton(
                    key: ValueKey('exclude-$id'),
                    onPressed: () => c.excludePassenger(id),
                    child: const Text('제외'),
                  ),
                  TextButton(
                    key: ValueKey('absent-$id'),
                    onPressed: () => c.markAbsent(id),
                    child: const Text('결석'),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              key: ValueKey('add-${route.baseRouteId}'),
              onPressed: () => _addPassenger(route),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('이용자 추가·복귀·재배정'),
            ),
            ExpansionTile(
              key: ValueKey('course-settings-$scope'),
              tilePadding: EdgeInsets.zero,
              title: const Text('추가 설정'),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '기본 방문 순서: ${c.baseRoute(route.baseRouteId).passengerIds.map((id) => displayName(c.passenger(id).name)).join(' → ')}',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _transferCourse(RouteAssignment route) async {
    final snapshot = c.draft;
    final revision = c.absenceRevisionKey;
    final catalog = c.catalog;
    final target = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (_) => CourseReassignmentDialog(
        catalog: catalog,
        snapshot: snapshot,
        route: route,
        absentStaffIds: {
          for (final staff in catalog.staff)
            if (c.isStaffAbsent(staff.id)) staff.id,
        },
      ),
    );
    if (target == null || !mounted) return;
    if (c.busy ||
        c.loading ||
        c.dataError != null ||
        c.availabilityLoading ||
        c.availabilityError != null ||
        c.conflict ||
        !identical(snapshot, c.draft) ||
        !identical(catalog, c.catalog) ||
        revision != c.absenceRevisionKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('일정 또는 결근 상태가 변경되었습니다. 대상을 다시 확인해 주세요.')),
      );
      return;
    }
    try {
      c.reassignAbsentCourse(route.baseRouteId, target);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${displayName(c.staff(route.staffId).name)} → ${displayName(c.staff(target).name)} · 담당 직원을 바꿨습니다. 내용을 확인하고 일정을 확정해 주세요.',
          ),
        ),
      );
    } on StateError catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(easyScheduleMessage(error.message))),
      );
    }
  }

  Future<void> _reassign(RouteAssignment route, String passengerId) async {
    final snapshot = c.draft;
    final target = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (_) => ReassignmentDialog(
        catalog: c.catalog,
        snapshot: snapshot,
        sourceStaffId: route.staffId,
        passengerId: passengerId,
        absentStaffIds: c.absences.values
            .where((a) => a.periods.contains(c.period))
            .map((a) => a.staffId)
            .toSet(),
      ),
    );
    if (target == null || !mounted) return;
    if (c.loading ||
        c.busy ||
        c.availabilityLoading ||
        c.availabilityError != null ||
        c.dataError != null ||
        !identical(snapshot, c.draft)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('일정이 변경되었거나 조회 중입니다. 재배정 대상을 다시 확인해 주세요.'),
        ),
      );
      return;
    }
    c.movePassenger(passengerId, target);
  }

  Future<void> _editTime(
    RouteAssignment route, {
    required String passengerId,
  }) async {
    if (c.period != TransportPeriod.morning) return;
    final snapshot = c.draft;
    final minute = route.estimatedVisitMinutes[passengerId];
    final manual = route.estimatedVisitSources[passengerId] == 'manual';
    final result = await showDialog<List<int?>>(
      context: context,
      useRootNavigator: false,
      builder: (_) => EstimatedTimeDialog(
        title: '${displayName(c.passenger(passengerId).name)} 약속 시간',
        defaultMinute: c.passenger(passengerId).defaultMorningMinute,
        labels: const ['이 날짜의 약속 시간(선택)'],
        guidance: minute != null && !manual
            ? '이전 기록 ${minuteLabel(minute)}은 약속 여부를 확인해야 합니다. 약속한 시간을 직접 입력해 주세요.'
            : '약속한 시간을 입력하세요. 비우고 저장하면 약속 시간이 지워집니다.',
        minutes: [manual ? minute : null],
      ),
    );
    if (result == null ||
        !mounted ||
        !identical(snapshot, c.draft) ||
        c.busy ||
        c.loading ||
        c.conflict ||
        c.dataError != null ||
        c.availabilityLoading ||
        c.availabilityError != null) {
      return;
    }
    // A blank legacy/reference field is not an instruction to erase that record.
    if (!manual && result[0] == null) return;
    c.setVisitMinute(route.baseRouteId, passengerId, result[0]);
  }

  Future<void> _editPassengerDetails(String id) async {
    final original = c.passenger(id);
    final version = c.catalog.version;
    final result = await showDialog<({String note, int? minute})>(
      context: context,
      useRootNavigator: false,
      builder: (_) => PassengerDetailsDialog(passenger: original),
    );
    if (result == null ||
        !mounted ||
        c.catalog.version != version ||
        !identical(c.passenger(id), original) ||
        c.busy ||
        c.loading) {
      return;
    }
    try {
      await c.savePassengerDetails(
        id,
        note: result.note,
        defaultMorningMinute: result.minute,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('기본 정보를 저장했습니다.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '기본 정보를 저장하지 못했습니다. 다른 관리자의 변경이나 연결 상태를 확인하고 다시 불러와 주세요.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _editAbsence(String staffId) async {
    final day = dateKey(c.selectedDate);
    final existing = c.absences[staffId];
    var scope = c.period.name;
    final result = await showDialog<({Set<TransportPeriod> periods, bool absent})>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, change) => AlertDialog(
          scrollable: true,
          title: Text('${displayName(c.staff(staffId).name)} · $day 결근'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '현재 결근: ${existing == null || existing.periods.isEmpty ? '없음' : existing.periods.map((p) => p.label).join(' · ')}',
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                key: const Key('absence-scope'),
                segments: const [
                  ButtonSegment(value: 'morning', label: Text('오전')),
                  ButtonSegment(value: 'afternoon', label: Text('오후')),
                  ButtonSegment(value: 'all', label: Text('종일')),
                ],
                selected: {scope},
                onSelectionChanged: (v) => change(() => scope = v.single),
              ),
              const SizedBox(height: 12),
              const Text('선택한 날짜에만 적용됩니다. 담당 코스는 다른 직원에게 넘긴 뒤 일정을 확정해 주세요.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
            OutlinedButton(
              key: const Key('cancel-staff-absence'),
              onPressed: () => Navigator.pop(context, (
                periods: scope == 'all'
                    ? TransportPeriod.values.toSet()
                    : {TransportPeriod.values.byName(scope)},
                absent: false,
              )),
              child: const Text('결근 취소'),
            ),
            FilledButton(
              key: const Key('register-staff-absence'),
              onPressed: () => Navigator.pop(context, (
                periods: scope == 'all'
                    ? TransportPeriod.values.toSet()
                    : {TransportPeriod.values.byName(scope)},
                absent: true,
              )),
              child: const Text('결근 등록'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (day != dateKey(c.selectedDate) ||
        c.busy ||
        c.loading ||
        c.dataError != null ||
        c.availabilityLoading ||
        c.availabilityError != null) {
      return;
    }
    await c.setStaffAbsence(
      staffId,
      result.periods,
      result.absent,
      existing?.version ?? 0,
    );
  }

  Future<void> _addPassenger(RouteAssignment route) async {
    final snapshot = c.draft;
    var query = '';
    final id = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final candidates = c.catalog.passengers
              .where(
                (person) =>
                    !route.passengerIds.contains(person.id) &&
                    displayName(person.name)
                        .contains(displayName(query.trim())) &&
                    c.catalog.baseRoutes
                        .where((r) => r.period == c.period)
                        .any((r) => r.passengerIds.contains(person.id)),
              )
              .toList();
          return AlertDialog(
            title: const Text('이용자 추가·복귀·재배정'),
            content: SizedBox(
              width: 440,
              height: 350,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(labelText: '이용자 이름 검색'),
                    onChanged: (value) => setDialogState(() => query = value),
                  ),
                  const SizedBox(height: 8),
                  const Text('다른 직원의 이용자를 선택하면 이 코스로 옮깁니다.'),
                  Expanded(
                    child: candidates.isEmpty
                        ? const Center(child: Text('추가할 이용자가 없습니다.'))
                        : ListView.builder(
                            itemCount: candidates.length,
                            itemBuilder: (_, index) {
                              final person = candidates[index];
                              final sources = c.draft.routes.where(
                                (r) => r.passengerIds.contains(person.id),
                              );
                              final status = sources.isNotEmpty
                                  ? '${displayName(c.staff(sources.first.staffId).name)}에게서 이동'
                                  : c.draft.absentIds.contains(person.id)
                                  ? '결석 복귀'
                                  : '제외 복귀';
                              return ListTile(
                                key: ValueKey('add-person-${person.id}'),
                                title: Text(displayName(person.name)),
                                subtitle: Text(status),
                                onTap: () => Navigator.pop(context, person.id),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
            ],
          );
        },
      ),
    );
    if (id != null &&
        mounted &&
        identical(snapshot, c.draft) &&
        !c.busy &&
        !c.loading &&
        c.dataError == null &&
        !c.availabilityLoading &&
        c.availabilityError == null) {
      c.addPassenger(id, route.baseRouteId);
    }
  }
}
