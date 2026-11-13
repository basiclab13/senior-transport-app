import 'schedule_catalog.dart';
import 'transport.dart';

/// An ephemeral proposal tied to exactly the draft that was sent to the server.
/// Protected fields are constructed locally, never accepted from AI output.
class AiScheduleSuggestion {
  AiScheduleSuggestion.fromJson(
    Map<String, dynamic> data, {
    required this.origin,
    required this.catalog,
    required this.confirmed,
    required this.absenceRevision,
    required this.generation,
  }) {
    if (data['date'] != dateKey(origin.date) ||
        data['period'] != origin.period.name ||
        data['catalogVersion'] != catalog.version ||
        data['expectedVersion'] != (confirmed?.version ?? 0)) {
      throw const FormatException('추천 대상 일정이 일치하지 않습니다.');
    }
    reasons = List.unmodifiable(List<String>.from(data['reasons'] as List));
    warnings = List.unmodifiable(List<String>.from(data['warnings'] as List));
    distanceComparison = data['distanceComparison'] == null
        ? null
        : ScheduleDistanceComparison.fromJson(
            Map<String, dynamic>.from(data['distanceComparison'] as Map),
          );
    final raw = data['routes'] as List;
    final byId = <String, Map<String, dynamic>>{};
    for (final value in raw) {
      final r = Map<String, dynamic>.from(value as Map);
      final id = r['baseRouteId'] as String;
      if (r.keys.any(
            (k) => !['baseRouteId', 'staffId', 'passengerIds'].contains(k),
          ) ||
          byId.containsKey(id) ||
          !origin.routes.any((r) => r.baseRouteId == id)) {
        throw const FormatException('추천 코스 또는 변경 필드가 올바르지 않습니다.');
      }
      byId[id] = r;
    }
    if (byId.length != origin.routes.length) {
      throw const FormatException('추천 코스가 누락되었습니다.');
    }
    final minutes = {for (final r in origin.routes) ...r.estimatedVisitMinutes};
    final sources = {for (final r in origin.routes) ...r.estimatedVisitSources};
    candidate = origin.copyWith(
      routes: [
        for (final old in origin.routes)
          old.copyWith(
            staffId: byId[old.baseRouteId]!['staffId'] as String,
            passengerIds: List<String>.from(
              byId[old.baseRouteId]!['passengerIds'] as List,
            ),
            estimatedVisitMinutes: {
              for (final id in List<String>.from(
                byId[old.baseRouteId]!['passengerIds'] as List,
              ))
                if (minutes.containsKey(id)) id: minutes[id]!,
            },
            estimatedVisitSources: {
              for (final id in List<String>.from(
                byId[old.baseRouteId]!['passengerIds'] as List,
              ))
                if (minutes.containsKey(id) && sources.containsKey(id))
                  id: sources[id]!,
            },
          ),
      ],
    );
  }
  final ScheduleSnapshot origin;
  final ScheduleSnapshot? confirmed;
  final ScheduleCatalog catalog;
  final String absenceRevision;
  final int generation;
  late final ScheduleSnapshot candidate;
  late final List<String> reasons, warnings;
  late final ScheduleDistanceComparison? distanceComparison;
}

class ScheduleDistanceComparison {
  ScheduleDistanceComparison.fromJson(Map<String, dynamic> data) {
    if (data['method'] != 'fictional-euclidean-round-trip-v1' ||
        data['beforeKm'] is! num ||
        data['afterKm'] is! num) {
      throw const FormatException('거리 비교 형식을 확인해 주세요.');
    }
    beforeKm = (data['beforeKm'] as num).toDouble();
    afterKm = (data['afterKm'] as num).toDouble();
    if (!beforeKm.isFinite ||
        !afterKm.isFinite ||
        beforeKm < 0 ||
        afterKm < 0) {
      throw const FormatException('거리 비교 값이 올바르지 않습니다.');
    }
  }
  late final double beforeKm, afterKm;
  double get reductionKm => beforeKm - afterKm;
  bool get improved => reductionKm > 0.001;
  bool get worsened => reductionKm < -0.001;
  String get summary {
    if (!improved && !worsened) return '추정 이동 거리 개선이 없습니다(1m 이내 차이는 동일).';
    final amount = reductionKm.abs();
    final percent = beforeKm == 0 ? null : amount / beforeKm * 100;
    final ratio = percent == null
        ? '기존 0km로 비율 계산 불가'
        : percent < 0.01
        ? '0.01% 미만'
        : '${percent.toStringAsFixed(2)}%';
    return '${improved ? '감소' : '증가'} ${amount.toStringAsFixed(3)} km · $ratio${worsened ? ' · 거리 개선안이 아닙니다.' : ''}';
  }
}
