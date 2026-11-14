import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/display_wording.dart';

import '../models/transport.dart';
import '../services/schedule_controller.dart';
import '../widgets/route_timeline.dart';
import 'attendance_screen.dart';

class StaffScheduleView extends StatelessWidget {
  const StaffScheduleView({
    super.key,
    required this.controller,
    this.photoPicker,
  });
  final ScheduleController controller;
  final Future<Uint8List?> Function()? photoPicker;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final person = c.staff(c.staffId!);
    final absent = c.isStaffAbsent(person.id);
    final routes = c.staffRoutes;
    final available = !absent && !c.confirmedReassignmentNeeded;
    final routeId = available && routes.length == 1
        ? routes.single.baseRouteId
        : null;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          key: const Key('my-schedule'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            Text(
              '${displayName(person.name)}님',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (absent)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '선택한 ${c.period.label}은 결근으로 등록되어 있습니다. 담당 일정은 관리자에게 확인해 주세요.',
                  key: const Key('staff-absence-warning'),
                ),
              )
            else if (c.confirmedReassignmentNeeded)
              const Text('담당 일정을 다시 확인해야 합니다. 관리자에게 문의해 주세요.')
            else if (c.confirmed == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('아직 확정된 일정이 없습니다. 관리자에게 확인해 주세요.'),
              )
            else if (routes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('선택한 날짜·시간대에 배정된 코스가 없습니다. 관리자에게 확인해 주세요.'),
              ),
            if (available)
              for (final route in routes)
                Card(
                  key: ValueKey('my-course-${route.baseRouteId}'),
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayName(
                                  c.baseRoute(route.baseRouteId).name,
                                ),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            Text('이용자 ${route.passengerIds.length}명'),
                          ],
                        ),
                        Text(
                          '담당 차량 · ${displayName(c.vehicle(route.vehicleId).name)}',
                        ),
                      ],
                    ),
                  ),
                ),
            AttendanceScreen(
              key: ValueKey(
                'work-photos-${dateKey(c.selectedDate)}-${c.period.name}-$routeId',
              ),
              embedded: true,
              controller: c,
              staffId: person.id,
              staffName: displayName(person.name),
              date: c.selectedDate,
              period: c.period,
              routeId: routeId,
              photoPicker: photoPicker,
            ),
            if (available && routes.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                '방문 순서',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final route in routes)
                RouteTimeline(controller: c, route: route, collapseNotes: true),
            ],
          ],
        ),
      ),
    );
  }
}
