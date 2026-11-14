import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/attendance_record.dart';
import '../models/transport.dart';

abstract class AttendanceProvider {
  AttendanceRepository get attendance;
}

abstract class AttendanceSummaryRepository implements AttendanceRepository {
  Future<List<AttendanceSummary>> summaries(
    String staffId,
    String date,
    TransportPeriod period,
  );
  Future<Uint8List> photo(AttendanceSummary summary);
}

abstract class AttendanceRepository {
  bool get enabled;
  Stream<List<AttendanceRecord>> watch(
    String staffId,
    String date,
    TransportPeriod period,
  );
  Future<AttendanceRecord> register({
    required AppUser user,
    required String date,
    required TransportPeriod period,
    required String routeId,
    required WorkPhotoKind kind,
    required Uint8List photo,
    int? expectedVersion,
    int? expectedAvailabilityVersion,
  });
}

class FirebaseAttendanceRepository implements AttendanceRepository {
  FirebaseAttendanceRepository(this.firestore);
  final FirebaseFirestore firestore;
  @override
  bool get enabled =>
      const bool.fromEnvironment('USE_FIREBASE_EMULATORS') &&
      firestore.app.options.projectId == 'demo-senior-transport';
  void _requireEnabled() {
    if (!enabled) throw StateError('사진 등록은 Emulator 시연 환경에서 사용할 수 있습니다.');
  }

  CollectionReference<Map<String, dynamic>> _records(String staffId) =>
      firestore.collection('attendance/$staffId/records');
  AttendanceRecord _decode(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return AttendanceRecord(
      staffId: data['staffId'] as String,
      date: data['date'] as String,
      period: TransportPeriod.values.byName(data['period'] as String),
      routeId: data['routeId'] as String,
      kind: WorkPhotoKind.values.byName(data['kind'] as String),
      registeredAt: (data['registeredAt'] as Timestamp).toDate(),
      photo: (data['photo'] as Blob).bytes,
    );
  }

  @override
  Stream<List<AttendanceRecord>> watch(
    String staffId,
    String date,
    TransportPeriod period,
  ) {
    _requireEnabled();
    return _records(staffId)
        .where('date', isEqualTo: date)
        .where('period', isEqualTo: period.name)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          if (snapshot.metadata.isFromCache ||
              snapshot.metadata.hasPendingWrites) {
            throw StateError('서버의 사진 기록을 확인 중입니다. 연결을 확인해 주세요.');
          }
          return snapshot.docs.map(_decode).toList()
            ..sort((a, b) => a.kind.index.compareTo(b.kind.index));
        });
  }

  @override
  Future<AttendanceRecord> register({
    required AppUser user,
    required String date,
    required TransportPeriod period,
    required String routeId,
    required WorkPhotoKind kind,
    required Uint8List photo,
    int? expectedVersion,
    int? expectedAvailabilityVersion,
  }) async {
    _requireEnabled();
    if (user.role != UserRole.staff || user.staffId == null) {
      throw StateError('직원 본인의 사진만 등록할 수 있습니다.');
    }
    if (photo.isEmpty || photo.length > AttendanceRecord.maxPhotoBytes) {
      throw StateError('사진 크기를 줄이거나 다른 시연용 사진을 선택해 주세요.');
    }
    final ref = _records(user.staffId!)
        .doc(AttendanceRecord.recordId(date, period, routeId, kind));
    try {
      await firestore.runTransaction((tx) async {
        final existing = await tx.get(ref);
        if (existing.exists) {
          return; // First registration is immutable/idempotent.
        }
        tx.set(ref, {
          'staffId': user.staffId,
          'uid': user.uid,
          'date': date,
          'period': period.name,
          'routeId': routeId,
          'kind': kind.name,
          'registeredAt': FieldValue.serverTimestamp(),
          'photo': Blob(photo),
          'contentType': 'image/jpeg',
        });
      });
    } catch (_) {
      // A lost acknowledgement must not cause a duplicate or overwrite.
      final committed = await ref.get(const GetOptions(source: Source.server));
      if (committed.exists) return _decode(committed);
      rethrow;
    }
    return _decode(await ref.get(const GetOptions(source: Source.server)));
  }
}
