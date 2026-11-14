import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:senior_transport_app/data/demo_data.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/schedule_catalog.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';
import 'package:senior_transport_app/services/schedule_repository.dart';

DateTime fixtureClock() => DateTime.utc(2026, 11, 12, 0);

/// Existing editor regressions explicitly enter the editor from the new home.
Future<void> openAdminEditor(WidgetTester tester) async {
  if (find.byKey(const Key('admin-dashboard')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('admin-editor')));
    await tester.pumpAndSettle();
  }
}

Future<void> openStaffInfo(WidgetTester tester, String id) async {
  if (find.byKey(ValueKey('staff-absence-$id')).evaluate().isNotEmpty) {
    return;
  }
  final tile = find.byKey(ValueKey('staff-info-$id'));
  await tester.scrollUntilVisible(
    tile,
    -100,
    scrollable: find
        .descendant(
          of: find.byKey(ValueKey('staff-detail-$id')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

ScheduleCatalog demoCatalog() => ScheduleCatalog(
  version: 'test-v1',
  staff: DemoData.staff,
  vehicles: DemoData.vehicles,
  passengers: DemoData.passengers,
  baseRoutes: DemoData.baseRoutes,
);

ScheduleCatalog largeCatalog() {
  final staff = [...DemoData.staff];
  final vehicles = [...DemoData.vehicles];
  final passengers = [...DemoData.passengers];
  final routes = [...DemoData.baseRoutes];
  for (var i = 4; i <= 40; i++) {
    staff.add(Staff('s$i', '가상 직원 $i'));
    vehicles.add(Vehicle('v$i', '가상 차량 $i', 4));
    final ids = <String>[];
    for (var j = 0; j < 2; j++) {
      final id = 'p${passengers.length + 1}';
      ids.add(id);
      passengers.add(
        Passenger(
          id,
          '가상 이용자 ${passengers.length + 1}',
          '가상도시 테스트길 $i-$j',
          '가상 데이터',
        ),
      );
    }
    for (final period in TransportPeriod.values) {
      routes.add(
        BaseRoute(
          id: '${period.name}-extra-$i',
          name: '가상 $i코스',
          period: period,
          staffId: 's$i',
          vehicleId: 'v$i',
          passengerIds: ids,
        ),
      );
    }
  }
  return ScheduleCatalog(
    version: 'scale-v1',
    staff: staff,
    vehicles: vehicles,
    passengers: passengers,
    baseRoutes: routes,
  );
}

ScheduleController fixtureController({
  required AppUser user,
  DateTime? initialDate,
  DateTime Function()? clock,
  List<ScheduleSnapshot> initialConfirmed = const [],
}) => ScheduleController(
  user: user,
  catalog: demoCatalog(),
  initialDate: initialDate,
  clock: clock ?? fixtureClock,
  initialConfirmed: initialConfirmed,
);

class MemoryScheduleRepository implements ScheduleRepository {
  MemoryScheduleRepository({ScheduleCatalog? catalog})
    : catalog = catalog ?? demoCatalog();
  final ScheduleCatalog catalog;
  final changes = StreamController<ScheduleViewData>.broadcast();
  final Map<String, ScheduleSnapshot> snapshots = {};
  Object? publishFailure;
  Completer<void>? hold;
  bool receipt = false;
  final requests = <String>[];
  String key(DateTime date, TransportPeriod period) =>
      '${dateKey(date)}_${period.name}';
  @override
  Stream<ScheduleViewData> watch(
    AppUser user,
    DateTime date,
    TransportPeriod period,
  ) async* {
    yield await load(user, date, period);
    yield* changes.stream;
  }

  @override
  Future<ScheduleViewData> load(
    AppUser user,
    DateTime date,
    TransportPeriod period,
  ) async => ScheduleViewData(catalog, snapshots[key(date, period)]);
  @override
  Future<void> publish(
    ScheduleSnapshot snapshot,
    String catalogVersion,
    int expectedVersion,
    String requestId,
  ) async {
    requests.add(requestId);
    if (hold != null) await hold!.future;
    if (publishFailure != null) throw publishFailure!;
    snapshots[key(snapshot.date, snapshot.period)] = snapshot.copyWith(
      version: expectedVersion + 1,
      confirmedAt: DateTime.now(),
    );
  }

  @override
  Future<bool> committed(
    DateTime date,
    TransportPeriod period,
    String requestId,
  ) async => receipt;
}
