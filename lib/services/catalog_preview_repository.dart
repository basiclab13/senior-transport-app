import '../models/app_user.dart';
import '../models/schedule_catalog.dart';
import '../models/staff_absence.dart';
import '../models/transport.dart';
import 'schedule_repository.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

const previewCatalogVersion = 'ai-test-25x80-v1';
const previewManifestHash =
    '1d9288075fc24a9f6c806f88eaa941b3bc535cc92a43de0c07c132e9034be38c';
const previewScenarios = <String, String>{
  'unchanged': '정상 일정 · 변경이 필요 없는 상황',
  'passenger-absence': '이용자 1명 결석',
  'order-improvement': '방문 순서 조정',
  'absence-capacity-improvement': '교차 배정과 결석 · 빈자리로 이동',
  'staff-absence': '직원 1명 결근 · 예비 직원 인계',
  'five-staff-absent': '직원 5명 결근 · 예비 5명 인계',
  'six-staff-absent': '직원 6명 결근 · 배정 불가능',
};

class CatalogPreviewData {
  CatalogPreviewData(
    this.catalog,
    Iterable<String> assigned,
    Iterable<String> reserve,
  ) : assignedStaffOrder = List.unmodifiable(assigned),
      assignedStaffIds = Set.unmodifiable(assigned),
      reserveStaffIds = Set.unmodifiable(reserve) {
    final staffIds = catalog.staff.map((s) => s.id).toSet();
    if (catalog.version != previewCatalogVersion ||
        catalog.staff.length != 25 ||
        catalog.passengers.length != 80 ||
        catalog.vehicles.length != 20 ||
        catalog.baseRoutes.length != 40 ||
        assignedStaffIds.length != 20 ||
        reserveStaffIds.length != 5 ||
        assignedStaffIds.intersection(reserveStaffIds).isNotEmpty ||
        !staffIds.containsAll(assignedStaffIds.union(reserveStaffIds)) ||
        catalog.vehicles.any((v) => v.passengerCapacity != 4)) {
      throw const FormatException('Invalid preview fixture');
    }
    final passengers = catalog.passengers.map((p) => p.id).toSet();
    final vehicles = catalog.vehicles.map((v) => v.id).toSet();
    for (final period in TransportPeriod.values) {
      final routes = catalog.baseRoutes
          .where((r) => r.period == period)
          .toList();
      final ids = routes.expand((r) => r.passengerIds).toList();
      if (routes.length != 20 ||
          routes.map((r) => r.staffId).toSet().length != 20 ||
          routes.map((r) => r.vehicleId).toSet().length != 20 ||
          routes.any(
            (r) =>
                !assignedStaffIds.contains(r.staffId) ||
                !vehicles.contains(r.vehicleId) ||
                r.passengerIds.length != 4,
          ) ||
          ids.length != 80 ||
          ids.toSet().length != 80 ||
          !passengers.containsAll(ids)) {
        throw const FormatException('Invalid preview assignments');
      }
    }
  }
  final ScheduleCatalog catalog;
  final List<String> assignedStaffOrder;
  final Set<String> assignedStaffIds;
  final Set<String> reserveStaffIds;
  factory CatalogPreviewData.fromJson(
    Map<String, dynamic> metadata,
    Map<String, dynamic> collections,
  ) {
    if (metadata['ready'] != true ||
        metadata['fictional'] != true ||
        metadata['testData'] != true ||
        metadata['manifestSha256'] != previewManifestHash) {
      throw const FormatException('Preview catalog not verified');
    }
    final fixture = Map<String, dynamic>.from(metadata['fixture'] as Map);
    return CatalogPreviewData(
      ScheduleCatalog.fromJson(previewCatalogVersion, collections),
      List<String>.from(fixture['assignedStaffIds'] as List),
      List<String>.from(fixture['reserveStaffIds'] as List),
    );
  }
}

abstract class CatalogPreviewSource {
  bool get allowsPreviewRequests;
  Future<CatalogPreviewData> load(AppUser user);
  Future<Map<String, dynamic>> suggest(Map<String, dynamic> request);
}

class FirebaseCatalogPreviewSource implements CatalogPreviewSource {
  FirebaseCatalogPreviewSource(this.base);
  final FirebaseScheduleRepository base;
  @override
  bool get allowsPreviewRequests =>
      base.allowsAiSuggestions &&
      const bool.fromEnvironment('ENABLE_AI_CATALOG_PREVIEW_REQUESTS');
  @override
  Future<CatalogPreviewData> load(AppUser user) async {
    if (user.role != UserRole.admin) throw StateError('관리자 전용 테스트입니다.');
    const server = GetOptions(source: Source.server);
    final root = base.firestore.doc('catalogs/$previewCatalogVersion');
    final metadata = (await root.get(server)).data();
    if (metadata == null) {
      throw const FormatException('Preview catalog missing');
    }
    final collections = <String, dynamic>{};
    for (final name in ['staff', 'vehicles', 'passengers', 'baseRoutes']) {
      final docs = await root.collection(name).get(server);
      collections[name] = docs.docs
          .map((d) => {...d.data(), 'id': d.id})
          .toList();
    }
    return CatalogPreviewData.fromJson(metadata, collections);
  }

  @override
  Future<Map<String, dynamic>> suggest(Map<String, dynamic> request) {
    if (!allowsPreviewRequests) throw StateError('미리보기 AI 요청이 비활성 상태입니다.');
    return base.suggestSchedule(request);
  }
}

class CatalogPreviewRepository
    implements
        ScheduleRepository,
        StaffAvailabilityRepository,
        ScheduleSuggestionRepository,
        CatalogPreviewScope {
  CatalogPreviewRepository({
    required this.data,
    required this.source,
    required this.user,
    required this.scenario,
  }) {
    if (user.role != UserRole.admin ||
        !previewScenarios.containsKey(scenario)) {
      throw StateError('허용된 관리자 테스트 상황을 선택해 주세요.');
    }
  }
  final CatalogPreviewData data;
  final CatalogPreviewSource source;
  final AppUser user;
  final String scenario;
  TransportPeriod _period = TransportPeriod.morning;
  @override
  Map<String, dynamic> get previewContext => {
    'kind': 'ai25-catalog-preview',
    'scenario': scenario,
    'manifestSha256': previewManifestHash,
  };
  @override
  Set<String> get reserveStaffIds => data.reserveStaffIds;
  List<String> get absentStaffIds {
    final count = scenario == 'staff-absence'
        ? 1
        : scenario == 'five-staff-absent'
        ? 5
        : scenario == 'six-staff-absent'
        ? 6
        : 0;
    return data.assignedStaffOrder.take(count).toList();
  }

  void _check(AppUser actor) {
    if (actor.uid != user.uid || actor.role != UserRole.admin) {
      throw StateError('관리자 테스트 권한을 확인해 주세요.');
    }
  }

  @override
  Stream<ScheduleViewData> watch(
    AppUser actor,
    DateTime date,
    TransportPeriod period,
  ) async* {
    _check(actor);
    _period = period;
    yield await load(actor, date, period);
  }

  @override
  Future<ScheduleViewData> load(
    AppUser actor,
    DateTime date,
    TransportPeriod period,
  ) async {
    _check(actor);
    _period = period;
    return ScheduleViewData(
      data.catalog,
      null,
      previewDraft: buildPreviewDraft(data.catalog, scenario, date, period),
    );
  }

  @override
  Stream<Map<String, StaffAbsence>> watchAbsences(
    AppUser actor,
    DateTime date,
  ) async* {
    _check(actor);
    await Future<void>.delayed(Duration.zero);
    yield {
      for (final id in absentStaffIds)
        id: StaffAbsence(staffId: id, periods: {_period}, version: 1),
    };
  }

  @override
  bool get allowsAiSuggestions =>
      source.allowsPreviewRequests &&
      data.catalog.staff.length - absentStaffIds.length >=
          data.assignedStaffIds.length;
  @override
  Future<Map<String, dynamic>> suggestSchedule(Map<String, dynamic> request) {
    if (!allowsAiSuggestions ||
        request['catalogVersion'] != previewCatalogVersion ||
        request['expectedVersion'] != 0 ||
        request['previewContext'] is! Map ||
        (request['previewContext'] as Map)['scenario'] != scenario ||
        (request['previewContext'] as Map)['kind'] != 'ai25-catalog-preview' ||
        (request['previewContext'] as Map)['manifestSha256'] !=
            previewManifestHash) {
      throw StateError('테스트 문맥을 확인해 주세요.');
    }
    return source.suggest(request);
  }

  Never _noWrite() =>
      throw StateError('테스트 화면에서는 서버에 일정을 저장하거나 결근을 등록하지 않습니다.');
  @override
  Future<void> publish(
    ScheduleSnapshot snapshot,
    String catalogVersion,
    int expectedVersion,
    String requestId,
  ) async => _noWrite();
  @override
  Future<void> publishWithAvailability(
    ScheduleSnapshot snapshot,
    String catalogVersion,
    int expectedVersion,
    String requestId,
    Map<String, int> versions,
  ) async => _noWrite();
  @override
  Future<bool> committed(
    DateTime date,
    TransportPeriod period,
    String requestId,
  ) async => _noWrite();
  @override
  Future<StaffAbsence> setAbsence(Map<String, dynamic> request) async =>
      _noWrite();
}

ScheduleSnapshot buildPreviewDraft(
  ScheduleCatalog catalog,
  String scenario,
  DateTime date,
  TransportPeriod period,
) {
  if (!previewScenarios.containsKey(scenario)) {
    throw const FormatException('Unknown preview scenario');
  }
  final first = period == TransportPeriod.morning ? 540 : 1020;
  final routes = catalog.baseRoutes.where((r) => r.period == period).toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  final values = routes
      .map(
        (r) => RouteAssignment(
          baseRouteId: r.id,
          staffId: r.staffId,
          vehicleId: r.vehicleId,
          passengerIds: r.passengerIds,
          startMinute: first - 10,
          endMinute: first + 40,
          estimatedVisitMinutes: {
            for (var i = 0; i < r.passengerIds.length; i++)
              r.passengerIds[i]: first + i * 5,
          },
          estimatedVisitSources: {
            for (final id in r.passengerIds) id: 'manual',
          },
        ),
      )
      .toList();
  final absent = <String>{};
  if (scenario == 'order-improvement') {
    values[0] = values[0].copyWith(
      passengerIds: ['p1', 'p3', 'p2', 'p4'],
      estimatedVisitMinutes: {
        'p1': first,
        'p3': first + 5,
        'p2': first + 10,
        'p4': first + 15,
      },
    );
  } else if (scenario == 'passenger-absence' ||
      scenario == 'absence-capacity-improvement') {
    absent.add('p2');
    if (scenario == 'absence-capacity-improvement') {
      values[0] = values[0].copyWith(
        passengerIds: ['p5', 'p3', 'p4'],
        estimatedVisitMinutes: {
          'p5': first,
          'p3': first + 10,
          'p4': first + 15,
        },
        estimatedVisitSources: {'p5': 'manual', 'p3': 'manual', 'p4': 'manual'},
      );
      values[1] = values[1].copyWith(
        passengerIds: ['p1', 'p6', 'p7', 'p8'],
        estimatedVisitMinutes: {
          'p1': first,
          'p6': first + 5,
          'p7': first + 10,
          'p8': first + 15,
        },
        estimatedVisitSources: {
          'p1': 'manual',
          'p6': 'manual',
          'p7': 'manual',
          'p8': 'manual',
        },
      );
    } else {
      values[0] = values[0].copyWith(
        passengerIds: ['p1', 'p3', 'p4'],
        estimatedVisitMinutes: {
          'p1': first,
          'p3': first + 10,
          'p4': first + 15,
        },
        estimatedVisitSources: {'p1': 'manual', 'p3': 'manual', 'p4': 'manual'},
      );
    }
  }
  return ScheduleSnapshot(
    date: date,
    period: period,
    routes: values,
    absentIds: absent,
  );
}
