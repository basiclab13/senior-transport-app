import 'package:flutter/material.dart';

import '../models/transport.dart';
import '../services/schedule_controller.dart';
import '../widgets/route_timeline.dart';
import 'attendance_screen.dart';

class StaffScheduleView extends StatelessWidget {
  const StaffScheduleView({super.key, required this.controller});
  final ScheduleController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final person = c.staff(c.staffId!);
    final routes = c.staffRoutes;
    return ListView(
      key: const Key('my-schedule'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${person.name}님의 ${c.period.label} 송영 일정',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          '${dateKey(c.selectedDate)} · ${c.period == TransportPeriod.morning ? '자택 → 센터' : '센터 → 자택'}',
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            '방문 시각과 운행 시간은 관리자가 입력한 예상 시간이며 실제 운행 시각과 다를 수 있습니다. 미입력 시각은 별도 확인이 필요합니다.',
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('attendance'),
          icon: const Icon(Icons.camera_alt_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AttendanceScreen(
                staffName: person.name,
                date: c.selectedDate,
                period: c.period,
              ),
            ),
          ),
          label: const Text('출퇴근 사진 인증 안내 · 준비 중'),
        ),
        const SizedBox(height: 16),
        if (c.confirmed == null)
          const Text('아직 확정된 일정이 없습니다.')
        else ...[
          Text(
            c.confirmedReassignmentNeeded
                ? '기존 확정 이력 · v${c.confirmed!.version} · 결근으로 재배정 필요'
                : '최신 확정 일정 · v${c.confirmed!.version}',
          ),
          if (routes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('이 날짜·시간대에 본인에게 배정된 확정 일정이 없습니다.'),
            ),
        ],
        for (final route in routes)
          Card(
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
                  const SizedBox(height: 8),
                  Text('담당 차량 · ${c.vehicle(route.vehicleId).name}'),
                  Text(
                    route.startMinute == null || route.endMinute == null
                        ? '예상 운행 시간 · 미입력'
                        : '예상 운행 ${minuteLabel(route.startMinute)}–${minuteLabel(route.endMinute)} · ${route.endMinute! - route.startMinute!}분',
                  ),
                  const Divider(height: 32),
                  RouteTimeline(controller: c, route: route),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
