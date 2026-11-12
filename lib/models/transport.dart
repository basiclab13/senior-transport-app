enum TransportPeriod {
  morning('오전', '08:00–09:30'),
  afternoon('오후', '16:00–17:30');

  const TransportPeriod(this.label, this.time);
  final String label;
  final String time;
}

enum DemoRole { admin, staff }

String dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class Staff {
  const Staff(this.id, this.name, {this.unavailableWeekdays = const {}});
  final String id;
  final String name;
  final Set<int> unavailableWeekdays;

  bool isAvailable(DateTime date, TransportPeriod period) =>
      !unavailableWeekdays.contains(date.weekday);
}

class Passenger {
  const Passenger(this.id, this.name, this.address, this.note);
  final String id;
  final String name;
  final String address;
  final String note;
}

class Vehicle {
  const Vehicle(this.id, this.name, this.passengerCapacity);
  final String id;
  final String name;
  // Demo capacity counts passengers only, excluding the single driver.
  final int passengerCapacity;
}

class BaseRoute {
  BaseRoute({
    required this.id,
    required this.name,
    required this.period,
    required this.staffId,
    required this.vehicleId,
    required List<String> passengerIds,
  }) : passengerIds = List.unmodifiable(passengerIds);

  final String id;
  final String name;
  final TransportPeriod period;
  final String staffId;
  final String vehicleId;
  final List<String> passengerIds;
}

class RouteAssignment {
  RouteAssignment({
    required this.baseRouteId,
    required this.staffId,
    required this.vehicleId,
    required List<String> passengerIds,
  }) : passengerIds = List.unmodifiable(passengerIds);

  final String baseRouteId;
  final String staffId;
  final String vehicleId;
  final List<String> passengerIds;

  RouteAssignment copyWith({
    String? staffId,
    String? vehicleId,
    List<String>? passengerIds,
  }) => RouteAssignment(
    baseRouteId: baseRouteId,
    staffId: staffId ?? this.staffId,
    vehicleId: vehicleId ?? this.vehicleId,
    passengerIds: passengerIds ?? this.passengerIds,
  );
}

/// Immutable snapshot of an entire date/period. Publishing replaces it atomically.
class ScheduleSnapshot {
  ScheduleSnapshot({
    required this.date,
    required this.period,
    required List<RouteAssignment> routes,
    Set<String> absentIds = const {},
    this.version = 0,
    this.confirmedAt,
  }) : routes = List.unmodifiable(routes),
       absentIds = Set.unmodifiable(absentIds);

  final DateTime date;
  final TransportPeriod period;
  final List<RouteAssignment> routes;
  final Set<String> absentIds;
  final int version;
  final DateTime? confirmedAt;

  ScheduleSnapshot copyWith({
    List<RouteAssignment>? routes,
    Set<String>? absentIds,
    int? version,
    DateTime? confirmedAt,
  }) => ScheduleSnapshot(
    date: date,
    period: period,
    routes: routes ?? this.routes,
    absentIds: absentIds ?? this.absentIds,
    version: version ?? this.version,
    confirmedAt: confirmedAt ?? this.confirmedAt,
  );
}
