import '../models/schedule_catalog.dart';
import '../models/transport.dart';

// Invented demo names, unrelated to any real person or external dataset.
const demoStaffNames = [
  '김다정',
  '이온유',
  '박여유',
  '최지훈',
  '정서연',
  '강민준',
  '조하은',
  '윤도현',
  '장수빈',
  '임지우',
  '한서준',
  '오예린',
  '서현우',
  '신유진',
  '권지호',
  '황다은',
  '안태윤',
  '송나연',
  '류준서',
  '홍소윤',
];
const _familyNames = ['김', '이', '박', '최', '정', '강', '조', '윤', '장', '임'];
const _givenNames = ['영숙', '정호', '순자', '상철', '미경', '명수', '정희', '종수'];
final demoPassengerNames = [
  for (final family in _familyNames)
    for (final given in _givenNames) '$family$given',
];

/// Presentation aliases for legacy snapshots. Never written back to Firestore.
ScheduleCatalog emulatorDisplayCatalog(
  ScheduleCatalog catalog, {
  required bool enabled,
  required String projectId,
}) {
  if (!enabled ||
      projectId != 'demo-senior-transport' ||
      catalog.version != 'operations-20x80-v1') {
    return catalog;
  }
  String name(String id, String prefix, List<String> names, String fallback) {
    final index = int.tryParse(
      id.startsWith(prefix) ? id.substring(prefix.length) : '',
    );
    return index != null &&
            id == '$prefix$index' &&
            index > 0 &&
            index <= names.length
        ? names[index - 1]
        : fallback;
  }

  return ScheduleCatalog(
    version: catalog.version,
    staff: catalog.staff.map(
      (s) => Staff(
        s.id,
        name(s.id, 's', demoStaffNames, s.name),
        active: s.active,
        unavailableWeekdays: s.unavailableWeekdays,
      ),
    ),
    passengers: catalog.passengers.map(
      (p) => Passenger(
        p.id,
        name(p.id, 'p', demoPassengerNames, p.name),
        p.address,
        p.note,
        defaultMorningMinute: p.defaultMorningMinute,
        detailsVersion: p.detailsVersion,
      ),
    ),
    vehicles: catalog.vehicles,
    baseRoutes: catalog.baseRoutes,
  );
}
