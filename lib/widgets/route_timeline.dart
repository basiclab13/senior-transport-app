import 'package:flutter/material.dart';

import '../models/transport.dart';
import '../services/schedule_controller.dart';

class RouteTimeline extends StatelessWidget {
  const RouteTimeline({
    super.key,
    required this.controller,
    required this.route,
    this.actionsBuilder,
  });
  final ScheduleController controller;
  final RouteAssignment route;
  final Widget Function(String passengerId, int index)? actionsBuilder;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (route.passengerIds.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('송영 대상 이용자가 없습니다.'),
        ),
      for (var i = 0; i < route.passengerIds.length; i++)
        _stop(context, route.passengerIds[i], i),
    ],
  );

  Widget _stop(BuildContext context, String id, int index) {
    final passenger = controller.passenger(id);
    return IntrinsicHeight(
      child: Row(
        key: ValueKey('timeline-$id'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 42,
            child: Column(
              children: [
                CircleAvatar(radius: 16, child: Text('${index + 1}')),
                if (index < route.passengerIds.length - 1)
                  const Expanded(child: VerticalDivider(thickness: 2)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '예상 ${minuteLabel(route.estimatedVisitMinutes[id])}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    passenger.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(passenger.address),
                  Text(
                    passenger.note,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  if (actionsBuilder != null) actionsBuilder!(id, index),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
