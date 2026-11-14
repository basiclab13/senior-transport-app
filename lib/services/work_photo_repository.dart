import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/attendance_record.dart';
import '../models/transport.dart';
import 'attendance_repository.dart';

typedef WorkPhotoCaller = Future<Map<String, dynamic>> Function(
  String name,
  Map<String, dynamic> input,
);

/// Storage-backed server API only; never reads/writes the Emulator Blob path.
class WorkPhotoRepository implements AttendanceSummaryRepository {
  WorkPhotoRepository({required this.call, required this.enabled});
  final WorkPhotoCaller call;
  @override
  final bool enabled;
  final _updates = StreamController<void>.broadcast();
  final _pending = <String, ({Uint8List bytes, String id})>{};
  void refresh() => _updates.add(null);
  void _check() {
    if (!enabled) throw StateError('사진 기능이 비활성 상태입니다.');
  }

  AttendanceRecord _decode(Map<String, dynamic> data) => AttendanceRecord(
    staffId: data['staffId'] as String,
    date: data['date'] as String,
    period: TransportPeriod.values.byName(data['period'] as String),
    routeId: data['routeId'] as String,
    kind: WorkPhotoKind.values.byName(data['kind'] as String),
    registeredAt: DateTime.parse(data['registeredAt'] as String),
    photo: base64Decode(data['photoBase64'] as String),
  );

  @override
  Future<List<AttendanceSummary>> summaries(
    String staffId,
    String date,
    TransportPeriod period,
  ) async {
    _check();
    final result = <AttendanceSummary>[];
    final cursors = <String>{};
    String? cursor;
    do {
      final page = await call('getWorkPhotos', {
        'staffId': staffId,
        'date': date,
        'period': period.name,
        'cursor': ?cursor,
      });
      for (final item in page['records'] as List) {
        final data = Map<String, dynamic>.from(item as Map);
        final summary = AttendanceSummary(
          recordId: data['recordId'] as String,
          staffId: data['staffId'] as String,
          date: data['date'] as String,
          period: TransportPeriod.values.byName(data['period'] as String),
          routeId: data['routeId'] as String,
          kind: WorkPhotoKind.values.byName(data['kind'] as String),
          registeredAt: DateTime.parse(data['registeredAt'] as String),
        );
        if (summary.staffId != staffId ||
            summary.date != date ||
            summary.period != period) {
          throw StateError('사진 기록의 담당자와 날짜를 확인해 주세요.');
        }
        result.add(summary);
      }
      cursor = page['nextCursor'] as String?;
      if (cursor != null && !cursors.add(cursor)) {
        throw StateError('사진 기록을 다시 확인해 주세요.');
      }
    } while (cursor != null);
    return result..sort((a, b) => a.registeredAt.compareTo(b.registeredAt));
  }

  @override
  Future<Uint8List> photo(AttendanceSummary summary) async {
    _check();
    final record = _decode(
      await call('getWorkPhotos', {
        'staffId': summary.staffId,
        'date': summary.date,
        'period': summary.period.name,
        'recordId': summary.recordId,
      }),
    );
    if (record.staffId != summary.staffId ||
        record.date != summary.date ||
        record.period != summary.period ||
        record.routeId != summary.routeId ||
        record.kind != summary.kind ||
        record.registeredAt != summary.registeredAt) {
      throw StateError('사진 기록이 변경되었습니다. 등록 정보를 다시 확인해 주세요.');
    }
    return record.photo;
  }

  Future<List<AttendanceRecord>> _load(
    String staffId,
    String date,
    TransportPeriod period,
  ) async {
    _check();
    final input = <String, dynamic>{
      'staffId': staffId,
      'date': date,
      'period': period.name,
    };
    final result = <AttendanceRecord>[];
    final cursors = <String>{};
    String? cursor;
    do {
      final page = await call('getWorkPhotos', {...input, 'cursor': ?cursor});
      for (final value in page['records'] as List) {
        final entry = Map<String, dynamic>.from(value as Map);
        final photo = await call('getWorkPhotos', {
          ...input,
          'recordId': entry['recordId'],
        });
        final record = _decode(photo);
        if (record.staffId != staffId ||
            record.date != date ||
            record.period != period) {
          throw StateError('사진 기록의 담당자와 날짜를 확인해 주세요.');
        }
        result.add(record);
      }
      cursor = page['nextCursor'] as String?;
      if (cursor != null && !cursors.add(cursor)) {
        throw StateError('사진 조회를 완료하지 못했습니다. 다시 확인해 주세요.');
      }
    } while (cursor != null);
    return result..sort((a, b) => a.registeredAt.compareTo(b.registeredAt));
  }

  @override
  Stream<List<AttendanceRecord>> watch(
    String staffId,
    String date,
    TransportPeriod period,
  ) {
    _check();
    late StreamController<List<AttendanceRecord>> output;
    late StreamSubscription<void> subscription;
    var revision = 0;
    Future<void> load() async {
      final current = ++revision;
      try {
        final records = await _load(staffId, date, period);
        if (!output.isClosed && current == revision) output.add(records);
      } catch (error, stack) {
        if (!output.isClosed && current == revision) {
          output.addError(error, stack);
        }
      }
    }

    output = StreamController<List<AttendanceRecord>>(
      onListen: () {
        subscription = _updates.stream.listen((_) => unawaited(load()));
        unawaited(load());
      },
      onCancel: () async {
        revision++;
        await subscription.cancel();
      },
    );
    return output.stream;
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
    _check();
    if (user.role != UserRole.staff ||
        user.staffId == null ||
        expectedVersion == null ||
        expectedAvailabilityVersion == null ||
        photo.isEmpty ||
        photo.length > AttendanceRecord.maxPhotoBytes) {
      throw StateError('확정된 본인 일정과 사진 크기를 확인해 주세요.');
    }
    final key = '${user.uid}_${date}_${period.name}_${routeId}_${kind.name}';
    // Preserve the request ID after an ambiguous failure; never retry silently.
    final previous = _pending[key];
    final requestId = previous != null && listEquals(previous.bytes, photo)
        ? previous.id
        : List.generate(
            16,
            (_) =>
                Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join();
    _pending[key] = (bytes: Uint8List.fromList(photo), id: requestId);
    try {
      final registered = await call('registerWorkPhoto', {
        'date': date,
        'period': period.name,
        'routeId': routeId,
        'kind': kind.name,
        'requestId': requestId,
        'photoBase64': base64Encode(photo),
        'expectedVersion': expectedVersion,
        'expectedAvailabilityVersion': expectedAvailabilityVersion,
      });
      final result = await call('getWorkPhotos', {
        'staffId': user.staffId,
        'date': date,
        'period': period.name,
        'recordId': registered['recordId'],
      });
      final record = _decode(result);
      if (record.staffId != user.staffId ||
          record.routeId != routeId ||
          record.date != date ||
          record.period != period ||
          record.kind != kind) {
        throw StateError('사진 등록 결과를 다시 확인해 주세요.');
      }
      _pending.remove(key);
      return record;
    } finally {
      refresh();
    }
  }
}
