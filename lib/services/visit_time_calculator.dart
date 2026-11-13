import '../models/transport.dart';

/// A future travel-time strategy can implement this without touching the UI.
abstract class VisitTimeCalculator {
  String get source;
  Map<String, int> calculate(
    List<String> orderedIds,
    int firstMinute,
    int intervalMinutes,
  );
}

class FixedIntervalVisitTimeCalculator implements VisitTimeCalculator {
  const FixedIntervalVisitTimeCalculator();
  static const defaultIntervalMinutes = 5;
  @override
  String get source => 'fixedInterval';
  @override
  Map<String, int> calculate(
    List<String> orderedIds,
    int firstMinute,
    int intervalMinutes,
  ) {
    if (orderedIds.isEmpty) throw ArgumentError('방문 이용자가 없는 코스입니다.');
    if (orderedIds.toSet().length != orderedIds.length) {
      throw ArgumentError('이용자 방문이 중복되어 있습니다.');
    }
    if (firstMinute < 0 || firstMinute >= 1440) {
      throw ArgumentError('첫 방문 시각은 00:00~23:59 범위여야 합니다.');
    }
    if (intervalMinutes <= 0) throw ArgumentError('방문 간격은 1분 이상이어야 합니다.');
    if (firstMinute + (orderedIds.length - 1) * intervalMinutes >= 1440) {
      throw ArgumentError('계산 시각이 자정을 넘습니다. 첫 시각이나 간격을 줄여 주세요.');
    }
    return Map.unmodifiable({
      for (var i = 0; i < orderedIds.length; i++)
        orderedIds[i]: firstMinute + i * intervalMinutes,
    });
  }
}

List<String> visitTimeWarnings(RouteAssignment route, Map<String, int> times) {
  final warnings = <String>[];
  if ((route.startMinute == null) != (route.endMinute == null) ||
      (route.startMinute != null &&
          route.endMinute != null &&
          (route.startMinute! < 0 ||
              route.endMinute! >= 1440 ||
              route.startMinute! >= route.endMinute!))) {
    warnings.add('예상 운행 시작·종료 시각이 올바르지 않습니다.');
  }
  int? previous;
  for (final id in route.passengerIds) {
    final minute = times[id];
    if (minute == null) continue;
    if (minute < 0 || minute >= 1440) warnings.add('방문 시각이 당일 범위를 벗어납니다.');
    if (previous != null && minute <= previous) {
      warnings.add('방문 순서와 예상 시각이 역전되거나 중복됩니다.');
    }
    if ((route.startMinute != null && minute < route.startMinute!) ||
        (route.endMinute != null && minute > route.endMinute!)) {
      warnings.add('방문 시각이 기존 예상 운행 시간 범위와 충돌합니다.');
    }
    previous = minute;
  }
  return List.unmodifiable(warnings.toSet());
}

class VisitTimePreview {
  VisitTimePreview._({
    required this.snapshot,
    required this.route,
    required Map<String, int> calculated,
    required Map<String, int> result,
    required Map<String, String> sources,
    required Set<String> protectedIds,
    required Set<String> manualChanges,
  }) : calculated = Map.unmodifiable(calculated),
       result = Map.unmodifiable(result),
       sources = Map.unmodifiable(sources),
       protectedIds = Set.unmodifiable(protectedIds),
       manualChanges = Set.unmodifiable(manualChanges),
       warnings = visitTimeWarnings(route, result),
       existingWarnings = visitTimeWarnings(route, route.estimatedVisitMinutes);
  final ScheduleSnapshot snapshot;
  final RouteAssignment route;
  final Map<String, int> calculated, result;
  final Map<String, String> sources;
  final Set<String> protectedIds, manualChanges;
  final List<String> warnings, existingWarnings;
}

VisitTimePreview previewVisitTimes(
  ScheduleSnapshot snapshot,
  String routeId,
  int firstMinute,
  int intervalMinutes, {
  bool replaceManual = false,
  VisitTimeCalculator calculator = const FixedIntervalVisitTimeCalculator(),
}) {
  final route = snapshot.routes.firstWhere((r) => r.baseRouteId == routeId);
  final calculated = calculator.calculate(
    route.passengerIds,
    firstMinute,
    intervalMinutes,
  );
  final result = <String, int>{};
  final sources = <String, String>{};
  final protected = <String>{};
  final changed = <String>{};
  for (final id in route.passengerIds) {
    final old = route.estimatedVisitMinutes[id];
    if (route.isManualEstimate(id) &&
        (!replaceManual || old == calculated[id])) {
      result[id] = old!;
      sources[id] = 'manual';
      protected.add(id);
    } else {
      result[id] = calculated[id]!;
      sources[id] = calculator.source;
      if (route.isManualEstimate(id) && old != calculated[id]) changed.add(id);
    }
  }
  return VisitTimePreview._(
    snapshot: snapshot,
    route: route,
    calculated: calculated,
    result: result,
    sources: sources,
    protectedIds: protected,
    manualChanges: changed,
  );
}
