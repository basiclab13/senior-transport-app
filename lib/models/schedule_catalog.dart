import 'transport.dart';

class ScheduleCatalog {
  ScheduleCatalog({
    required this.version,
    required Iterable<Staff> staff,
    required Iterable<Vehicle> vehicles,
    required Iterable<Passenger> passengers,
    required Iterable<BaseRoute> baseRoutes,
  }) : staff = List.unmodifiable(staff),
       vehicles = List.unmodifiable(vehicles),
       passengers = List.unmodifiable(passengers),
       baseRoutes = List.unmodifiable(baseRoutes);

  factory ScheduleCatalog.empty() => ScheduleCatalog(
    version: '',
    staff: [],
    vehicles: [],
    passengers: [],
    baseRoutes: [],
  );
  final String version;
  final List<Staff> staff;
  final List<Vehicle> vehicles;
  final List<Passenger> passengers;
  final List<BaseRoute> baseRoutes;

  factory ScheduleCatalog.fromJson(String version, Map<String, dynamic> data) {
    List<Map<String, dynamic>> entries(String key) => (data[key] as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
    return ScheduleCatalog(
      version: version,
      staff: entries('staff').map(
        (s) => Staff(
          s['id'] as String,
          s['name'] as String,
          active: s['active'] as bool,
          unavailableWeekdays: Set<int>.from(
            s['unavailableWeekdays'] as List? ?? [],
          ),
        ),
      ),
      vehicles: entries('vehicles').map(
        (v) => Vehicle(
          v['id'] as String,
          v['name'] as String,
          v['passengerCapacity'] as int,
        ),
      ),
      passengers: entries('passengers').map(
        (p) => Passenger(
          p['id'] as String,
          p['name'] as String,
          p['address'] as String,
          p['note'] as String,
        ),
      ),
      baseRoutes: entries('baseRoutes').map(
        (r) => BaseRoute(
          id: r['id'] as String,
          name: r['name'] as String,
          period: TransportPeriod.values.byName(r['period'] as String),
          staffId: r['staffId'] as String,
          vehicleId: r['vehicleId'] as String,
          passengerIds: List<String>.from(r['passengerIds'] as List),
        ),
      ),
    );
  }
}
