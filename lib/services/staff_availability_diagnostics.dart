import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/staff_absence.dart';

/// A cache snapshot says nothing about whether the server collection is empty.
class StaffAvailabilityUnverified implements Exception {
  const StaffAvailabilityUnverified({required this.pendingWrites});
  final bool pendingWrites;
}

Map<String, StaffAbsence> decodeStaffAvailability(
  String day,
  Map<String, Map<String, dynamic>> documents, {
  required bool isFromCache,
  required bool hasPendingWrites,
}) {
  if (isFromCache || hasPendingWrites) {
    throw StaffAvailabilityUnverified(pendingWrites: hasPendingWrites);
  }
  // A successful server read of an empty collection/missing own document is
  // verified absence of records. Errors must never become an empty map.
  return Map.unmodifiable({
    for (final entry in documents.entries)
      entry.key: StaffAbsence.fromJson(entry.key, entry.value, date: day),
  });
}

String staffAvailabilityErrorMessage(Object error) {
  const blocked = ' 확인 전에는 일정을 확정할 수 없습니다.';
  final reason = switch (error) {
    FirebaseException(code: 'permission-denied') => '결근 정보 읽기 권한이 없습니다 (permission-denied). 연결 프로젝트와 게시된 Firestore Rules의 관리자 조회 권한을 확인해 주세요.',
    FirebaseException(code: 'unauthenticated') =>
      '결근 정보 조회의 인증이 만료되었습니다. 다시 로그인해 주세요.',
    FirebaseException(code: 'unavailable' || 'deadline-exceeded') =>
      '결근 정보 서버에 연결하지 못했습니다. 네트워크와 Firebase 연결 대상을 확인해 주세요.',
    TimeoutException() => '결근 정보의 서버 확인 시간이 초과되었습니다. 캐시만으로 결근 없음으로 판단할 수 없습니다. 네트워크와 연결 대상을 확인해 주세요.',
    FormatException() => '결근 문서의 형식이 올바르지 않습니다. 날짜·직원 연결·버전·시간대 필드를 확인해 주세요.',
    _ => '결근 정보를 확인할 수 없습니다. 디버그 로그의 예외 유형과 오류 코드를 확인해 주세요.',
  };
  return '$reason$blocked';
}

void logStaffAvailability(
  String event, {
  Object? error,
  void Function(String)? logger,
}) {
  if (!kDebugMode) return;
  final code = switch (error) {
    FirebaseException() => error.code,
    StaffAvailabilityUnverified() => 'server-unverified',
    TimeoutException() => 'server-verification-timeout',
    FormatException() => 'invalid-document',
    _ => 'unknown',
  };
  // Never stringify arbitrary exceptions or FormatException.source: they can
  // contain document values. Standard Firebase messages are needed to diagnose
  // Rules/network failures; no credentials or document payloads are logged.
  final message = switch (error) {
    FirebaseException() => error.message ?? '(no message)',
    FormatException() => error.message,
    StaffAvailabilityUnverified() => 'Waiting for a server snapshot',
    TimeoutException() => error.message ?? '(no message)',
    _ => '(no Firebase message)',
  };
  (logger ?? debugPrint)(
    '[staff-availability] $event${error == null ? '' : ' type=${error.runtimeType} code=$code message=$message'}',
  );
}
