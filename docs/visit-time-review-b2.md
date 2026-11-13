# B-2 일정 변경 시 예상 시각 재검토

## 동작과 범위

관리자 초안의 방문 순서 변경, 이용자 추가·결석·제외·복귀, 이용자 코스 이동 및 코스 담당 직원 변경(결근 인계 포함)은 영향을 받는 코스를 `예상 시각 재검토 필요`로 표시한다. 이용자 코스 이동은 출발·도착 모두 표시한다. 직원 목록, 전체 배정 현황의 건수 및 코스 상세에서 확인한다.

시각은 자동 계산하거나 삭제하지 않는다. 코스 이동 시 기존 시각과 출처를 함께 옮긴다. 결석·제외로 활성 목록에서 제거한 시각은 같은 날짜·시간대의 현재 미확정 초안에 임시 보관하고 복귀 시 복원한다. 서버에 이미 확정된 결석자의 과거 시각을 복구하거나 기본값으로 추측하지 않는다. 기본 코스, 계정, 다른 날짜·시간대에는 영향을 주지 않는다.

관리자는 다음 중 하나를 명시적으로 선택한다.

- `재계산 미리보기`: B-1 비교 화면에서 확인 후 적용한다. 수동/출처 없는 기존 시각 보호가 기본이며 변경에는 별도 확인이 필요하다. 적용 전에는 초안이 바뀌지 않는다. 보호 때문에 값이 바뀌지 않는 미리보기도 명시적 적용으로 검토 완료할 수 있다.
- `기존 시각 유지`: 변경된 방문 순서와 기존 시각 목록을 확인한 뒤 유지한다. 미입력 인원과 빈 코스도 표시한다. 미입력 시각은 기존 정책처럼 필수가 아니며 유지 시 미입력으로 남는다. 역전·동일 시각·당일 범위·운행 구간 충돌이 있으면 유지 버튼과 컨트롤러가 거부한다.

미검토 코스가 남으면 전체 검토·확정을 차단한다. 검토한 코스의 방문 구성/순서/담당자 또는 시각/운행 구간을 다시 변경하면 재검토로 돌아간다. 미리보기의 불변 초안 참조와 현재 초안, 카탈로그, 결근 리비전을 확인해 오래된 결과 적용을 거부한다. 유지 확인 대화상자도 초안·결근 변경을 확인한다. 전체 확정 요약에는 적용/유지 검토 코스 수를 표시한다.

## 서버·데이터 구조

B-2 자체의 Firestore 스키마, Rules, Functions 운영 코드 변경은 없다. `pending/kept/applied`와 이유, 임시 복귀용 시각은 컨트롤러의 날짜·시간대별 메모리 초안에만 둔다. 확정/명시적 초안 폐기 때 제거한다. 기존처럼 브라우저 새로고침으로 미확정 초안 자체가 사라지면 이 상태도 사라진다. 서버 감사 기록이나 영구 검토 승인으로 취급하지 않는다.

서버에는 기존 전체 확정 요청과 B-1의 선택 필드 `estimatedVisitSources`만 전달한다. 서버는 관리자 권한, 결근 리비전, 일정 버전, 요청 ID, 직원/차량/정원/중복/순서와 시각 충돌을 독립적으로 검증한다. 클라이언트 검토 상태로 검증을 면제하지 않는다. B-1 서버 코드가 아직 운영에 반영되지 않았다면 새 출처 필드 지원을 포함한 `confirmSchedule`을 승인된 배포 시 먼저 갱신해야 한다. 이번 작업은 배포하지 않는다.

## 변경 파일

- `lib/models/visit_time_review.dart`: 초안 검토 결정과 이유.
- `lib/services/schedule_controller.dart`: 영향 코스 감지, 이동 시각 보존, 복귀 임시 보관, 명시 검토 및 확정 차단.
- `lib/screens/admin_schedule_view.dart`: 재검토 표시, 바로 미리보기, 기존 시각 유지 확인.
- `lib/screens/schedule_screen.dart`, `lib/widgets/admin_assignment_overview.dart`: 전체 확정 차단/검토 요약, 현황 표시.
- `test/visit_time_review_test.dart`: 경계·수동 보호·두 코스·인계·다른 날짜/시간대·빈 코스·오래된 결과·실패/폐기·작은 화면 검증. 기존 흐름 테스트도 명시적 검토 단계를 거치도록 갱신.
- `functions/test/staff-absence.test.cjs`: 20명/80명 이동의 시각 충돌 원자적 거부, 재계산 값 확정, 중복 요청/다른 관리자 충돌 및 직원 조회 권한.
- `tools/operations_browser.cjs`: 기존 실제 Chrome+Emulator 규모 검증에 출발 코스 유지/도착 코스 충돌 차단/미리보기 적용 단계를 추가.

## 로컬 재현

```powershell
flutter analyze
flutter test
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-emulators.ps1
flutter build web --debug --dart-define=USE_FIREBASE_EMULATORS=true
```

새 demo Emulator를 별도 터미널에서 `tools/start_operations_emulators.ps1`로 시작한다. 가져온 운영 데이터나 실제 Firebase 프로젝트를 사용하지 않는다. 다른 검증 세션이 쓰는 8080/9099/5001 포트와 충돌하지 않아야 한다.

```powershell
$env:GCLOUD_PROJECT = 'demo-senior-transport'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
$env:OPERATIONS_RUN_LABEL = 'visit-review-b2'
Remove-Item Env:OPERATIONS_CHECK_BULK_TIMES -ErrorAction SilentlyContinue
Remove-Item Env:OPERATIONS_CHECK_COURSE_TRANSFER -ErrorAction SilentlyContinue
Remove-Item Env:OPERATIONS_CHECK_ABSENCE -ErrorAction SilentlyContinue
node tools/operations_browser.cjs
```

이 도구는 demo+loopback과 Emulator 빌드를 검사하고 실제 Firebase URL을 브라우저에서 차단한다. 가상 계정 비밀번호는 실행 때 생성하여 Git 제외 로컬 디렉터리에만 저장한다. 운영용 Hosting 산출물은 별도 준비해야 하며 이 debug 빌드를 배포하지 않는다.

## 검증 결과

`flutter analyze`는 No issues found, Flutter 테스트 157개와 Firebase Emulator 테스트 52개가 모두 통과했다. 미리보기/유지 확인 대화상자가 열린 도중의 인원·순서 변경을 실제 위젯 경로에서도 거부했다. Emulator 전용 debug Web 빌드도 성공했다. 테스트 로그는 `.local-tools/b2-flutter-tests.log`, `.local-tools/b2-emulator-tests.log`, `.local-tools/b2-web-build.log`다.

실제 Chrome+Emulator의 20명/80명 흐름은 `COMPLETE`로 종료했다. 이용자 코스 이동과 결석 → 두 코스 재검토 → 출발 코스 기존 시각 유지 → 도착 코스 시각 역전으로 유지 차단 → 고정 간격 미리보기/별도 수동 변경 확인/적용 → 전체 검토(유지 1/적용 1)/확정 v2 → 담당 직원 새 예상 시각 조회를 검증했다. 직원 본인 이외 문서/전체 일정 읽기 거부, 데스크톱/작은 화면, 한국 시간 자동 선택과 수동 선택·현재 일정 복귀도 함께 확인했다. JavaScript 예외 0건, 원격 Firebase 요청 0건이다. 결과와 화면은 `.local-tools/visit-review-b2/report.json`, 같은 폴더의 `b2-*.png` 및 `confirm-all-staff.png`다. 검색 시간 등 측정값은 로컬 headless 관측치이며 운영 환경 성능 보장은 아니다.

별도의 새 demo Emulator 세션에서 20명/80명 A-2 브라우저 회귀도 `COMPLETE`로 종료했다. 종일 결근 등록 → 코스 전체 인계 → 인계받은 직원 화면의 재검토/기존 시각 유지 확인 → 확정 v2 → 새 담당 직원 조회를 검증했다. 차량·방문 순서·시각 보존, 이전/새 직원 문서의 원자적 교체, 다른 날짜·오후 보존 및 권한 거부가 정상이며 JavaScript 예외와 원격 요청은 각각 0건이다. 결과는 `.local-tools/visit-review-b2-handoff/report.json`이다. `OPERATIONS_CHECK_COURSE_TRANSFER=true` 옵션으로 실행하며 기존 세션의 결근/확정 변경이 남아 있지 않은 새 Emulator를 사용한다.

검증 후 Emulator를 종료했다. 실제 Firebase 데이터 변경 및 배포는 수행하지 않았다. 기존 담당 직원의 결근·인계 완료 표시 문제는 [별도 개선 항목](known-issues.md)으로 유지한다.
