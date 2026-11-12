import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/app_user.dart';
import '../models/schedule_catalog.dart';
import '../models/schedule_codec.dart';
import '../models/transport.dart';

class ScheduleViewData {
  const ScheduleViewData(this.catalog, this.confirmed, {this.lastRequestId});
  final ScheduleCatalog catalog;
  final ScheduleSnapshot? confirmed;
  final String? lastRequestId;
}

abstract class ScheduleRepository {
  Stream<ScheduleViewData> watch(
    AppUser user,
    DateTime date,
    TransportPeriod period,
  );
  Future<ScheduleViewData> load(
    AppUser user,
    DateTime date,
    TransportPeriod period,
  );
  Future<void> publish(
    ScheduleSnapshot snapshot,
    String catalogVersion,
    int expectedVersion,
    String requestId,
  );
  Future<bool> committed(
    DateTime date,
    TransportPeriod period,
    String requestId,
  );
}

class FirebaseScheduleRepository implements ScheduleRepository {
  FirebaseScheduleRepository(this.firestore, this.functions);
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;
  static const _server = GetOptions(source: Source.server);

  DocumentReference<Map<String, dynamic>> _reference(
    AppUser user,
    DateTime date,
    TransportPeriod period,
  ) {
    final id = '${dateKey(date)}_${period.name}';
    return firestore.doc(
      user.role == UserRole.admin
          ? 'schedules/$id'
          : 'staffSchedules/${user.staffId}/days/$id',
    );
  }

  @override
  Stream<ScheduleViewData> watch(
    AppUser user,
    DateTime date,
    TransportPeriod period,
  ) => _reference(user, date, period)
      .snapshots(includeMetadataChanges: true)
      .asyncMap((doc) {
        if (doc.metadata.isFromCache || doc.metadata.hasPendingWrites) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'unavailable',
          );
        }
        return _decode(user, date, period, doc);
      });

  @override
  Future<ScheduleViewData> load(
    AppUser user,
    DateTime date,
    TransportPeriod period,
  ) async => _decode(
    user,
    date,
    period,
    await _reference(user, date, period).get(_server),
  );

  Future<ScheduleViewData> _decode(
    AppUser user,
    DateTime date,
    TransportPeriod period,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final String version;
    if (data != null) {
      version = data['catalogVersion'] as String;
    } else {
      version =
          (await firestore.doc('settings/schedules').get(_server))
                  .data()?['catalogVersion']
              as String? ??
          '';
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(version)) {
      throw const FormatException('기본 데이터 등록이 필요합니다.');
    }
    final ScheduleCatalog catalog;
    if (user.role == UserRole.staff && data != null) {
      if (data['staffId'] != user.staffId) {
        throw const FormatException('직원 연결 정보가 일치하지 않습니다.');
      }
      catalog = ScheduleCatalog.fromJson(
        version,
        Map<String, dynamic>.from(data['catalog'] as Map),
      );
    } else {
      final ref = firestore.doc('catalogs/$version');
      final metadata = (await ref.get(_server)).data();
      if (metadata?['ready'] != true || metadata?['fictional'] != true) {
        throw const FormatException('가상 기본 데이터가 준비되지 않았습니다.');
      }
      final collections = <String, dynamic>{};
      if (user.role == UserRole.staff) {
        final staff = await ref
            .collection('staff')
            .doc(user.staffId)
            .get(_server);
        if (staff.data()?['active'] != true) {
          throw const UserProfileException(
            UserProfileFailure.invalidStaffMapping,
          );
        }
        collections.addAll({
          'staff': [
            {...staff.data()!, 'id': staff.id},
          ],
          'vehicles': [],
          'passengers': [],
          'baseRoutes': [],
        });
      } else {
        for (final name in ['staff', 'vehicles', 'passengers', 'baseRoutes']) {
          final entries = await ref.collection(name).get(_server);
          collections[name] = entries.docs
              .map((entry) => {...entry.data(), 'id': entry.id})
              .toList();
        }
      }
      catalog = ScheduleCatalog.fromJson(version, collections);
    }
    final snapshot = data == null
        ? null
        : scheduleFromJson(data, (data['confirmedAt'] as Timestamp).toDate());
    if (snapshot != null &&
        (dateKey(snapshot.date) != dateKey(date) ||
            snapshot.period != period ||
            (user.role == UserRole.staff &&
                snapshot.routes.any((r) => r.staffId != user.staffId)))) {
      throw const FormatException('일정 조회 범위가 일치하지 않습니다.');
    }
    return ScheduleViewData(
      catalog,
      snapshot,
      lastRequestId: data?['lastRequestId'] as String?,
    );
  }

  @override
  Future<void> publish(
    ScheduleSnapshot snapshot,
    String catalogVersion,
    int expectedVersion,
    String requestId,
  ) async {
    await functions.httpsCallable('confirmSchedule').call<void>({
      ...scheduleToJson(snapshot),
      'catalogVersion': catalogVersion,
      'expectedVersion': expectedVersion,
      'requestId': requestId,
    });
  }

  @override
  Future<bool> committed(
    DateTime date,
    TransportPeriod period,
    String requestId,
  ) async =>
      (await firestore
              .doc(
                'schedules/${dateKey(date)}_${period.name}/commits/$requestId',
              )
              .get(_server))
          .exists;
}
