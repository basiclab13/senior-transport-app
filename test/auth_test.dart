import 'support/fixtures.dart';

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/main.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/services/auth_service.dart';

class FakeAuthRepository implements AuthRepository {
  final sessions = StreamController<String?>.broadcast();
  final profiles = StreamController<AppUser>.broadcast();
  Completer<void>? pendingLogin;
  Object? loginFailure;
  int loginCalls = 0;
  String? submittedEmail;
  String? requestedUid;

  @override
  Stream<String?> authChanges() => sessions.stream;
  @override
  Stream<AppUser> watchUser(String uid) {
    requestedUid = uid;
    return profiles.stream;
  }

  @override
  Future<void> signIn(String email, String password) async {
    loginCalls++;
    submittedEmail = email;
    await pendingLogin?.future;
    if (loginFailure != null) throw loginFailure!;
    sessions.add('fictional-user');
  }

  @override
  Future<void> signOut() async => sessions.add(null);

  Future<void> close() async {
    await sessions.close();
    await profiles.close();
  }
}

void main() {
  const admin = AppUser(uid: 'fictional-user', role: UserRole.admin);
  const staff = AppUser(
    uid: 'fictional-user',
    role: UserRole.staff,
    staffId: 's2',
  );

  test('제공된 관리자 문서는 active 누락을 정확히 알리고 true 추가 시 관리자로 인식한다', () {
    final document = <String, dynamic>{
      'email': 'admin@example.com',
      'name': '관리자',
      'role': 'admin',
    };
    expect(
      () => AppUser.fromDocument('fictional-admin-uid', document),
      throwsA(
        isA<UserProfileException>().having(
          (error) => error.reason,
          'reason',
          UserProfileFailure.missingActive,
        ),
      ),
    );
    final user = AppUser.fromDocument('fictional-admin-uid', {
      ...document,
      'active': true,
    });
    expect(user.uid, 'fictional-admin-uid');
    expect(user.role, UserRole.admin);
    expect(user.staffId, isNull);
    // email and name are optional metadata; only UID identifies the account.
    expect(
      AppUser.fromDocument('fictional-admin-uid', {
        'role': 'admin',
        'active': true,
      }).role,
      UserRole.admin,
    );
  });

  test('문서 누락, 필드 타입 오류, 비활성화 및 역할 오류의 안내를 구분한다', () {
    final cases = <(Map<String, dynamic>?, UserProfileFailure, String)>[
      (null, UserProfileFailure.missingDocument, '문서가 없습니다'),
      ({'role': 'admin'}, UserProfileFailure.missingActive, 'active 필드가 없습니다'),
      (
        {'role': 'admin', 'active': 'true'},
        UserProfileFailure.invalidActive,
        'boolean 타입이어야',
      ),
      (
        {'role': 'admin', 'active': 1},
        UserProfileFailure.invalidActive,
        'boolean 타입이어야',
      ),
      (
        {'role': 'admin', 'active': null},
        UserProfileFailure.invalidActive,
        'boolean 타입이어야',
      ),
      (
        {'role': 'admin', 'active': false},
        UserProfileFailure.inactive,
        '사용이 중지',
      ),
      (
        {'role': 'Admin', 'active': true},
        UserProfileFailure.invalidRole,
        '문자열 admin 또는 staff',
      ),
      (
        {'role': 1, 'active': true},
        UserProfileFailure.invalidRole,
        '문자열 admin 또는 staff',
      ),
      (
        {'role': 'staff', 'active': true},
        UserProfileFailure.invalidStaffMapping,
        'staffId',
      ),
    ];
    for (final (document, reason, message) in cases) {
      expect(
        () => AppUser.fromDocument('fictional-user', document),
        throwsA(
          isA<UserProfileException>()
              .having((error) => error.reason, 'reason', reason)
              .having(authErrorMessage, 'message', contains(message)),
        ),
      );
    }
    final denied = authErrorMessage(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
    expect(denied, contains('조회가 거부'));
    expect(denied, isNot(contains('문서가 없습니다')));
    expect(
      authErrorMessage(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      ),
      contains('네트워크'),
    );
  });

  test('권한 문서는 누락, 비활성화, 알 수 없는 역할과 직원 매핑을 거부한다', () {
    for (final data in <Map<String, dynamic>?>[
      null,
      {},
      {'active': false, 'role': 'admin'},
      {'active': true, 'role': 'owner'},
      {'active': true, 'role': 'staff'},
      {'active': true, 'role': 'staff', 'staffId': 'bad/id'},
    ]) {
      expect(
        () => AppUser.fromDocument('fictional-user', data),
        throwsFormatException,
      );
    }
    expect(
      AppUser.fromDocument('fictional-user', {
        'active': true,
        'role': 'staff',
        'staffId': 's2',
      }).staffId,
      's2',
    );
  });

  test('비밀번호 및 네트워크 오류를 안전한 한국어 메시지로 변환한다', () {
    for (final code in [
      'wrong-password',
      'invalid-credential',
      'user-not-found',
    ]) {
      expect(
        authErrorMessage(FirebaseAuthException(code: code)),
        '이메일 또는 비밀번호가 올바르지 않습니다.',
      );
    }
    expect(
      authErrorMessage(FirebaseAuthException(code: 'network-request-failed')),
      contains('네트워크'),
    );
  });

  late FakeAuthRepository repository;
  late AuthService auth;
  late List<String> logs;
  setUp(() {
    repository = FakeAuthRepository();
    logs = [];
    auth = AuthService(
      repository,
      logger: (message) {
        logs.add(message);
        debugPrint(message);
      },
    );
  });
  tearDown(() async {
    auth.dispose();
    await repository.close();
  });

  testWidgets('로그인 로딩, 중복 제출 차단, 실패 안내', (tester) async {
    await tester.pumpWidget(
      MyApp(auth: auth, schedules: MemoryScheduleRepository()),
    );
    repository.sessions.add(null);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login')));
    await tester.pumpAndSettle();
    expect(repository.loginCalls, 0);
    await tester.enterText(
      find.byKey(const Key('email')),
      ' fictional@example.invalid ',
    );
    await tester.enterText(
      find.byKey(const Key('password')),
      'fictional-input',
    );
    repository.pendingLogin = Completer<void>();
    repository.loginFailure = FirebaseAuthException(code: 'wrong-password');
    await tester.tap(find.byKey(const Key('login')));
    await tester.pump();
    expect(auth.busy, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('login'))).onPressed,
      isNull,
    );
    expect(repository.submittedEmail, 'fictional@example.invalid');
    repository.pendingLogin!.complete();
    await tester.pumpAndSettle();
    expect(find.text('이메일 또는 비밀번호가 올바르지 않습니다.'), findsOneWidget);
    expect(repository.loginCalls, 1);
    expect(logs, contains('[auth] authentication failed code=wrong-password'));
    expect(repository.requestedUid, isNull);
    expect(logs.any((line) => line.startsWith('[auth] profile')), isFalse);
    expect(find.text('송영 현황'), findsNothing);
  });

  testWidgets('직원 Authentication 성공 후 staffId 누락을 로그로 구분하고 보정 시 직원 화면을 연다', (
    tester,
  ) async {
    await tester.pumpWidget(
      MyApp(auth: auth, schedules: MemoryScheduleRepository()),
    );
    repository.sessions.add(null);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('email')),
      'staff01@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('password')),
      'fictional-input',
    );
    await tester.tap(find.byKey(const Key('login')));
    await tester.pump();
    expect(auth.signedIn, isTrue);
    expect(logs, contains('[auth] authentication succeeded'));
    final document = <String, dynamic>{
      'active': true,
      'email': 'staff01@example.com',
      'name': '직원1',
      'role': 'staff',
    };
    try {
      AppUser.fromDocument('fictional-user', document);
      fail('A staff profile must reference an assigned staff ID');
    } on UserProfileException catch (failure) {
      repository.profiles.addError(failure);
    }
    await tester.pumpAndSettle();
    expect(logs, contains('[auth] profile failed code=invalidStaffMapping'));
    expect(auth.signedIn, isTrue);
    expect(auth.user, isNull);
    expect(find.textContaining('담당 직원 정보가 연결되지'), findsOneWidget);
    expect(find.text('내 송영 일정'), findsNothing);
    repository.profiles.add(
      AppUser.fromDocument('fictional-user', {...document, 'staffId': 's1'}),
    );
    await tester.pumpAndSettle();
    expect(logs, contains('[auth] profile succeeded role=staff'));
    expect(find.text('내 송영 일정'), findsOneWidget);
    expect(find.byKey(const Key('confirm-schedule')), findsNothing);
    expect(logs.join('\n'), isNot(contains('staff01@example.com')));
    expect(logs.join('\n'), isNot(contains('fictional-input')));
    expect(logs.join('\n'), isNot(contains('fictional-user')));
    expect(logs.join('\n'), isNot(contains('직원1')));
  });

  testWidgets('Firestore 권한 거부는 Authentication 실패와 별도 로그를 남긴다', (tester) async {
    await tester.pumpWidget(
      MyApp(auth: auth, schedules: MemoryScheduleRepository()),
    );
    repository.sessions.add('fictional-user');
    await tester.pump();
    repository.profiles.addError(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
    await tester.pumpAndSettle();
    expect(auth.signedIn, isTrue);
    expect(auth.user, isNull);
    expect(logs, contains('[auth] profile failed code=permission-denied'));
    expect(logs.any((line) => line.contains('authentication failed')), isFalse);
    expect(find.textContaining('관리자에게 권한 확인'), findsOneWidget);
    expect(find.text('내 송영 일정'), findsNothing);
  });

  testWidgets('저장된 인증 복원 후 역할 확인, 직원 이동 및 로그아웃', (tester) async {
    await tester.pumpWidget(
      MyApp(auth: auth, schedules: MemoryScheduleRepository()),
    );
    repository.sessions.add('fictional-user');
    await tester.pump();
    expect(repository.requestedUid, 'fictional-user');
    expect(find.text('내 송영 일정'), findsNothing);
    repository.profiles.add(staff);
    await tester.pumpAndSettle();
    expect(find.text('내 송영 일정'), findsOneWidget);
    expect(find.byKey(const Key('confirm-schedule')), findsNothing);
    await tester.tap(find.byKey(const Key('logout')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login')), findsOneWidget);
    expect(find.text('내 송영 일정'), findsNothing);
  });

  testWidgets('로그인 성공 후 관리자 화면으로 이동한다', (tester) async {
    await tester.pumpWidget(
      MyApp(auth: auth, schedules: MemoryScheduleRepository()),
    );
    repository.sessions.add(null);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('email')),
      'fictional@example.invalid',
    );
    await tester.enterText(
      find.byKey(const Key('password')),
      'fictional-input',
    );
    await tester.tap(find.byKey(const Key('login')));
    await tester.pump();
    repository.profiles.add(admin);
    await tester.pumpAndSettle();
    expect(find.text('송영 현황'), findsOneWidget);
    expect(find.byKey(const Key('login')), findsNothing);
    repository.sessions.addError(
      FirebaseAuthException(code: 'network-request-failed'),
    );
    await tester.pumpAndSettle();
    repository.profiles.add(admin);
    await tester.pumpAndSettle();
    expect(find.text('송영 현황'), findsNothing);
    expect(find.textContaining('네트워크'), findsOneWidget);
  });

  testWidgets('관리자 권한 제거는 열린 일정 확정 대화상자까지 제거한다', (tester) async {
    await tester.pumpWidget(
      MyApp(auth: auth, schedules: MemoryScheduleRepository()),
    );
    repository.sessions.add('fictional-user');
    await tester.pump();
    repository.profiles.add(admin);
    await tester.pumpAndSettle();
    expect(find.text('송영 현황'), findsOneWidget);
    final confirm = find.byKey(const Key('confirm-schedule'));
    await tester.scrollUntilVisible(
      confirm,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('approve-confirm')), findsOneWidget);
    repository.profiles.add(staff);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('approve-confirm')), findsNothing);
    expect(find.text('송영 현황'), findsNothing);
    expect(find.text('내 송영 일정'), findsOneWidget);
  });

  testWidgets('잘못된 역할과 서버 오류는 접근을 차단하고 재시도를 제공한다', (tester) async {
    await tester.pumpWidget(
      MyApp(auth: auth, schedules: MemoryScheduleRepository()),
    );
    repository.sessions.add('fictional-user');
    await tester.pump();
    repository.profiles.addError(
      const UserProfileException(UserProfileFailure.missingDocument),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('계정 설정을 확인'), findsOneWidget);
    expect(find.text('송영 현황'), findsNothing);
    await tester.tap(find.text('다시 확인'));
    await tester.pump();
    repository.profiles.add(admin);
    await tester.pumpAndSettle();
    repository.profiles.addError(
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('네트워크'), findsOneWidget);
    expect(find.text('송영 현황'), findsNothing);
  });

  testWidgets('active 누락으로 차단 후 Console 문서 보정 이벤트에서 관리자 화면을 연다', (
    tester,
  ) async {
    await tester.pumpWidget(
      MyApp(auth: auth, schedules: MemoryScheduleRepository()),
    );
    repository.sessions.add('fictional-admin-uid');
    await tester.pump();
    expect(repository.requestedUid, 'fictional-admin-uid');
    repository.profiles.addError(
      const UserProfileException(UserProfileFailure.missingActive),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('계정 설정을 확인'), findsOneWidget);
    expect(find.text('송영 현황'), findsNothing);
    repository.profiles.add(
      AppUser.fromDocument('fictional-admin-uid', {
        'email': 'admin@example.com',
        'name': '관리자',
        'role': 'admin',
        'active': true,
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('송영 현황'), findsOneWidget);
  });

  testWidgets('로그아웃 이벤트는 직원의 사진 인증 안내 화면까지 제거한다', (tester) async {
    await tester.pumpWidget(
      MyApp(auth: auth, schedules: MemoryScheduleRepository()),
    );
    repository.sessions.add('fictional-user');
    await tester.pump();
    repository.profiles.add(staff);
    await tester.pumpAndSettle();
    expect(find.text('사진 등록을 사용할 수 없습니다. 관리자에게 문의해 주세요.'), findsOneWidget);
    repository.sessions.add(null);
    await tester.pumpAndSettle();
    expect(find.text('사진 등록을 사용할 수 없습니다. 관리자에게 문의해 주세요.'), findsNothing);
    expect(find.byKey(const Key('login')), findsOneWidget);
  });
}
