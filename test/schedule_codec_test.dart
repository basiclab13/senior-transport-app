import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/schedule_catalog.dart';
import 'package:senior_transport_app/models/schedule_codec.dart';
import 'package:senior_transport_app/models/transport.dart';

void main() {
  test('Firestore wire format preserves order, estimated minutes, exclusion and version', () {
    final confirmedAt = DateTime.utc(2026, 11, 12, 1);
    final snapshot = ScheduleSnapshot(
      date: DateTime(2026, 11, 12),
      period: TransportPeriod.morning,
      routes: [
        RouteAssignment(
          baseRouteId: 'morning-a',
          staffId: 's40',
          vehicleId: 'v40',
          passengerIds: ['p2', 'p1'],
          estimatedVisitMinutes: {'p2': 490, 'p1': 500},
          startMinute: 480,
          endMinute: 540,
        ),
      ],
      absentIds: {'p3'},
      excludedIds: {'p4'},
    );
    final decoded = scheduleFromJson({
      ...scheduleToJson(snapshot),
      'schemaVersion': 1,
      'status': 'confirmed',
      'timezone': 'Asia/Seoul',
      'version': 7,
    }, confirmedAt);
    expect(decoded.routes.single.passengerIds, ['p2', 'p1']);
    expect(decoded.routes.single.estimatedVisitMinutes, {'p2': 490, 'p1': 500});
    expect(decoded.routes.single.startMinute, 480);
    expect(decoded.absentIds, {'p3'});
    expect(decoded.excludedIds, {'p4'});
    expect(decoded.confirmedAt, confirmedAt);
    expect(decoded.version, 7);
    expect(
      () => decoded.routes.single.estimatedVisitMinutes.clear(),
      throwsUnsupportedError,
    );
  });

  test('unsupported/unconfirmed server records are rejected', () {
    expect(
      () => scheduleFromJson({'schemaVersion': 99}, DateTime.now()),
      throwsFormatException,
    );
  });

  test('inactive master employee remains displayable but is unavailable for assignment', () {
    final catalog = ScheduleCatalog.fromJson('test-v1', {
      'staff': [
        {
          'id': 's40',
          'name': '가상 직원 40',
          'active': false,
          'unavailableWeekdays': [],
        },
      ],
      'vehicles': [],
      'passengers': [],
      'baseRoutes': [],
    });
    expect(catalog.staff.single.id, 's40');
    expect(
      catalog.staff.single.isAvailable(
        DateTime(2026, 11, 12),
        TransportPeriod.morning,
      ),
      isFalse,
    );
  });
}
