import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';

abstract class AuthRepository {
  Stream<String?> authChanges();
  Stream<AppUser> watchUser(String uid);
  Future<void> signIn(String email, String password);
  Future<void> signOut();
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this.auth, this.firestore);
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  @override
  Stream<String?> authChanges() =>
      auth.idTokenChanges().map((user) => user?.uid);

  @override
  Stream<AppUser> watchUser(String uid) => firestore
      .collection('users')
      .doc(uid)
      .snapshots(includeMetadataChanges: true)
      .asyncMap((snapshot) async {
        // Never grant access using a cached role or a local pending write.
        if (snapshot.metadata.isFromCache ||
            snapshot.metadata.hasPendingWrites) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'unavailable',
          );
        }
        final user = AppUser.fromDocument(uid, snapshot.data());
        if (user.role == UserRole.staff) {
          const server = GetOptions(source: Source.server);
          final settings =
              (await firestore.doc('settings/schedules').get(server)).data();
          final version = settings?['catalogVersion'];
          if (version is! String ||
              !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(version)) {
            throw const UserProfileException(
              UserProfileFailure.invalidStaffMapping,
            );
          }
          final staff = await firestore
              .doc('catalogs/$version/staff/${user.staffId}')
              .get(server);
          if (!staff.exists || staff.data()?['active'] != true) {
            throw const UserProfileException(
              UserProfileFailure.invalidStaffMapping,
            );
          }
        }
        return user;
      });

  @override
  Future<void> signIn(String email, String password) async {
    await auth.signInWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> signOut() => auth.signOut();
}

String authErrorMessage(Object error) {
  if (error is UserProfileException) {
    return switch (error.reason) {
      UserProfileFailure.missingDocument =>
        '로그인한 계정의 users/{uid} 문서가 없습니다. 관리자에게 사용자 등록을 요청해 주세요.',
      UserProfileFailure.missingActive =>
        '사용자 문서에 active 필드가 없습니다. 관리자에게 boolean 타입의 active: true 설정을 요청해 주세요.',
      UserProfileFailure.invalidActive =>
        '사용자 문서의 active 필드는 boolean 타입이어야 합니다. 관리자에게 설정 확인을 요청해 주세요.',
      UserProfileFailure.inactive => '사용이 중지된 사용자입니다. 관리자에게 문의해 주세요.',
      UserProfileFailure.invalidRole =>
        '사용자 문서의 role은 문자열 admin 또는 staff여야 합니다. 관리자에게 설정 확인을 요청해 주세요.',
      UserProfileFailure.invalidStaffMapping => '직원 계정의 staffId가 없거나 유효하지 않습니다. 실제 활성 직원 데이터의 ID를 등록해 달라고 관리자에게 요청해 주세요.',
    };
  }
  if (error is FormatException) {
    return '등록된 사용 권한이 없습니다. 관리자에게 계정 설정을 요청해 주세요.';
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'wrong-password' ||
      'user-not-found' ||
      'invalid-credential' ||
      'invalid-login-credentials' => '이메일 또는 비밀번호가 올바르지 않습니다.',
      'invalid-email' => '올바른 이메일 주소를 입력해 주세요.',
      'network-request-failed' ||
      'unavailable' ||
      'deadline-exceeded' => '네트워크 연결을 확인한 뒤 다시 시도해 주세요.',
      'too-many-requests' => '로그인 시도가 많습니다. 잠시 후 다시 시도해 주세요.',
      'user-disabled' => '사용이 중지된 계정입니다. 관리자에게 문의해 주세요.',
      'permission-denied' =>
        'Firestore에서 사용자 문서 조회가 거부되었습니다. 관리자에게 보안 규칙 확인을 요청해 주세요.',
      'not-found' => 'Firestore 조회 대상을 찾을 수 없습니다. 관리자에게 Firebase 프로젝트와 데이터베이스 설정 확인을 요청해 주세요.',
      _ => '인증 처리에 실패했습니다. 잠시 후 다시 시도해 주세요.',
    };
  }
  return '인증 처리에 실패했습니다. 잠시 후 다시 시도해 주세요.';
}

void _debugAuthLog(String message) {
  if (kDebugMode) debugPrint(message);
}

class AuthService extends ChangeNotifier {
  AuthService(this.repository, {void Function(String)? logger})
    : _logger = logger ?? _debugAuthLog {
    _authSubscription = repository.authChanges().listen(
      _onAuthChanged,
      onError: (Object failure) {
        ++_generation;
        _userSubscription?.cancel();
        _uid = null;
        _onError(failure, stage: 'session');
      },
    );
  }

  final AuthRepository repository;
  final void Function(String) _logger;
  StreamSubscription<String?>? _authSubscription;
  StreamSubscription<AppUser>? _userSubscription;
  String? _uid;
  AppUser? user;
  bool initializing = true;
  bool busy = false;
  String? error;
  int _generation = 0;
  bool _disposed = false;

  bool get signedIn => _uid != null;

  // Only stages, validated roles and error codes; never credentials, user
  // documents, UID, email, tokens, or raw exception messages.
  void _log(String event, {Object? failure}) {
    final code = switch (failure) {
      UserProfileException error => error.reason.name,
      FirebaseException error => error.code,
      null => null,
      _ => 'unexpected-error',
    };
    _logger('[auth] $event${code == null ? '' : ' code=$code'}');
  }

  void _onAuthChanged(String? uid) {
    if (_disposed) return;
    final generation = ++_generation;
    _userSubscription?.cancel();
    _uid = uid;
    user = null;
    error = null;
    initializing = uid != null;
    notifyListeners();
    if (uid == null) {
      _log('session signed_out');
      return;
    }
    _log('session authenticated');
    _log('profile started');
    _userSubscription = repository
        .watchUser(uid)
        .listen(
          (value) {
            if (_disposed || generation != _generation) return;
            user = value;
            initializing = false;
            error = null;
            _log('profile succeeded role=${value.role.name}');
            notifyListeners();
          },
          onError: (Object failure) {
            if (_disposed || generation != _generation) return;
            _onError(failure);
          },
        );
  }

  void _onError(Object failure, {String stage = 'profile'}) {
    if (_disposed) return;
    _log('$stage failed', failure: failure);
    user = null;
    initializing = false;
    error = authErrorMessage(failure);
    notifyListeners();
  }

  void retry() => _onAuthChanged(_uid);

  Future<void> signIn(String email, String password) => _perform(
    'authentication',
    () => repository.signIn(email.trim(), password),
  );

  Future<void> signOut() => _perform('logout', () async {
    await repository.signOut();
    if (!_disposed) _onAuthChanged(null);
  });

  Future<void> _perform(String stage, Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    _log('$stage started');
    try {
      await action();
      if (!_disposed) _log('$stage succeeded');
    } catch (failure) {
      if (!_disposed) {
        _log('$stage failed', failure: failure);
        error = authErrorMessage(failure);
      }
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _authSubscription?.cancel();
    _userSubscription?.cancel();
    super.dispose();
  }
}
