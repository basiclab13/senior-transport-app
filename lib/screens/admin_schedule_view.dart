import 'package:flutter/material.dart';

import 'attendance_screen.dart';

import '../models/transport.dart';
import '../models/visit_time_review.dart';
import '../services/schedule_controller.dart';
import '../services/visit_time_calculator.dart';
import '../widgets/estimated_time_dialog.dart';
import '../widgets/route_timeline.dart';
import '../widgets/admin_assignment_overview.dart';
import '../widgets/admin_transport_dashboard.dart';
import '../widgets/reassignment_dialog.dart';
import '../widgets/course_reassignment_dialog.dart';
import '../widgets/bulk_visit_time_dialog.dart';
import '../utils/staff_sort.dart';
import '../utils/schedule_wording.dart';

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
    return staff.name.contains(_query.trim()) &&
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
              title: Text(person.name),
              subtitle: Text(
                '${c.isStaffAbsent(person.id)
                    ? '결근'
                    : available
                    ? '근무 가능'
                    : '근무 불가'} · ${routes.isEmpty ? '미배정' : '${routes.length}개 코스 배정'}${c.isStaffAbsent(person.id) && routes.isNotEmpty ? ' · 다른 직원 배정 필요' : ''}${routes.any((r) => c.pendingTimeReviewRouteIds.contains(r.baseRouteId)) ? ' · 방문 시간 확인 필요' : ''}',
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
          '${staff.name}님의 송영 일정',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(
          '${dateKey(c.selectedDate)} · ${c.period.label} · ${c.isStaffAbsent(staffId)
              ? '결근'
              : c.staffAvailable(staff)
              ? '근무 가능'
              : '근무 불가'}',
        ),
        if (c.attendanceRepository?.enabled == true || c.supportsAbsences)
          ExpansionTile(
            key: ValueKey('staff-info-$staffId'),
            tilePadding: EdgeInsets.zero,
            dense: true,
            title: const Text('직원 정보 · 결근/사진'),
            children: [
              if (c.attendanceRepository?.enabled == true)
                OutlinedButton.icon(
                  key: ValueKey('attendance-$staffId'),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('업무 시작·종료 기록 보기'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AttendanceScreen(
                        controller: c,
                        staffId: staff.id,
                        staffName: staff.name,
                        date: c.selectedDate,
                        period: c.period,
                      ),
                    ),
                  ),
                ),
              if (c.supportsAbsences)
                OutlinedButton.icon(
                  key: ValueKey('staff-absence-$staffId'),
                  onPressed: c.busy ? null : () => _editAbsence(staffId),
                  icon: const Icon(Icons.event_busy),
                  label: const Text('날짜별 결근 등록·취소'),
                ),
            ],
          ),
        if (c.isStaffAbsent(staffId) && routes.isNotEmpty)
          const Text(
            '결근 직원의 코스 · 다른 직원 배정 필요',
            style: TextStyle(color: Colors.red),
          ),
        const SizedBox(height: 12),
        const Text('방문 시각은 관리자 입력 예상 시간이며 실제 운행 시각과 다를 수 있습니다.'),
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
                    '${c.baseRoute(route.baseRouteId).name} · 현재 ${c.staff(route.staffId).name}',
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
                    '${c.passenger(id).name} · ${c.draft.absentIds.contains(id) ? '결석' : '제외'}',
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
    final operatingWarning = visitTimeWarnings(
      route,
      route.estimatedVisitMinutes,
    ).any((warning) => warning.contains('운행'));
    return Card(
      key: _focusedRouteId == route.baseRouteId ? _focusedRouteKey : null,
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              c.baseRoute(route.baseRouteId).name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '이용자 ${route.passengerIds.length}/${c.vehicle(route.vehicleId).passengerCapacity}명',
            ),
            Text(
              '담당 직원 · ${c.staff(route.staffId).name}',
              key: ValueKey('assigned-staff-${route.baseRouteId}'),
            ),
            Text(
              '담당 차량 · ${c.vehicle(route.vehicleId).name}',
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
            if (operatingWarning)
              TextButton.icon(
                key: ValueKey('fix-operating-${route.baseRouteId}'),
                onPressed: () => _editTime(route),
                icon: const Icon(Icons.warning_amber),
                label: const Text('운행 시간 범위 확인·수정'),
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
                              '${staff.name}${c.staffAvailable(staff) ? '' : ' (근무 불가)'}',
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
                              '${vehicle.name} (${vehicle.passengerCapacity}명)',
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
            if (c.timeReviews[route.baseRouteId] case final review?) ...[
              Card(
                color: review.decision == VisitTimeReviewDecision.pending
                    ? Theme.of(context).colorScheme.errorContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.decision.label,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        review.decision == VisitTimeReviewDecision.pending
                            ? '방문 순서가 바뀌었습니다. 위의 「변경된 방문 시간 맞추기」를 누르거나 기존 시간을 확인해 주세요.'
                            : '방문 시간 확인을 마쳤습니다. 다른 변경사항을 확인한 후 최종 확정해 주세요.',
                      ),
                      if (review.decision == VisitTimeReviewDecision.pending)
                        TextButton(
                          key: ValueKey('keep-times-${route.baseRouteId}'),
                          onPressed: () => _keepTimes(route),
                          child: const Text('기존 시간 그대로 쓰기'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const Divider(height: 16),
            const Text(
              '방문 순서 · 예상 방문 시각',
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
                  TextButton.icon(
                    key: ValueKey('time-$id'),
                    onPressed: () => _editTime(route, passengerId: id),
                    icon: const Icon(Icons.schedule, size: 18),
                    label: const Text('시각 수정'),
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
            OutlinedButton.icon(
              key: ValueKey('bulk-time-${route.baseRouteId}'),
              onPressed: () => _bulkTimes(route),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(
                c.pendingTimeReviewRouteIds.contains(route.baseRouteId)
                    ? '방문 시간 다시 맞추기'
                    : '방문 시간 맞추기',
              ),
            ),
            ExpansionTile(
              key: ValueKey('course-settings-$scope'),
              tilePadding: EdgeInsets.zero,
              title: const Text('추가 설정'),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  key: ValueKey('operating-${route.baseRouteId}'),
                  onPressed: () => _editTime(route),
                  icon: const Icon(Icons.schedule),
                  label: Text(
                    '예상 운행 ${minuteLabel(route.startMinute)}–${minuteLabel(route.endMinute)}',
                  ),
                ),
                Text(
                  '기본 방문 순서: ${c.baseRoute(route.baseRouteId).passengerIds.map((id) => c.passenger(id).name).join(' → ')}',
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
            '${c.staff(route.staffId).name} → ${c.staff(target).name} · 담당 직원 변경 완료. 전체 직원 변경 검토·확정이 필요합니다.',
          ),
        ),
      );
    } on StateError catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
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

  Future<void> _keepTimes(RouteAssignment route) async {
    final snapshot = c.draft;
    final revision = c.absenceRevisionKey;
    final warnings = visitTimeWarnings(route, route.estimatedVisitMinutes);
    final missing = route.passengerIds
        .where((id) => !route.estimatedVisitMinutes.containsKey(id))
        .length;
    final approved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('기존 방문 시간 확인'),
        content: SizedBox(
          width: 480,
          height: 300,
          child: ListView(
            children: [
              Text(
                '${dateKey(snapshot.date)} · ${snapshot.period.label} · ${c.baseRoute(route.baseRouteId).name}',
              ),
              const Text('변경된 방문 순서의 기존 시각을 확인해 주세요. 실제 운행 시각이 아닌 예상 시각입니다.'),
              for (final id in route.passengerIds)
                Text(
                  '${c.passenger(id).name} · ${minuteLabel(route.estimatedVisitMinutes[id])}',
                ),
              if (missing > 0) Text('예상 시각 미입력 $missing명: 유지하면 미입력 상태로 남습니다.'),
              if (route.passengerIds.isEmpty) const Text('방문 이용자가 없는 코스입니다.'),
              for (final warning in warnings)
                Text(easyScheduleMessage(warning)),
              if (warnings.isNotEmpty) const Text('방문 시간을 다시 맞춘 뒤 확인해 주세요.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const Key('approve-keep-times'),
            onPressed: warnings.isEmpty
                ? () => Navigator.pop(context, true)
                : null,
            child: const Text('검토 완료 · 기존 시간 그대로 쓰기'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    try {
      if (revision != c.absenceRevisionKey) {
        throw StateError('결근 상태가 변경되었습니다. 다시 검토해 주세요.');
      }
      c.keepVisitTimes(route.baseRouteId, expectedSnapshot: snapshot);
    } on StateError catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _bulkTimes(RouteAssignment route) async {
    final snapshot = c.draft;
    final catalog = c.catalog;
    final revision = c.absenceRevisionKey;
    final result = await showDialog<VisitTimeApplication>(
      context: context,
      useRootNavigator: false,
      builder: (_) => BulkVisitTimeDialog(
        catalog: catalog,
        snapshot: snapshot,
        routeId: route.baseRouteId,
      ),
    );
    if (result == null || !mounted) return;
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
        const SnackBar(
          content: Text('일정 또는 결근 상태가 변경되었습니다. 최신 방문 순서로 다시 계산해 주세요.'),
        ),
      );
      return;
    }
    c.applyVisitTimePreview(
      result.preview,
      manualOverwriteConfirmed: result.manualOverwriteConfirmed,
    );
  }

  Future<void> _editTime(RouteAssignment route, {String? passengerId}) async {
    final snapshot = c.draft;
    final result = await showDialog<List<int?>>(
      context: context,
      useRootNavigator: false,
      builder: (_) => EstimatedTimeDialog(
        title: passengerId == null
            ? '예상 운행 시간 수정'
            : '${c.passenger(passengerId).name} 예상 방문 시각',
        labels: passengerId == null ? ['예상 출발', '예상 종료'] : ['예상 방문'],
        minutes: passengerId == null
            ? [route.startMinute, route.endMinute]
            : [route.estimatedVisitMinutes[passengerId]],
      ),
    );
    if (result == null ||
        !mounted ||
        !identical(snapshot, c.draft) ||
        c.busy ||
        c.loading ||
        c.dataError != null ||
        c.availabilityLoading ||
        c.availabilityError != null) {
      return;
    }
    if (passengerId == null) {
      c.setOperatingWindow(route.baseRouteId, result[0], result[1]);
    } else {
      c.setVisitMinute(route.baseRouteId, passengerId, result[0]);
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
          title: Text('${c.staff(staffId).name} · $day 결근'),
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
              const Text(
                '선택한 날짜에만 적용됩니다. 담당 코스가 남으면 다른 직원 배정 필요로 표시되며, 일정은 자동으로 수정·확정되지 않습니다.',
              ),
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
                    person.name.contains(query.trim()) &&
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
                  const Text(
                    '다른 직원의 이용자를 선택하면 해당 배정에서 이동합니다. 예상 방문 시각은 다시 입력해 주세요.',
                  ),
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
                                  ? '${c.staff(sources.first.staffId).name}에게서 이동'
                                  : c.draft.absentIds.contains(person.id)
                                  ? '결석 복귀'
                                  : '제외 복귀';
                              return ListTile(
                                key: ValueKey('add-person-${person.id}'),
                                title: Text(person.name),
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
