import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../models/transport.dart';
import '../services/schedule_controller.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, this.controller});
  final ScheduleController? controller;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late final ScheduleController c = widget.controller ?? ScheduleController();

  @override
  void dispose() {
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: c.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '송영 날짜 선택',
    );
    if (date != null && mounted) c.selectDate(date);
  }

  Future<void> _confirm() async {
    final snapshot = c.draft;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${c.period.label} 일정 확정'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${dateKey(c.selectedDate)} · ${c.period.time}'),
                const SizedBox(height: 12),
                for (final route in snapshot.routes) ...[
                  Text(
                    c.baseRoute(route.baseRouteId).name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${c.staff(route.staffId).name} · ${c.vehicle(route.vehicleId).name}',
                  ),
                  Text(
                    route.passengerIds.isEmpty
                        ? '송영 대상 없음'
                        : route.passengerIds
                              .map((id) => c.passenger(id).name)
                              .join(' → '),
                  ),
                  const SizedBox(height: 12),
                ],
                Text('결석 ${snapshot.absentIds.length}명'),
                const SizedBox(height: 12),
                const Text('확정하면 이 시간대의 전체 일정이 직원 화면에 반영됩니다.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('계속 수정'),
          ),
          FilledButton(
            key: const Key('approve-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('확정하여 공유'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    // A dialog reviews one immutable snapshot; reject an unexpected state change.
    if (!identical(snapshot, c.draft)) return;
    c.confirm();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('일정을 확정했습니다. 직원 화면에서 확인할 수 있습니다.')),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final admin = c.role == DemoRole.admin;
      final routes = admin ? c.draft.routes : c.staffRoutes;
      final errors = admin ? c.validationErrors : <String>[];
      final confirmed = c.confirmed;
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            '다정 송영 관리',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  '가상 주간보호센터 · MVP 시제품',
                  style: TextStyle(
                    color: Color(0xFF147D73),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  admin
                      ? '오늘의 이동을 함께 준비해요'
                      : '${c.staff(c.staffId).name}님의 송영 일정',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('가상 데이터만 사용합니다. 새로고침하면 수정·확정 내역이 초기화됩니다.'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SegmentedButton<DemoRole>(
                      segments: const [
                        ButtonSegment(
                          value: DemoRole.admin,
                          label: Text('관리자'),
                          icon: Icon(Icons.edit_calendar),
                        ),
                        ButtonSegment(
                          value: DemoRole.staff,
                          label: Text('직원'),
                          icon: Icon(Icons.person_outline),
                        ),
                      ],
                      selected: {c.role},
                      onSelectionChanged: (roles) => c.selectRole(roles.first),
                    ),
                    const Text('임시 역할 전환'),
                    if (!admin)
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('staff-${c.staffId}'),
                          initialValue: c.staffId,
                          decoration: const InputDecoration(
                            labelText: '시연할 직원',
                          ),
                          items: [
                            for (final staff in DemoData.staff)
                              DropdownMenuItem(
                                value: staff.id,
                                child: Text(staff.name),
                              ),
                          ],
                          onChanged: (id) {
                            if (id != null) c.selectStaff(id);
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: '이전 날짜',
                      onPressed: () => c.selectDate(
                        DateTime(
                          c.selectedDate.year,
                          c.selectedDate.month,
                          c.selectedDate.day - 1,
                        ),
                      ),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Text(dateKey(c.selectedDate)),
                    ),
                    IconButton(
                      tooltip: '다음 날짜',
                      onPressed: () => c.selectDate(
                        DateTime(
                          c.selectedDate.year,
                          c.selectedDate.month,
                          c.selectedDate.day + 1,
                        ),
                      ),
                      icon: const Icon(Icons.chevron_right),
                    ),
                    SegmentedButton<TransportPeriod>(
                      segments: const [
                        ButtonSegment(
                          value: TransportPeriod.morning,
                          label: Text('오전'),
                        ),
                        ButtonSegment(
                          value: TransportPeriod.afternoon,
                          label: Text('오후'),
                        ),
                      ],
                      selected: {c.period},
                      onSelectionChanged: (periods) =>
                          c.selectPeriod(periods.first),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _notice(
                  admin ? Icons.edit_note : Icons.verified_outlined,
                  admin
                      ? (confirmed == null
                            ? '작성 중 · 아직 확정하지 않은 일정입니다.'
                            : c.hasPendingChanges
                            ? '수정 중 · 직원에게는 확정본 v${confirmed.version}이 표시됩니다.'
                            : '확정 완료 · v${confirmed.version}')
                      : (confirmed == null
                            ? '아직 확정된 일정이 없습니다.'
                            : '최신 확정 일정 · v${confirmed.version}'),
                  '${c.period.label} ${c.period.time} · ${c.period == TransportPeriod.morning ? '자택 → 센터' : '센터 → 자택'}',
                ),
                if (admin) ...[
                  const SizedBox(height: 12),
                  const Text('결석과 편집은 선택한 날짜·시간대에만 적용됩니다. 기본 코스는 유지됩니다.'),
                  if (c.draft.absentIds.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('결석 이용자 · 복귀 시 기본 코스의 마지막 순서에 추가'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final id in c.draft.absentIds)
                          InputChip(
                            label: Text(c.passenger(id).name),
                            deleteIcon: const Icon(Icons.undo, size: 18),
                            deleteButtonTooltipMessage: '결석 취소',
                            onDeleted: () => c.restorePassenger(id),
                          ),
                      ],
                    ),
                  ],
                ],
                const SizedBox(height: 16),
                if (routes.isEmpty)
                  _notice(
                    Icons.event_available,
                    '배정된 확정 일정이 없습니다.',
                    '관리자가 이 날짜·시간대의 일정을 확정하면 본인에게 배정된 코스가 표시됩니다.',
                  ),
                for (final route in routes) _routeCard(route, admin),
                if (admin) ...[
                  const SizedBox(height: 8),
                  _notice(
                    errors.isEmpty
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    errors.isEmpty ? '일정 검증 통과' : '확정 전 수정이 필요합니다',
                    errors.isEmpty
                        ? '직원 근무 · 차량 정원 · 중복 배정 · 이용자 누락을 확인했습니다.'
                        : errors.join('\n'),
                    error: errors.isNotEmpty,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('confirm-schedule'),
                    onPressed:
                        errors.isEmpty &&
                            (confirmed == null || c.hasPendingChanges)
                        ? _confirm
                        : null,
                    icon: const Icon(Icons.check),
                    label: Text('${c.period.label} 전체 일정 검토 및 확정'),
                  ),
                ],
                const SizedBox(height: 24),
                const Text(
                  '시연 기준: 코스당 직원 1명 · 시간대 내 코스 동시 운행 · 정원은 이용자 수 기준',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _notice(
    IconData icon,
    String title,
    String detail, {
    bool error = false,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFFEDEC) : const Color(0xFFE6F2EF),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: error ? Colors.red.shade800 : const Color(0xFF147D73),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(detail),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _routeCard(RouteAssignment route, bool admin) {
    final base = c.baseRoute(route.baseRouteId);
    final vehicle = c.vehicle(route.vehicleId);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFDDE5E5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              base.name,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${c.staff(route.staffId).name} · ${vehicle.name} · 이용자 ${route.passengerIds.length}/${vehicle.passengerCapacity}명',
            ),
            if (admin) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        '${dateKey(c.selectedDate)}-${route.baseRouteId}-${route.staffId}',
                      ),
                      initialValue: route.staffId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '담당 직원'),
                      items: [
                        for (final staff in DemoData.staff)
                          DropdownMenuItem(
                            value: staff.id,
                            child: Text(
                              '${staff.name}${staff.isAvailable(c.selectedDate, c.period) ? '' : ' (근무 불가)'}',
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
                    width: 240,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        '${dateKey(c.selectedDate)}-${route.baseRouteId}-${route.vehicleId}',
                      ),
                      initialValue: route.vehicleId,
                      decoration: const InputDecoration(labelText: '배정 차량'),
                      items: [
                        for (final v in DemoData.vehicles)
                          DropdownMenuItem(
                            value: v.id,
                            child: Text('${v.name} (${v.passengerCapacity}명)'),
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
              const SizedBox(height: 12),
              Text(
                '기본 방문 순서: ${base.passengerIds.map((id) => c.passenger(id).name.replaceFirst('가상 어르신 ', '')).join(' → ')}',
                style: const TextStyle(color: Colors.black54),
              ),
            ],
            const Divider(height: 28),
            if (route.passengerIds.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('송영 대상 이용자가 없습니다.'),
              ),
            for (var i = 0; i < route.passengerIds.length; i++)
              _passengerRow(route, i, admin),
          ],
        ),
      ),
    );
  }

  Widget _passengerRow(RouteAssignment route, int index, bool admin) {
    final id = route.passengerIds[index];
    final passenger = c.passenger(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 17, child: Text('${index + 1}')),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      passenger.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(passenger.address),
                    Text(
                      passenger.note,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (admin)
            Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  key: ValueKey('up-$id'),
                  tooltip: '${passenger.name} 위로',
                  onPressed: index > 0
                      ? () => c.reorder(route.baseRouteId, index, -1)
                      : null,
                  icon: const Icon(Icons.arrow_upward, size: 20),
                ),
                IconButton(
                  key: ValueKey('down-$id'),
                  tooltip: '${passenger.name} 아래로',
                  onPressed: index < route.passengerIds.length - 1
                      ? () => c.reorder(route.baseRouteId, index, 1)
                      : null,
                  icon: const Icon(Icons.arrow_downward, size: 20),
                ),
                PopupMenuButton<String>(
                  key: ValueKey('move-$id'),
                  tooltip: '${passenger.name} 코스 이동',
                  onSelected: (routeId) => c.movePassenger(id, routeId),
                  itemBuilder: (_) => [
                    for (final r in c.draft.routes.where(
                      (r) => r.baseRouteId != route.baseRouteId,
                    ))
                      PopupMenuItem(
                        value: r.baseRouteId,
                        child: Text('${c.baseRoute(r.baseRouteId).name}로 이동'),
                      ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('코스 이동 ▾'),
                  ),
                ),
                TextButton.icon(
                  key: ValueKey('absent-$id'),
                  onPressed: () => c.markAbsent(id),
                  icon: const Icon(Icons.person_off_outlined, size: 18),
                  label: const Text('결석'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
