import 'transport.dart';

class StaffAbsence {
  StaffAbsence({
    required this.staffId,
    required Iterable<TransportPeriod> periods,
    required this.version,
  }) : periods = Set.unmodifiable(periods);
  final String staffId;
  final Set<TransportPeriod> periods;
  final int version;

  factory StaffAbsence.fromJson(
    String staffId,
    Map<String, dynamic> data, {
    String? date,
  }) {
    final version = data['version'];
    final raw = data['unavailablePeriods'];
    if (version is! int ||
        version < 1 ||
        raw is! List ||
        raw.any((v) => v != 'morning' && v != 'afternoon') ||
        raw.toSet().length != raw.length ||
        (date != null &&
            (data['schemaVersion'] != 1 ||
                data['date'] != date ||
                data['staffId'] != staffId))) {
      throw const FormatException('Invalid staff absence');
    }
    return StaffAbsence(
      staffId: staffId,
      periods: raw.map((p) => TransportPeriod.values.byName(p as String)),
      version: version,
    );
  }
}
