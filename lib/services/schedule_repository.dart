import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/app_user.dart';
import '../models/schedule_catalog.dart';
import '../models/schedule_codec.dart';
import '../models/transport.dart';
import '../models/staff_absence.dart';
import 'staff_availability_diagnostics.dart';
import 'attendance_repository.dart';
import 'work_photo_repository.dart';
import '../data/emulator_display_names.dart';

class ScheduleViewData {
  const ScheduleViewData(
    this.catalog,
    this.confirmed, {
    this.lastRequestId,
    this.previewDraft,
  });
  final ScheduleCatalog catalog;
  final ScheduleSnapshot? confirmed;
  final String? lastRequestId;
  final ScheduleSnapshot? previewDraft;
}

abstract class CatalogPreviewScope {
  Map<String, dynamic> get previewContext;
  Set<String> get reserveStaffIds;
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

abstract class StaffAvailabilityRepository {
  Stream<Map<String, StaffAbsence>> watchAbsences(AppUser user, DateTime date);
  Future<StaffAbsence> setAbsence(Map<String, dynamic> request);
  Future<void> publishWithAvailability(
    ScheduleSnapshot snapshot,
    String catalogVersion,
    int expectedVersion,
    String requestId,
    Map<String, int> versions,
  );
}

abstract class ScheduleSuggestionRepository {
  bool get allowsAiSuggestions;
  Future<Map<String, dynamic>> suggestSchedule(Map<String, dynamic> request);
}

abstract class PassengerDetailsRepository {
  Future<Passenger> savePassengerDetails(
    String catalogVersion,
    Passenger passenger, {
    required String note,
    required int? defaultMorningMinute,
  });
}

class FirebaseScheduleRepository
    implements
        ScheduleRepository,
        StaffAvailabilityRepository,
        ScheduleSuggestionRepository,
        PassengerDetailsRepository,
        AttendanceProvider {
  @override
  late final AttendanceRepository attendance =
      const bool.fromEnvironment('ENABLE_STORAGE_WORK_PHOTOS') &&
          ((const bool.fromEnvironment('USE_FIREBASE_EMULATORS') &&
                  firestore.app.options.projectId == 'demo-senior-transport') ||
              (!const bool.fromEnvironment('USE_FIREBASE_EMULATORS') &&
                  firestore.app.options.projectId == 'senior-transport-app')) &&
          functions.app.options.projectId == firestore.app.options.projectId
      ? WorkPhotoRepository(
          enabled: true,
          call: (name, input) async {
            final response = await functions
                .httpsCallable(
                  name,
                  options: HttpsCallableOptions(
                    timeout: const Duration(seconds: 75),
                  ),
                )
                .call<Map<String, dynamic>>(input);
            return Map<String, dynamic>.from(response.data);
          },
        )
      : FirebaseAttendanceRepository(firestore);
  FirebaseScheduleRepository(this.firestore, this.functions);
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;
  static const _server = GetOptions(source: Source.server);

  @override
  Future<Passenger> savePassengerDetails(
    String catalogVersion,
    Passenger passenger, {
    required String note,
    required int? defaultMorningMinute,
  }) async {
    final result = await functions
        .httpsCallable('updatePassengerDetails')
        .call<Map<String, dynamic>>({
          'catalogVersion': catalogVersion,
          'passengerId': passenger.id,
          'expectedVersion': passenger.detailsVersion,
          'note': note,
          'defaultMorningMinute': defaultMorningMinute,
        });
    return passenger.withDetails(
      note: result.data['note'] as String,
      defaultMorningMinute: result.data['defaultMorningMinute'] as int?,
      detailsVersion: result.data['detailsVersion'] as int,
    );
  }

  @override
  bool get allowsAiSuggestions =>
      (const bool.fromEnvironment('USE_FIREBASE_EMULATORS') &&
          firestore.app.options.projectId == 'demo-senior-transport' &&
          functions.app.options.projectId == 'demo-senior-transport') ||
      (!const bool.fromEnvironment('USE_FIREBASE_EMULATORS') &&
          const bool.fromEnvironment('ENABLE_PRODUCTION_AI') &&
          firestore.app.options.projectId == 'senior-transport-app' &&
          functions.app.options.projectId == 'senior-transport-app');

  @override
  Future<Map<String, dynamic>> suggestSchedule(
    Map<String, dynamic> request,
  ) async {
    if (!allowsAiSuggestions) {
      throw StateError('이 앱에서는 AI 추천이 활성화되지 않았습니다.');
    }
    final result = await functions
        .httpsCallable(
          'suggestSchedule',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 105)),
        )
        .call<Map<String, dynamic>>(request);
    return Map<String, dynamic>.from(result.data);
  }

  @override
  Stream<Map<String, StaffAbsence>> watchAbsences(AppUser user, DateTime date) {
    final day = dateKey(date);
    final collection = firestore.collection('staffAvailability/$day/staff');
    logStaffAvailability(
      'read_started project=${firestore.app.options.projectId} path=staffAvailability/$day/staff scope=${user.role == UserRole.admin ? 'admin-list' : 'own-document'}',
    );
    if (user.role == UserRole.staff) {
      return collection
          .doc(user.staffId!)
          .snapshots(includeMetadataChanges: true)
          .map((doc) {
            return decodeStaffAvailability(
              day,
              {if (doc.exists) doc.id: doc.data()!},
              isFromCache: doc.metadata.isFromCache,
              hasPendingWrites: doc.metadata.hasPendingWrites,
            );
          });
    }
    return collection.snapshots(includeMetadataChanges: true).map((snapshot) {
      return decodeStaffAvailability(
        day,
        {for (final doc in snapshot.docs) doc.id: doc.data()},
        isFromCache: snapshot.metadata.isFromCache,
        hasPendingWrites: snapshot.metadata.hasPendingWrites,
      );
    });
  }

  @override
  Future<StaffAbsence> setAbsence(Map<String, dynamic> request) async {
    final result = await functions
        .httpsCallable('setStaffAbsence')
        .call<Map<String, dynamic>>(request);
    return StaffAbsence.fromJson(
      request['staffId'] as String,
      Map<String, dynamic>.from(result.data),
    );
  }

  @override
  Future<void> publishWithAvailability(
    ScheduleSnapshot snapshot,
    String catalogVersion,
    int expectedVersion,
    String requestId,
    Map<String, int> versions,
  ) async {
    await functions.httpsCallable('confirmSchedule').call<void>({
      ...scheduleToJson(snapshot),
      'catalogVersion': catalogVersion,
      'expectedVersion': expectedVersion,
      'requestId': requestId,
      'expectedAvailabilityVersions': versions,
    });
  }

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
    ScheduleCatalog catalog;
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
    if (user.role == UserRole.admin || snapshot != null) {
      final result = await functions
          .httpsCallable('getPassengerDetails')
          .call<Map<String, dynamic>>({
            'catalogVersion': version,
            'date': dateKey(date),
            'period': period.name,
          });
      final details = {
        for (final raw in result.data['passengers'] as List)
          (raw as Map)['id'] as String: raw,
      };
      catalog = ScheduleCatalog(
        version: catalog.version,
        staff: catalog.staff,
        vehicles: catalog.vehicles,
        baseRoutes: catalog.baseRoutes,
        passengers: catalog.passengers.map((p) {
          final d = details[p.id];
          return d == null
              ? p
              : p.withDetails(
                  note: d['note'] as String,
                  defaultMorningMinute: d['defaultMorningMinute'] as int?,
                  detailsVersion: d['detailsVersion'] as int,
                );
        }),
      );
    }
    return ScheduleViewData(
      emulatorDisplayCatalog(
        catalog,
        enabled: const bool.fromEnvironment('USE_FIREBASE_EMULATORS'),
        projectId: firestore.app.options.projectId,
      ),
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
