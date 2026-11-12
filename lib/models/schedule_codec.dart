import 'transport.dart';

Map<String, dynamic> routeToJson(RouteAssignment route) => {
  'baseRouteId': route.baseRouteId,
  'staffId': route.staffId,
  'vehicleId': route.vehicleId,
  'passengerIds': route.passengerIds,
  'estimatedVisitMinutes': route.estimatedVisitMinutes,
  'startMinute': route.startMinute,
  'endMinute': route.endMinute,
};

Map<String, dynamic> scheduleToJson(ScheduleSnapshot snapshot) => {
  'date': dateKey(snapshot.date),
  'period': snapshot.period.name,
  'routes': snapshot.routes.map(routeToJson).toList(),
  'absentIds': snapshot.absentIds.toList()..sort(),
  'excludedIds': snapshot.excludedIds.toList()..sort(),
};

ScheduleSnapshot scheduleFromJson(
  Map<String, dynamic> data,
  DateTime confirmedAt,
) {
  if (data['schemaVersion'] != 1 ||
      data['status'] != 'confirmed' ||
      data['timezone'] != 'Asia/Seoul' ||
      (data['version'] as int) < 1) {
    throw const FormatException('Invalid schedule schema');
  }
  return ScheduleSnapshot(
    date: DateTime.parse(data['date'] as String),
    period: TransportPeriod.values.byName(data['period'] as String),
    routes: (data['routes'] as List).map((raw) {
      final r = Map<String, dynamic>.from(raw as Map);
      return RouteAssignment(
        baseRouteId: r['baseRouteId'] as String,
        staffId: r['staffId'] as String,
        vehicleId: r['vehicleId'] as String,
        passengerIds: List<String>.from(r['passengerIds'] as List),
        estimatedVisitMinutes: Map<String, int>.from(
          r['estimatedVisitMinutes'] as Map,
        ),
        startMinute: r['startMinute'] as int?,
        endMinute: r['endMinute'] as int?,
      );
    }).toList(),
    absentIds: Set<String>.from(data['absentIds'] as List),
    excludedIds: Set<String>.from(data['excludedIds'] as List),
    version: data['version'] as int,
    confirmedAt: confirmedAt,
  );
}
