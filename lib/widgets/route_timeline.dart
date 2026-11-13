import 'package:flutter/material.dart';

import '../models/transport.dart';
import '../services/schedule_controller.dart';

class RouteTimeline extends StatelessWidget {
  const RouteTimeline({
    super.key,
    required this.controller,
    required this.route,
    this.actionsBuilder,
    this.compact = false,
    this.focusedPassengerId,
    this.collapseNotes = false,
  });
  final ScheduleController controller;
  final RouteAssignment route;
  final Widget Function(String passengerId, int index)? actionsBuilder;
  final bool compact;
  final String? focusedPassengerId;
  final bool collapseNotes;

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
    if (collapseNotes && passenger.note.isEmpty) {
      return ListTile(
        key: ValueKey('timeline-$id'),
        leading: CircleAvatar(radius: 16, child: Text('${index + 1}')),
        title: Text(passenger.name, key: ValueKey('visit-$id')),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '예상 ${minuteLabel(route.estimatedVisitMinutes[id])}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            Text(passenger.address),
          ],
        ),
      );
    }
    if (compact || collapseNotes) {
      return ExpansionTile(
        key: collapseNotes
            ? ValueKey('timeline-$id')
            : ValueKey('compact-$id-${focusedPassengerId == id}'),
        initiallyExpanded: focusedPassengerId == id,
        leading: CircleAvatar(radius: 16, child: Text('${index + 1}')),
        title: Text(passenger.name, key: ValueKey('visit-$id')),
        subtitle: collapseNotes
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '예상 ${minuteLabel(route.estimatedVisitMinutes[id])}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(passenger.address),
                  if (passenger.note.isNotEmpty)
                    const Text('특이사항 보기', style: TextStyle(fontSize: 12)),
                ],
              )
            : Text(
                '${passenger.address}\n예상 ${minuteLabel(route.estimatedVisitMinutes[id])}',
              ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (passenger.note.isNotEmpty) Text(passenger.note),
          if (actionsBuilder != null) actionsBuilder!(id, index),
        ],
      );
    }
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
