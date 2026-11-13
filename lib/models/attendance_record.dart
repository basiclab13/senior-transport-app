import 'dart:typed_data';

import 'transport.dart';

enum WorkPhotoKind {
  start('업무 시작'),
  end('업무 종료');

  const WorkPhotoKind(this.label);
  final String label;
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.staffId,
    required this.date,
    required this.period,
    required this.routeId,
    required this.kind,
    required this.registeredAt,
    required this.photo,
  });
  static const maxPhotoBytes = 180 * 1024;
  final String staffId, date, routeId;
  final TransportPeriod period;
  final WorkPhotoKind kind;
  final DateTime registeredAt;
  final Uint8List photo;
  static String recordId(
    String date,
    TransportPeriod period,
    String routeId,
    WorkPhotoKind kind,
  ) => '${date}_${period.name}_${routeId}_${kind.name}';
  String get koreaTime {
    final t = registeredAt.toUtc().add(const Duration(hours: 9));
    return '${dateKey(t)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  }
}
