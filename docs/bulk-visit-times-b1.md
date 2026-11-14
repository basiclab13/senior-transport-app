# B-1 예상 방문 시각 일괄 계산

> 이전 구현 기록입니다. B-1은 제거되었습니다. 현재 동작과 배포 호환성은 [방문 시간 단순화](appointment-time-simplification.md)를 따릅니다.

사용자 확인 기준으로 실제 Firebase의 A-1/A-2 결근 등록·코스 인계·확정·새 담당 직원 조회는 정상이다. B-1은 로컬 구현과 Emulator에서만 검증하며 실제 데이터·서버·Hosting을 변경하지 않는다. 기존 담당 직원의 결근·인계 완료 표시 문제는 [별도 개선 항목](known-issues.md)으로 기록하고 이번에 수정하지 않는다.

## 사용 흐름

관리자 직원 상세의 코스별 `예상 방문 시각 일괄 계산`을 누른다. 해당 날짜·오전/오후·코스가 표시된다. 첫 방문 예상 시각(HH:mm)과 기본 방문 간격(양의 정수 분)을 입력하고 `계산 미리보기`를 누른다.

현재 방문 순서의 i번째 계산값은 `첫 시각 + i × 간격`이다. 지도·교통정보나 실제 이동 시간을 사용하지 않는다. 이 사실과 실제 운행 시각과 다를 수 있음을 화면에 표시한다. 기본 간격은 별도 상수의 5분이며 관리자가 바꿀 수 있다.

미리보기는 이용자별 기존 시각/출처, 전체 계산값, 보호 후 실제 적용 예정값을 비교해 보여준다. 기존 수동 시각은 기본 보호하며 출처가 없거나 자동 계산으로 확인되지 않는 기존 시각도 수동으로 간주한다. 보호된 시각을 기준으로 다른 방문 시각을 재배치하는 알고리즘은 아니다. 현재 순서의 고정 간격 계산값을 만든 뒤 보호된 수동 값만 유지하므로 충돌이 생기면 경고한다.

`수동 시각 변경도 미리보기`를 선택해도 초안은 바뀌지 않는다. 그 상태에서 적용을 누르고 실제 수동 변경이 있다면 이용자와 이전→새 시각을 나열한 **별도 확인 대화상자**를 표시한다. `유지`하면 미리보기로 돌아가고, `수동 시각 N개 변경 확인`을 눌러야 적용된다. 수동 값과 계산값이 같으면 수동 출처를 유지하여 다음 계산에서도 보호한다.

- 미리보기·입력 변경·취소는 일정 초안과 서버를 수정하지 않는다.
- 입력이나 수동 변경 옵션이 바뀌면 이전 미리보기를 폐기해 다시 계산해야 한다.
- 적용 결과에 순서 역전/중복 또는 기존 운행 시간 범위 충돌이 있으면 경고하고 적용을 막는다. 기존 시각의 충돌과 적용 예정 시각의 충돌을 구분한다.
- 0/음수 간격, 잘못된 첫 시각, 자정 도달·초과는 계산하지 않는다. 다음 날로 이월하거나 시각을 잘라내지 않는다. 방문자 없는 코스는 계산/적용할 수 없다.
- 적용은 캡처한 날짜·시간대·코스 초안에만 반영한다. 다른 코스·날짜·시간대와 운행 구간을 바꾸지 않는다. 결과가 의미상 동일하면 불필요하게 초안을 변경하지 않는다.
- 최종 Firestore 저장은 기존 전체 직원 변경 요약·검증·명시적 확정으로만 수행한다. 출처 변경만 있는 경우에도 요약에서 확인할 수 있다.

## 데이터와 기존 문서 호환성

기존 route의 `estimatedVisitMinutes`를 유지하고 선택 필드를 추가한다. 최상위 schedule schemaVersion은 1을 유지한다.

```text
routes[].estimatedVisitMinutes: { p1: 530, p2: 535 }
routes[].estimatedVisitSources: { p1: "manual", p2: "fixedInterval" }
```

sources는 시각이 있는 배정 이용자 ID에만 둘 수 있고 값은 manual/fixedInterval 두 가지다. Sources가 없는 기존 시각은 수동으로 취급한다. 기존 문서를 일괄 마이그레이션하거나 소급해서 자동 출처로 표시하지 않는다. 비어 있는 sources는 요청에서 생략한다.

개별 시각 수정은 해당 값을 manual로 표시하며 삭제하면 시각과 출처를 함께 제거한다. B-2부터는 다른 코스로 이동할 때 시각·출처를 그대로 옮기고 두 코스의 재검토를 요구한다. 결석·제외 시 활성 코스에서는 제거하되 같은 미확정 초안에서 복귀하면 임시 보관한 시각·출처를 복원한다. 방문 순서 변경과 A-2 코스 전체 인계도 시각·출처를 유지하고 명시적인 검토를 요구한다. 상세한 초안 수명과 검증은 [B-2 문서](visit-time-review-b2.md)를 참고한다.

서버는 선택 필드의 형식·허용 출처·시각 ID 참조를 검증하고 기존 순서·운행 범위·당일 분 범위 검증을 그대로 수행한다. 기존 일정 보존 검사도 새 선택 필드를 인식한다. 직원용 문서에는 본인 코스에 포함된 시각·출처만 기존 확정 트랜잭션으로 반영한다. Rules, 사용자 role/active/staffId, 결근 저장 API와 개인정보 읽기 경계를 완화하지 않는다.

출처는 수동 보호를 위한 편집 메타데이터이며 권한 증명이 아니다. 직원·미인증 변경 요청과 클라이언트 직접 쓰기는 여전히 거부한다. 관리자 확정의 일정 버전·결근 버전·중복 요청 영수증을 유지한다. 구버전 클라이언트가 출처를 생략해 재확정하면 해당 시각은 이후 다시 수동으로 보호된다.

## 구현 경계

| 파일 | 변경 |
|---|---|
| `lib/services/visit_time_calculator.dart` | UI와 분리한 계산기 인터페이스/고정 간격 계산, 보호 적용·미리보기·경고 |
| `lib/widgets/bulk_visit_time_dialog.dart` | 입력, 기존/계산/적용 값 비교, 수동 변경 별도 확인 |
| `lib/screens/admin_schedule_view.dart` | 코스별 진입점과 모달 종료 시 최신 일정·카탈로그·결근 상태 검사 |
| `lib/services/schedule_controller.dart` | 캡처한 초안 동일성·권한 검사 후 한 번에 반영, 수동 출처/삭제 처리 |
| `lib/models/transport.dart`, `schedule_codec.dart` | 불변 출처 Map과 선택적 직렬화·기존 문서 읽기 |
| `lib/models/schedule_changes.dart` | 출처만 변경되는 경우의 변경 요약 |
| `functions/validation.js`, `existing-schedule.js` | 선택 출처 형식 검증과 기존 확정본 호환 |
| `test/visit_time_calculator_test.dart`, `test/bulk_visit_time_test.dart` | 계산·보호·확인·충돌·경계·작은 화면·초안 적용 테스트 |
| `functions/test/staff-absence.test.cjs` | 서버 저장/직원 조회·기존 문서·거부 시 원자성 통합 검사 |
| `tools/operations_browser.cjs` | 옵션으로 실행하는 실제 Chrome+Emulator B-1 흐름 |

추후 이동 시간 기반 계산기는 계산기 경계를 재사용할 수 있다. 외부 API/비동기 이동 시간 공급, 새 출처 값과 서버 검증, 해당 방식의 화면 설명은 후속 단계에서 함께 설계한다. 이번에 지도 API나 자동 일정 확정을 연결하지 않는다.

## 로컬 검증 절차

```powershell
flutter analyze
flutter test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/test-emulators.ps1
```

실제 Chrome 검증에는 새 demo Emulator 세션을 `tools/start_operations_emulators.ps1`로 실행하고 다음을 사용한다. 기존 20명/80명 가상 fixture와 계정 준비 도구를 재사용한다. 소스에 계정 비밀번호를 넣지 않으며 생성 파일은 Git에서 제외된다.

```powershell
flutter build web --debug --dart-define=USE_FIREBASE_EMULATORS=true
$env:GCLOUD_PROJECT = 'demo-senior-transport'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
$env:OPERATIONS_RUN_LABEL = 'bulk-times-b1'
$env:OPERATIONS_CHECK_BULK_TIMES = 'true'
node tools/operations_browser.cjs
```

최종 Flutter 분석은 No issues found, Flutter 테스트 142개와 Emulator 테스트 51개가 모두 통과했다. 0/음수 간격, 23:59·자정 경계, 빈 코스, 출처 없는 수동 보호, 별도 확인, 시각·범위 충돌, 오래된 미리보기, 다른 날짜·시간대, 작은 화면과 기존 A-1/A-2·인증·직원별 읽기를 검증한다. 서버 테스트는 20명/80명 및 기존 40명/79명 가상 데이터, 잘못된 출처/시간 거부 시 원자적 보존을 포함한다. Emulator 전용 debug Web 빌드도 성공했다.

실제 Chrome+Emulator 검증은 `COMPLETE`로 종료했다. 직원 20명·이용자 80명 환경에서 기존 출처 없는 수동 시각 보호 미리보기, 취소 시 서버 무변경, 수동 변경 거부/별도 확인, 적용 후 서버 무변경, 전체 변경 요약/확정 v1→v2, 출처 Map 저장, 오후 일정 보존, 직원 실제 로그인 후 새 예상 시각 표시를 확인했다. JavaScript 예외 0건, 원격 Firebase 요청 0건이다. 테스트 종료 후 로컬 Emulator를 종료했다.

결과는 `.local-tools/bulk-times-b1/report.json`, 화면은 같은 디렉터리의 `b1-*.png`, Flutter/Emulator 로그는 `.local-tools/b1-flutter-tests.log`, `.local-tools/b1-emulator-tests.log`다. 모든 비밀번호·로그·검증 데이터는 Git 제외 로컬 디렉터리에만 두고 실제 Firebase에는 쓰지 않는다.

## 향후 운영 반영 시 주의

이번에는 실제 배포하지 않는다. 현재 운영 중인 A-1/A-2 confirmSchedule은 새 route 필드를 허용하지 않으므로 B-1 클라이언트를 먼저 게시하면 invalid-argument가 발생할 수 있다. 향후 승인된 배포에서는 **B-1 필드 검증과 기존 일정 보존 검사를 포함한 confirmSchedule을 먼저 갱신한 뒤** 실제 Firebase용 release/Hosting 산출물을 새로 만들어 검증한다. setStaffAbsence나 Rules 변경은 B-1 때문에 필요하지 않다.

이번 debug Emulator 빌드는 운영용 Hosting 검증 기록과 다르므로 그대로 배포하면 사전 검사가 차단한다. Hosting용 빌드는 기존 `tools/build-hosting.ps1`로 별도 준비해야 한다. 운영 데이터·계정 마이그레이션이나 초기 데이터 재등록은 수행하지 않는다.
