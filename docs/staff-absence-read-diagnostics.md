# A-1 결근 정보 조회 오류 진단

## 확인한 원인과 연결 대상

`flutter run -d chrome`은 디버그 실행이지만 Emulator 실행은 아니다. `USE_FIREBASE_EMULATORS` 기본값이 false이므로 현재 설정에서는 실제 `senior-transport-app`의 기본 Firestore 데이터베이스 `(default)`를 사용한다. Emulator는 명시적 `--dart-define=USE_FIREBASE_EMULATORS=true` 옵션이 필요하다. `.firebaserc`나 Firebase CLI 프로젝트 선택이 Flutter의 이 분기를 바꾸지는 않는다.

기존 결근 구독의 `onError`는 실제 예외를 로그로 남기지 않고 동일한 화면 문구로 바꿨다. 따라서 Authentication과 프로필 조회가 성공해도 결근 조회 실패 코드가 Console에 나타나지 않았다. 또한 캐시 응답을 직접 만든 `FirebaseException(code: unavailable)`로 바꾸어 실제 서버 네트워크 오류와 구분할 수 없었다.

관리자 조회 경로는 `staffAvailability/{YYYY-MM-DD}/staff`이며, 직원 조회 경로는 그 아래 `users/{uid}.staffId` 문서이다. 서버 저장 경로와 같다. 사용자 UID나 카탈로그 하위 경로를 결근 문서 ID로 쓰지 않는다.

로컬 Rules에는 해당 경로의 관리자 `list`, 관리자/본인 직원 `get` 권한이 있다. 관리자 판정은 Authentication UID에 해당하는 사용자 프로필의 `active == true`, `role == 'admin'`이다. 사용자 본인 프로필 읽기는 별도 규칙이므로 **프로필 조회 성공만으로 새 경로 읽기 권한을 보장하지 않는다.** A-1 이전 Rules에는 이 경로의 허용이 없어 기본 거부된다. 실제 게시된 Rules가 이전 버전이면 문서가 없는 날짜도 `permission-denied`로 실패한다. 실제 배포본은 원격 조회하지 않았으므로 게시 버전 불일치는 아직 확인이 필요한 원인 후보이다.

## 로컬 수정

- `lib/main.dart`: 디버그 시작 시 프로젝트 ID, 실제/Emulator 환경, 리전과 서비스 연결 대상을 출력한다. 키·비밀번호·토큰은 출력하지 않는다.
- `lib/services/staff_availability_diagnostics.dart`: 서버 스냅샷 검사와 디코딩, 오류별 화면 문구, 디버그 로그를 분리한다. Firebase 예외의 실제 런타임 유형·code·message를 출력한다. FormatException은 메시지만 기록하며 문서 값이 담길 수 있는 source나 임의 예외의 전체 문자열은 기록하지 않는다.
- `lib/services/schedule_repository.dart`: 조회 프로젝트·경로·목록/본인 조회 범위를 기록하고 공통 디코더를 사용한다. 캐시는 가짜 unavailable 대신 서버 미확인 상태를 전달한다.
- `lib/services/schedule_controller.dart`: 성공/서버 대기/실패 로그를 남긴다. 초기 캐시는 확인 중으로 표시하며 서버 결과를 기다린다. 15초간 서버 확인이 없으면 명확한 시간 초과로 안내한다. 이후 서버 결과가 도착하면 복구할 수 있다. 이전 서버 확인 후 캐시만 도착한 경우에도 다시 미확인 상태로 전환해 확정을 차단한다.
- `test/staff_absence_test.dart`: 빈 결과, 캐시, 시간 초과, 권한/인증/네트워크 오류, 잘못된 문서, 로그, 재연결과 확정 차단의 회귀 테스트를 추가한다.
- `functions/test/staff-absence.test.cjs`: 같은 빈 컬렉션이 A-1 Rules에서는 정상이고 이전 Rules에서는 권한 거부되는지 Emulator로 비교한다. 서버 구현이나 Rules 자체는 이 진단 수정에서 바꾸지 않는다.

| 상황 | 처리 |
|---|---|
| 서버 조회 성공, 문서 0개/본인 문서 없음 | `read_succeeded state=verified-empty`. 결근 기록 없음/기본 버전 0. 다른 일정 검증을 통과해야 확정 가능 |
| 캐시/미반영 쓰기만 확인 | `read_waiting ... code=server-unverified`. 확인 중, 확정 불가 |
| 서버 확인 15초 초과 | `read_failed ... code=server-verification-timeout`. 시간 초과, 확정 불가 |
| Firestore permission-denied | 실제 예외 type/code/message 로그, 게시된 Rules·연결 프로젝트 확인 안내, 확정 불가 |
| unavailable/deadline-exceeded | 실제 코드·메시지 로그, 연결 오류 안내, 확정 불가 |
| unauthenticated | 인증 오류 안내, 확정 불가 |
| 문서 형식 오류 | FormatException/invalid-document 로그, 데이터 형식 확인 안내, 확정 불가 |

**컬렉션이나 부모 날짜 문서를 미리 만들 필요는 없다.** 빈 컬렉션/본인 문서 부재도 서버 조회에 성공해야 정상적인 결근 없음이다. 권한 오류·캐시·네트워크 오류를 빈 결과로 바꾸지 않는다.

## 재실행 후 확인할 로그

기존 앱을 종료한 뒤 같은 `flutter run -d chrome`으로 시작한다. 디버그 Console에서 `[firebase]`, `[staff-availability]`를 검색한다. 다음은 권한 오류일 때의 예시이며, 실제 프로젝트에서 관측한 로그는 아니다.

```text
[firebase] project=senior-transport-app environment=firebase region=asia-northeast3 ...
[staff-availability] read_started project=senior-transport-app path=staffAvailability/2026-11-13/staff scope=admin-list
[staff-availability] read_failed type=FirebaseException code=permission-denied message=Missing or insufficient permissions.
```

`read_waiting`은 서버 응답 전일 수 있으므로 그 뒤의 `read_succeeded` 또는 `read_failed`를 확인한다. 권한 거부라면 Firebase Console에서 프로젝트 ID와 `(default)` 데이터베이스를 확인하고 **현재 게시된 Rules**에 아래 경로의 조회 권한이 있는지 로컬 `firestore.rules`와 비교한다. Rules 편집·게시는 별도 배포 작업이므로 이번 진단에서 수행하지 않는다. 사용자 `active`/`role`을 우회하거나 `allow read: if true`로 바꾸지 않는다.

```text
match /staffAvailability/{date}/staff/{staffId}
  관리자: list/get
  직원: 본인 staffId get만
  모든 클라이언트: write 거부
```

결근 **조회**는 Firestore 직접 구독이므로 Cloud Functions 배포 여부가 이 조회 오류를 직접 만들지는 않는다. 그러나 등록에는 새 `setStaffAbsence`가, 확정에는 결근 검증과 `expectedAvailabilityVersions`를 지원하는 새 `confirmSchedule`이 필요하다. 이전 확정 함수는 새 필드를 `invalid-argument`로 거부할 수 있다. 조회가 정상화되어도 서버 보호 적용이 완료되었다고 판단하지 말고 향후 승인된 배포에서 Rules·두 함수·클라이언트의 버전을 함께 검증해야 한다.

이번 작업에서 실제 Firebase 조회·데이터 변경·Functions/Rules 배포는 수행하지 않는다. 재현과 테스트는 로컬 가상 저장소와 demo 프로젝트 Emulator에 한정한다.

## 로컬 검증 결과

- `flutter analyze`: No issues found.
- `flutter test`: 112개 모두 통과. 이번 진단의 10개 테스트를 포함한다.
- Auth·Firestore·Functions Emulator 테스트: 48개 모두 통과. 현재 A-1 Rules에서 빈 컬렉션/없는 본인 문서가 서버 확인된 정상 결과이고, 이전 Rules에서는 같은 빈 컬렉션의 관리자 조회도 `permission-denied`로 실패함을 재현했다.
- 테스트 로그: Git 제외 `.local-tools/absence-diagnostics-flutter-test.log`, `.local-tools/absence-diagnostics-emulator-test.log`. 실제 게시된 Rules의 버전이나 사용자의 실제 실패 코드를 원격 검증한 결과는 아니다.
