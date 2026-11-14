import '../models/transport.dart';

String? visitTimeText(
  TransportPeriod period,
  RouteAssignment route,
  String id,
) {
  if (period != TransportPeriod.morning) return null;
  final minute = route.estimatedVisitMinutes[id];
  return minute != null && route.estimatedVisitSources[id] == 'manual'
      ? '약속 시간 ${minuteLabel(minute)}'
      : null;
}
