import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/attendance_record.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/screens/attendance_screen.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/attendance_repository.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';

import 'support/fixtures.dart';

final demoPhoto = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j6R0AAAAASUVORK5CYII=',
);
const staffUser = AppUser(
  uid: 'photo-staff',
  role: UserRole.staff,
  staffId: 's1',
);
const adminUser = AppUser(uid: 'photo-admin', role: UserRole.admin);

class PhotoRepository implements AttendanceRepository {
  @override
  bool enabled = true;
  bool fail = false;
  final records = <AttendanceRecord>[];
  final updates = StreamController<void>.broadcast();
  @override
  Stream<List<AttendanceRecord>> watch(
    String staffId,
    String date,
    TransportPeriod period,
  ) async* {
    List<AttendanceRecord> selected() => records
        .where(
          (r) => r.staffId == staffId && r.date == date && r.period == period,
        )
        .toList();
    yield selected();
    yield* updates.stream.map((_) => selected());
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
    if (fail) throw Exception('simulated network failure');
    final record = AttendanceRecord(
      staffId: user.staffId!,
      date: date,
      period: period,
      routeId: routeId,
      kind: kind,
      registeredAt: DateTime.utc(2026, 11, 12, 0, 15),
      photo: photo,
    );
    records.add(record);
    updates.add(null);
    return record;
  }
}

class PhotoSchedules extends MemoryScheduleRepository
    implements AttendanceProvider {
  @override
  final PhotoRepository attendance = PhotoRepository();
}

void main() {
  late PhotoSchedules repo;
  late ScheduleController c;
  setUp(() {
    repo = PhotoSchedules();
    final source = fixtureController(user: adminUser);
    source.confirm();
    repo.snapshots['2026-11-12_morning'] = source.confirmed!;
    source.selectPeriod(TransportPeriod.afternoon);
    source.confirm();
    repo.snapshots['2026-11-12_afternoon'] = source.confirmed!;
    source.dispose();
    c = ScheduleController.remote(
      user: staffUser,
      repository: repo,
      clock: fixtureClock,
    );
  });
  tearDown(() async {
    c.dispose();
    await repo.changes.close();
    await repo.attendance.updates.close();
  });
  Future<void> open(
    WidgetTester tester, {
    Future<Uint8List?> Function()? picker,
    String? routeId = 'morning-a',
  }) async {
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          controller: c,
          staffId: 's1',
          staffName: '김다정',
          date: DateTime(2026, 11, 12),
          period: c.period,
          routeId: routeId,
          photoPicker: picker ?? () async => demoPhoto,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder button(String kind) => find.byKey(Key('register-work-$kind'));
  Future<void> register(WidgetTester tester, String kind) async {
    await tester.ensureVisible(button(kind));
    await tester.tap(button(kind));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-work-photo')));
    await tester.pumpAndSettle();
  }

  testWidgets('사진 확인 후 시작·종료를 기록하며 한국 시간과 사진을 다시 조회한다', (tester) async {
    await open(tester);
    expect(button('end'), findsNothing);
    await register(tester, 'start');
    expect(repo.attendance.records.single.kind, WorkPhotoKind.start);
    expect(find.textContaining('2026-11-12 09:15:00'), findsOneWidget);
    expect(tester.widget<FilledButton>(button('start')).onPressed, isNull);
    expect(button('end'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await open(tester);
    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('2026-11-12 09:15:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('카메라와 사진 선택을 구분하며 선택 메뉴 취소는 저장하지 않는다', (tester) async {
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          controller: c,
          staffId: 's1',
          staffName: '김다정',
          date: DateTime(2026, 11, 12),
          period: TransportPeriod.morning,
          routeId: 'morning-a',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(button('start'));
    await tester.pumpAndSettle();
    expect(find.text('카메라로 촬영'), findsOneWidget);
    expect(find.text('사진 선택'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(repo.attendance.records, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('사진 선택이나 명시적 확인을 취소하면 기록하지 않는다', (tester) async {
    await open(tester, picker: () async => null);
    await tester.tap(button('start'));
    await tester.pumpAndSettle();
    expect(repo.attendance.records, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await open(tester);
    await tester.tap(button('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repo.attendance.records, isEmpty);
  });
  testWidgets('등록 오류는 성공으로 표시하지 않고 다시 시도할 수 있다', (tester) async {
    repo.attendance.fail = true;
    await open(tester);
    await register(tester, 'start');
    expect(repo.attendance.records, isEmpty);
    expect(find.textContaining('사진을 등록하지 못했습니다'), findsOneWidget);
    repo.attendance.fail = false;
    await register(tester, 'start');
    expect(repo.attendance.records.length, 1);
  });
  testWidgets('사진 확인 중 담당 날짜가 변경되면 오래된 화면의 등록을 막는다', (tester) async {
    await open(tester);
    await tester.tap(button('start'));
    await tester.pumpAndSettle();
    c.selectDate(DateTime(2026, 11, 13));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-work-photo')));
    await tester.pumpAndSettle();
    expect(repo.attendance.records, isEmpty);
    expect(find.textContaining('담당 일정이나 결근 정보가 변경되었습니다'), findsOneWidget);
  });
  testWidgets('담당 코스가 없으면 이전 사진 조회만 가능하며 업로드는 차단한다', (tester) async {
    await open(tester, routeId: null);
    expect(tester.widget<FilledButton>(button('start')).onPressed, isNull);
    expect(button('end'), findsNothing);
  });
  testWidgets('관리자 직원 상세에서 기록을 열고 조회만 할 수 있다', (tester) async {
    await repo.attendance.register(
      user: staffUser,
      date: '2026-11-12',
      period: TransportPeriod.morning,
      routeId: 'morning-a',
      kind: WorkPhotoKind.start,
      photo: demoPhoto,
    );
    c.dispose();
    c = ScheduleController.remote(
      user: adminUser,
      repository: repo,
      clock: fixtureClock,
    );
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          controller: c,
          user: adminUser,
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openAdminEditor(tester);
    await tester.pumpAndSettle();
    expect(find.text('업무 시작·종료 기록'), findsOneWidget);
    expect(find.textContaining('2026-11-12 09:15:00'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    await tester.tap(find.text('사진 보기'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(button('start'), findsNothing);
    expect(button('end'), findsNothing);
  });
  testWidgets('작은 화면에서도 시작·종료 사진을 등록할 수 있다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester);
    await register(tester, 'start');
    expect(button('end'), findsNothing);
    expect(repo.attendance.records.length, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Emulator가 아닌 환경에서는 등록하지 않는다', (tester) async {
    repo.attendance.enabled = false;
    await open(tester);
    expect(find.text('사진 등록을 사용할 수 없습니다. 관리자에게 문의해 주세요.'), findsOneWidget);
    expect(button('start'), findsNothing);
  });
  testWidgets('오전 시작 누락과 관계없이 오후에는 종료 사진만 등록한다', (tester) async {
    c.selectPeriod(TransportPeriod.afternoon);
    await tester.pumpWidget(const SizedBox());
    await open(tester, routeId: 'afternoon-a');
    expect(button('start'), findsNothing);
    expect(button('end'), findsOneWidget);
    await register(tester, 'end');
    expect(repo.attendance.records.single.kind, WorkPhotoKind.end);
    expect(repo.attendance.records.single.period, TransportPeriod.afternoon);
    expect(
      repo.attendance.records.where((r) => r.period == TransportPeriod.morning),
      isEmpty,
    );
  });
}
