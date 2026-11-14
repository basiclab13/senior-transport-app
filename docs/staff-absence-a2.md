# A-2 결근 직원의 코스 전체 재배정

## 동작과 범위

관리자가 선택한 날짜·오전/오후의 결근 직원 상세에서 담당 코스의 **코스 전체 재배정**을 누른다. 이름 검색과 `재배정 가능만` 필터를 제공한다. 대상 직원의 현재 근무 가능 여부, 코스명·차량·이용자 수, 인계 후 이용자 수와 원래 차량 승계를 표시한다.

다음 대상은 사유를 표시하고 선택하지 못하게 한다. 컨트롤러 명령에서도 같은 판단 로직으로 재검사한다.

- 현재 담당자, 해당 날짜·시간대 결근자, 비활성/기본 휴무 직원
- 해당 시간대 이미 코스가 있는 직원 (이용자 0명 코스도 포함)
- 원래 코스의 차량 정보가 없거나 정원이 초과된 경우
- 원래 차량이 다른 코스에도 중복 배정된 경우

현재 근무 모델에서 시간대별 코스들은 동시에 운행한다. 다른 코스를 가진 직원에게 시간을 달리해 추가 인계하거나 두 코스를 합치는 기능은 제공하지 않는다. 기존 코스가 없는 근무 가능 직원에게 하나의 코스를 인계한다. 대상의 별도 차량을 자동 선택하지 않고 **원래 코스의 차량**을 함께 넘긴다.

선택하면 `RouteAssignment.staffId`만 바꾼 새 초안을 만든다. 코스 ID, 차량 ID, 이용자 전체 목록, 방문 순서, 수동 예상 방문 시각과 운행 구간, 결석·제외 목록은 유지한다. 기본 코스 마스터·직원 마스터·사용자 프로필은 바꾸지 않는다. 저장 또는 확정을 자동 호출하지 않는다.

전체 확정 전 기존 변경 요약에 `코스: 이전 직원 → 새 직원`을 표시한다. 확정 이력이 없을 때도 기본 배정 대비 담당자 변경을 표시하고, 첫 확정임을 함께 알린다. 미확정 단계에서는 기존 확정 이력에 결근 직원의 코스가 남아 있다는 A-1 경고를 유지한다. 새 확정본이 서버에서 확인된 후에 정상 확정 상태로 표시한다.

미배정 가능한 직원이 없거나 대화상자를 닫으면 초안은 그대로이며 재배정 필요도 남는다. 하나를 인계했더라도 다른 결근 직원의 코스가 남으면 전체 확정을 계속 차단한다. 종일 결근은 결근 상태를 오전·오후에 함께 적용하지만 **코스 인계는 현재 선택한 날짜·시간대 하나에만 적용**한다. 오후 코스는 오후를 선택해 별도로 검토·재배정·확정해야 한다.

직원 본인 결근 신청·승인이나 예상 시각 자동 계산은 추가하지 않는다.

## 권한·저장·동시성

Firestore 스키마와 Callable API는 추가하지 않는다. 기존 `confirmSchedule`의 전체 일정 요청에 변경된 `routes[].staffId`를 포함한다.

- A-2 초안 명령은 관리자만 사용할 수 있다. 결근 정보가 서버 미확인/오류 상태이거나 저장 중·일정 버전 충돌이면 차단한다.
- 대상 대화상자는 캡처한 일정·카탈로그·결근 버전을 사용한다. 대화상자 도중 이 값이 바뀌면 초안에 반영하지 않고 다시 선택하도록 안내한다.
- 확정 시 기존 검증이 직원당 1개 코스, 차량 중복·정원, 이용자 중복·누락, 방문 시각을 검증한다. A-1 서버 검증은 새 담당자의 날짜별 결근과 검토한 결근 버전을 다시 검사한다.
- 기존 일정 CAS(`expectedVersion`), 요청 ID/해시 영수증, 읽기를 모두 먼저 수행하는 트랜잭션 구조를 그대로 사용한다.
- 같은 날짜·시간대의 기존 담당 직원용 문서 제거와 새 담당 직원용 문서 저장은 기존 확정 트랜잭션에서 함께 처리한다. 다른 날짜와 시간대는 건드리지 않는다.
- Rules의 관리자/직원 구분 및 클라이언트 직접 쓰기 금지를 유지한다. 직원은 인계가 확정된 뒤 본인의 새 일정만 조회한다.

## 변경 파일

| 파일 | 역할 |
|---|---|
| `lib/models/course_reassignment.dart` | 대상 가능 여부와 선택 불가 사유의 공통 판단 |
| `lib/widgets/course_reassignment_dialog.dart` | 이름 검색·필터·근무/코스/이용자/차량 표시 |
| `lib/services/schedule_controller.dart` | 결근 코스를 초안에서만 넘기는 관리자 명령 |
| `lib/screens/admin_schedule_view.dart` | 결근 코스의 바로 재배정 진입점, 최신 상태 검사, 초안 반영 안내 |
| `lib/models/schedule_changes.dart` | 첫 확정 전에도 기본 배정 대비 이전·새 담당자 요약 |
| `test/course_reassignment_test.dart` | 초안 보존, 시간대·날짜 분리, 불가 대상, 요약, 동시 변경·작은 화면 테스트 |
| `functions/test/staff-absence.test.cjs` | 20명·80명 서버 인계·기존/신규 직원 문서·직원 권한·중복 요청·충돌 통합 검증 |
| `tools/operations_browser.cjs` | 옵션으로 실행하는 A-2 실제 Chrome+Emulator 흐름 |

## 로컬 검증과 재현

```powershell
flutter analyze
flutter test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/test-emulators.ps1
```

Chrome 확인은 별도 새 Emulator 세션에서 수행한다. `tools/start_operations_emulators.ps1`로 로컬 Emulator를 시작하고 다른 터미널에서 실행한다. Node 22, Java 21, Firebase CLI, Chrome을 사용한다. 이전 검증에서 수정된 스냅샷을 가져오지 않는다.

```powershell
flutter build web --debug --dart-define=USE_FIREBASE_EMULATORS=true
$env:GCLOUD_PROJECT = 'demo-senior-transport'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
$env:OPERATIONS_RUN_LABEL = 'course-transfer-a2'
$env:OPERATIONS_CHECK_COURSE_TRANSFER = 'true'
node tools/operations_browser.cjs
```

기존 20명/80명/차량 20대/코스 38개 fixture를 사용한다. 시간대마다 19개 코스와 예비 직원 s3가 있다. 예비 직원의 기본 금요일 휴무를 바꾸지 않고 금요일 실행이면 이미 등록 도구가 준비하는 내일 일정을 사용한다. 원래 담당 s1의 종일 결근 → 오전 코스 대상 검색 → s3에게 초안 인계 → 서버 변경 없음 확인 → 전체 요약/확정 → s3의 실제 로그인 조회를 검증한다. 원래 차량과 이용자·순서·예상 시각 전체 동일성, 기존 직원 문서 제거, 다른 날짜·시간대 보존과 다른 직원 문서 읽기 거부도 확인한다. 로그와 생성 비밀번호·스크린샷은 Git 제외 `.local-tools/course-transfer-a2/`에 저장한다. 앱과 도구는 demo/loopback만 사용하고 브라우저는 원격 Firebase endpoint를 차단한다.

`flutter analyze`는 No issues found, Flutter 테스트 121개와 Emulator 테스트 49개가 모두 통과했다. Emulator 전용 debug 웹 빌드도 성공했다.

실제 Chrome 통합 검증은 `COMPLETE`로 종료했다. 직원 20명·이용자 80명의 가상 환경에서 2026-11-14 오전의 s1 → s3 인계를 v1 → v2로 확정했다. 종일 결근 등록, 대상 검색과 이미 코스가 있는 직원 표시, 초안 단계 서버 무변경, 이전/새 담당자 요약, 이용자·순서·원래 차량·예상 시각의 전체 동일성, 기존/신규 직원 문서 교체, 다른 날짜·오후 일정 보존, 새 담당자의 실제 로그인·PC/모바일 조회와 타 직원 문서 읽기 거부를 확인했다. JavaScript 예외 0건, 원격 Firebase 요청 0건이다.

최종 결과는 `.local-tools/course-transfer-a2/report.json`, 화면 기록은 같은 디렉터리의 `a2-*.png`이다. Flutter·Emulator 로그는 `.local-tools/a2-flutter-test.log`, `.local-tools/a2-emulator-test.log`이다. Emulator의 예상 PERMISSION_DENIED 로그는 권한 거부 테스트 결과이며 테스트 실패가 아니다. 테스트 종료 후 로컬 Emulator를 종료했다.

## 실제 배포 전 확인 사항

실제 Firebase의 Functions와 Rules는 사용자가 알려준 대로 A-1 이전 버전으로 취급한다. **현재 로컬 클라이언트만 실제 Firebase에서 실행해 A-2가 보호된다고 판단하지 않는다.** 이번 작업에서는 실제 데이터·배포·요금제 설정을 바꾸지 않는다.

향후 별도 승인된 배포에서는 다음을 함께 검토해야 한다.

1. A-1의 `staffAvailability/{date}/staff/{staffId}` 읽기 Rules (관리자 목록, 직원 본인 문서)와 직접 쓰기 금지.
2. A-1 관리자 Callable `setStaffAbsence` 및 결근/버전 검증이 반영된 `confirmSchedule`. A-2 전용 새 Function은 필요 없다.
3. A-1 조회 진단과 A-2 초안 UI를 포함한 클라이언트 갱신. 리전은 기존 `asia-northeast3`, 런타임은 Node 22를 유지한다.
4. 실제 관리자·직원의 기존 UID 프로필, `active`·`role`·`staffId` 및 활성 가상 카탈로그의 연결 확인. 이 기능 때문에 사용자 문서를 다시 생성하거나 덮어쓸 필요는 없다.
5. 별도 가상 테스트 날짜에서 결근 등록·인계·확정·직원 조회, 다른 시간대/날짜 보존, 동시 관리자 충돌, 권한 거부를 배포 후 재검증. Blaze·유료 서비스 활성화와 실제 배포는 사용자가 별도로 검토한다.
