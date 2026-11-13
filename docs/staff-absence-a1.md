# A-1 관리자 날짜별 결근 등록과 상태 표시

후속 코스 전체 재배정(A-2)은 [staff-absence-a2.md](staff-absence-a2.md)에 정리한다. 아래 범위 설명은 A-1 단계의 기록이다.

조회 실패 코드가 표시되지 않는 경우의 분석과 디버그 로그·빈 결과/캐시/실패 구분은 [staff-absence-read-diagnostics.md](staff-absence-read-diagnostics.md)를 참고한다.

날짜별 오전·오후·종일 결근의 관리자 등록·취소와 상태 표시를 구현한다. 직원 본인의 신청·승인, 새로운 코스 일괄 재배정, 예상 시각 자동 계산은 추가하지 않는다. 기존 직원 변경·이용자 편집과 전체 일정 검증·확정을 유지한다.

## 화면과 적용 범위

- 관리자 직원 상세의 `날짜별 결근 등록·취소`에서 날짜와 오전·오후·종일을 지정한다. 결근 저장은 일정 확정과 별도의 명시적 관리자 작업이다.
- 직원 목록, 근무 필터, 전체 배정 현황, 직원 상세에 결근을 반영한다. 담당 코스가 남으면 `재배정 필요`를 표시한다. 기존 이용자 재배정 대화상자의 근무 가능 여부에도 반영한다.
- 직원은 본인 결근만 조회한다. 결근 직원에게 남은 기존 확정 일정은 정상 운행 일정이 아닌 확정 이력으로 표시한다. 직원에게 결근 등록·취소 컨트롤은 제공하지 않는다.
- 결근 저장 중 편집·날짜 이동·확정을 잠근다. 저장 오류와 충돌을 알리고, 작성 중인 일정 초안은 버리지 않는다.
- 결근과 일정은 서버 스트림으로 조회한다. 한쪽이라도 조회 실패 또는 캐시 데이터만 있는 경우 정상 일정/확정 가능 상태를 표시하지 않는다.
- `users/{uid}`의 `active`, `role`, `staffId`, 직원 마스터의 `active`, `unavailableWeekdays`와 다른 날짜 데이터는 수정하지 않는다.

## Firestore 구조

`staffAvailability/{YYYY-MM-DD}/staff/{staffId}`:

```json
{
  "schemaVersion": 1,
  "date": "2026-11-16",
  "staffId": "s1",
  "unavailablePeriods": ["afternoon", "morning"],
  "version": 1,
  "updatedBy": "관리자 Authentication UID",
  "updatedAt": "Firestore serverTimestamp"
}
```

`updatedAt`은 문자열이 아닌 Timestamp이다. 오전은 `["morning"]`, 오후는 `["afternoon"]`, 종일은 두 항목, 모두 취소하면 `[]`이다. 문서가 없으면 결근 없음/버전 0이다. 취소 후에도 문서를 삭제하지 않고 버전을 증가시켜 이전 버전으로 되돌아가는 동시성 문제를 막는다. 상위 날짜 문서는 필요 없다.

동일 직원 ID는 카탈로그 버전이 달라도 동일 직원이라는 기존 규칙을 따른다. 결근은 카탈로그 버전에 종속되지 않는다. 서버에서 현재 활성 카탈로그 또는 해당 날짜 기존 오전·오후 확정본의 카탈로그에 실제 존재하는 직원인지 검증한다.

`.../staff/{staffId}/commits/{requestId}`에 요청자 UID, 정규화한 요청의 SHA-256 해시, 결과 버전/시간대, 서버 시각을 저장한다. 응답 유실 시 중복 등록을 방지하며 관리자 단건 읽기만 허용한다.

## 서버 정합성과 동시성

`setStaffAbsence`는 기존 `confirmSchedule`과 같은 Node 22/asia-northeast3 Callable이다. 입력은 `date`, `staffId`, `periods`, `absent`, `expectedVersion`, `requestId`, `catalogVersion`이다.

1. 트랜잭션에서 사용자 프로필, 현재 결근, 요청 영수증, 카탈로그 포인터, 해당 날짜 오전·오후 일정, 카탈로그 메타데이터와 직원 문서를 모두 먼저 읽는다.
2. 활성 관리자, 날짜·시간대·직원 참조와 버전을 검증한다. 다른 관리자 변경은 `aborted`로 거부한다.
3. 요청 시간대만 추가·제거하고 결근과 영수증을 함께 저장한다. 종일은 한 문서의 한 번의 원자적 변경이다. 같은 요청 ID와 내용의 재시도는 같은 결과를 반환한다.

`confirmSchedule`은 기존 검증에 더해 배정된 모든 직원의 날짜별 결근 문서를 **같은 트랜잭션에서 쓰기 전에** 읽는다. 해당 시간대 결근 직원에게 코스가 하나라도 남으면 `failed-precondition`으로 거부한다. 이용자 0명 코스도 예외가 아니다. 새 클라이언트는 검토한 결근 버전(`expectedAvailabilityVersions`)도 보내며, 검토 후 등록·취소로 버전이 바뀌면 `aborted`로 다시 검토하도록 한다. 이전 클라이언트가 이 필드를 생략해도 실제 결근 검사는 생략되지 않는다.

두 작업은 결근과 일정 문서를 교차해 읽으므로 Firestore 트랜잭션 순서에 따라 직렬화된다.

- 결근이 먼저 커밋되면 뒤의 해당 직원 일정 확정은 실패한다.
- 일정 확정이 먼저 커밋되면 뒤의 결근 등록은 유지된 확정 이력을 `재배정 필요`로 바꾼다. 과거 확정본과 직원용 문서는 삭제·수정하지 않는다. 현재 결근 상태를 합쳐 판단하므로 정상 운행 가능으로 취급하지 않는다.
- **`schedules.status == confirmed` 단독으로 현재 운행 가능 여부를 판단하면 안 된다.** 화면이나 후속 소비자는 날짜별 결근 정보를 함께 확인해야 한다. 기존 요청 영수증 재조회는 과거 성공 확인이며 새 확정이 아니다.

기존 일정 버전 충돌 방지, 전체 직원 단위 확정, 직원용 문서 원자적 교체·삭제, 정원·중복·시간 검증을 유지한다. 모든 트랜잭션 읽기를 첫 쓰기 전에 수행한다.

## 권한과 로컬 검증

Rules는 활성 관리자에게 날짜별 결근 목록 조회, 직원에게 본인 ID 단건 조회만 허용한다. 관리자 포함 모든 클라이언트 직접 쓰기를 거부한다. Functions는 Admin SDK가 Rules를 우회하므로 Callable 트랜잭션 내에서 Authentication UID의 활성 관리자 프로필을 별도로 검사한다.

Flutter 테스트는 `test/staff_absence_test.dart`, 서버 테스트는 `functions/test/staff-absence.test.cjs`와 기존 Callable 통합 테스트의 새 검사를 사용한다. 직원 20명·이용자 80명 가상 카탈로그를 별도 `demo-staff-absence` Emulator 네임스페이스에서 검증한다. 기존 인증·보안·일정 테스트도 실행한다.

```powershell
flutter analyze
flutter test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/test-emulators.ps1
```

브라우저 확인은 새 Emulator 전용 빌드를 사용한다. 다른 터미널에서 `tools/start_operations_emulators.ps1`을 실행한 뒤 다음 환경을 지정한다. Node 22, Java 21과 로컬 Chrome이 필요하다. 기존 스냅샷을 가져오지 않은 새 Emulator에서 실행한다.

```powershell
flutter build web --debug --dart-define=USE_FIREBASE_EMULATORS=true
$env:GCLOUD_PROJECT = 'demo-senior-transport'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
$env:OPERATIONS_RUN_LABEL = 'absence-a1'
$env:OPERATIONS_CHECK_ABSENCE = 'true'
node tools/operations_browser.cjs
```

브라우저 테스트는 종일 등록 → 전체 현황 → 새로고침 유지 → 본인 직원 화면 경고 → 관리자 취소 후 기존 편집·재배정·확정 흐름을 검증한다. 생성 비밀번호와 로그·스크린샷은 Git 제외 `.local-tools/absence-a1/`에만 보관한다.

새로고침 테스트는 개발 실행과 같은 debug 모드를 사용한다. 현재 Auth Web SDK의 Emulator origin 복원은 debug 모드에서 수행된다. release Emulator 빌드에서는 저장된 로그인 복원 후 재로그인이 원격 Auth endpoint를 향하는 현상을 확인했고, 테스트 브라우저에서 차단했다. 운영용 인증 코드를 변경하거나 우회하지 않는다. 원격 Firebase endpoint 차단과 demo 프로젝트/loopback 가드는 그대로 유지한다.

## 변경 파일

| 파일 | 변경 이유 |
|---|---|
| `lib/models/staff_absence.dart` | 날짜별 결근의 버전·시간대 모델 및 서버 데이터 형식 검사 |
| `lib/services/schedule_repository.dart` | 관리자 날짜별 목록/직원 본인 문서 구독, Callable 연결 |
| `lib/services/schedule_controller.dart` | 결근 저장 상태, 오류·충돌·재시도, 기존 초안 유지, 결근 포함 일정 검증 |
| `lib/screens/admin_schedule_view.dart` | 날짜별 결근 등록·취소, 목록·상세 상태와 작은 화면 대화상자 |
| `lib/screens/schedule_screen.dart`, `lib/screens/staff_schedule_view.dart` | 결근 조회 전 정상 표시 차단, 과거 확정본 경고, 확정 검토 후 결근 버전 변경 감지 |
| `lib/widgets/admin_assignment_overview.dart`, `lib/widgets/reassignment_dialog.dart` | 전체 현황 결근 수/재배정 필요, 기존 재배정의 근무 가능 여부 |
| `functions/staff-absence-service.js`, `functions/index.js` | 관리자 Callable의 원자적 저장, 버전 비교와 요청 영수증 |
| `functions/schedule-service.js`, `functions/validation.js` | 확정 트랜잭션의 결근 상태 및 검토 버전 검사 |
| `firestore.rules` | 결근 관리자 목록/직원 본인 조회와 직접 쓰기 금지 |
| `test/staff_absence_test.dart`, `functions/test/staff-absence.test.cjs`, `functions/test/emulator.test.cjs` | Flutter UI·상태 및 Emulator 권한·동시성·실제 Callable 회귀 테스트 |
| `tools/operations_browser.cjs` | 옵션으로 실행하는 Chrome 결근 흐름 검증 |
| `docs/staff-absence-a1.md`, `docs/firestore-schedules.md`, `docs/staff-centered-schedules.md` | 데이터 계약, 현재 운행 가능 판단, 실행 절차와 검증 기록 |

## 검증 결과 (2026-11-13)

- `flutter analyze`: No issues found.
- `flutter test`: 102개 통과. A-1 관련 13개를 포함한다. 320×568 관리자 결근 대화상자, 오전·오후·종일/취소, 조회 실패, 응답 유실 재시도, 기존 확정 이력 경고, 수동 선택과 기존 일정 회귀 검증을 포함한다.
- Auth·Firestore·Functions Emulator: 47개 통과. A-1의 20명/80명 검증과 기존 40명/79명 인증·확정·보안 검증을 함께 실행했다. 동시 관리자 변경, 결근/확정 경합, 원자적 쓰기, 읽기 선행, 요청 재시도와 직접 쓰기 차단을 검증했다. 테스트의 PERMISSION_DENIED 로그는 예상된 권한 거부 검증이다.
- `flutter build web --dart-define=USE_FIREBASE_EMULATORS=true`: 성공.
- `flutter build web --debug --dart-define=USE_FIREBASE_EMULATORS=true`: 성공. 이 debug 빌드의 Chrome+Emulator 종단 검증은 `COMPLETE`로 종료했다. 종일 결근 등록/전체 현황/새로고침/직원 본인 경고/취소와 기존 검색·시각 수정·이용자 재배정·결석·확정 v1→v2·직원 조회·모바일 화면을 통과했다. 서울 자동 선택도 브라우저 시간대를 Los Angeles로 둔 상태에서 확인했다. JavaScript 예외 0건, 원격 Firebase 요청 0건이다. 최종 결과는 `.local-tools/absence-a1/report.json`, 화면 기록은 같은 디렉터리의 PNG 파일이다.

실제 Firebase 데이터·계정은 수정하지 않고 배포도 하지 않는다. 운영 적용에는 별도 승인된 Functions(`setStaffAbsence`, 변경된 `confirmSchedule`)와 Rules 배포 및 클라이언트 갱신이 필요하다. 배포 전에는 운영 서버의 결근 보호가 적용되었다고 판단하지 않는다.
