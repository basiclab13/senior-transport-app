# suggestSchedule 미리보기 지원 배포 전 최종 점검

2026-11-14 로컬 소스와 Emulator를 기준으로 점검했다. 실제 Firebase 조회/배포, 설정 변경, Gemini 호출은 하지 않았다. 배포된 함수 리비전·Secret IAM·현재 mode는 이번 점검에서 원격 확인하지 않았다.

## 요청 경계

| 항목 | 일반 운영 AI 요청 | 명시적 미리보기 요청 |
| --- | --- | --- |
| 분기 | previewContext 필드 없음 | previewContext 필드 있음; null·잘못된 값은 거절 |
| catalog | 확정 일정 또는 settings 포인터와 일치 | ai-test-25x80-v1만, expectedVersion 0만 |
| 추가 검증 | 기존 일정·결근 버전 | kind/scenario/manifestSha256 정확한 필드 집합, 고정 manifest 전체 내용 해시, 가상 결근 버전 |
| 읽는 일정 | 선택 날짜 schedules, 실제 staffAvailability, settings/schedules | 모두 읽지 않음; 가상 결근은 고정 metadata와 scenario에서 계산 |
| catalog 읽기 | 승인된 catalog | 고정 부모와 staff/vehicles/passengers/baseRoutes 자식만 |
| 공통 읽기 | users/{로그인 UID}, _aiControl/config, 해당 요청·사용량 기록 | 동일 |
| 쓰기 | _aiRequests 및 _aiUsage 관리 기록만 | 동일; 일정·catalog·결근·계정·settings 쓰기 없음 |

`previewRequest`는 서버 내부 context reader를 선택한다. 클라이언트는 reader나 임의 결근 ID를 주입할 수 없다. previewContext를 제거하면 기존 운영 경로로 돌아가며 catalog/일정 버전/실제 결근 검증을 통과해야 한다. 미리보기 catalog라는 이유로 일반 경로의 포인터 일치 검사를 생략하지 않는다.

고정 manifest 해시: `1d9288075fc24a9f6c806f88eaa941b3bc535cc92a43de0c07c132e9034be38c`. 부모 ready/fictional/testData와 내용 해시를 요청 전·응답 후 검증한다. catalog가 변하면 요청이 실패하며 유사 데이터로 대체하지 않는다.

## 공통 보안·호환성

- 매 요청 active=true, role=admin을 검사한다. 운영 mode는 정확히 test이고 UID와 catalog가 각각 allowlist에 있어야 한다. requireAppCheck=true면 토큰을 요구하고 false/누락이면 토큰 없음만으로 거절하지 않는다.
- 권한은 최초·예약 트랜잭션·응답 완료 시 재검사한다. 원격 조회 실패는 승인으로 간주하지 않는다.
- 프로젝트/관리자 일일 한도, 대기 간격, 프로젝트 동시 실행 잠금, 요청 ID 영구 중복 방지를 그대로 사용한다. 미리보기에도 같은 한도를 적용하며 별도 무료/무제한 경로가 없다. 실패한 외부 호출도 사용량을 환급하지 않는다.
- Gemini 입력은 허용 필드로 새로 구성한다. 원래 문서 ID를 요청별 임시 ID로 치환하고 이름·주소·UID·previewContext·해시는 전송하지 않는다. 가상 평면 좌표는 allowFictionalLocations=true인 경우만 외부로 보낸다.
- 기존 직원 가용성·누락/중복 배정·차량 정원·결근·재배정/거리 평가를 재사용한다. 차량·결석·수동 시각·출처는 AI가 변경하지 않는다. 시각 충돌은 기존 B-2 확인 및 최종 확정 규칙을 따른다.
- 미리보기는 별도 컨트롤러/저장소에서 메모리만 편집한다. 적용 승인 후에도 서버에 일정을 저장하지 않는다. 확정 버튼을 제공하지 않고 컨트롤러와 저장소도 publish/결근 저장을 거절한다. 운영 화면으로 자동 복사하지 않는다.
- confirmSchedule은 previewContext가 포함된 요청을 기존 허용 필드 검증으로 거절한다. 기존 두 함수 코드·Rules·Storage·데이터 스키마는 이번 점검에서 변경하지 않았다. 운영의 정상 관리자 확정 권한 자체를 제거한 것은 아니므로, 관리자가 별도로 작성한 일반 확정 요청까지 금지하는 기능은 아니다.

## 함수 manifest

로컬 `node tools/verify-functions-build.cjs`로 확인:

- Node.js 22, Functions v2, asia-northeast3.
- suggestSchedule: maxInstances=1, minInstances=0, concurrency=1, timeoutSeconds=90.
- GEMINI_API_KEY Secret은 suggestSchedule에만 연결. GEMINI_MODEL 파라미터 유지. 모델/제한 시간 변경 없음.
- confirmSchedule, setStaffAbsence: maxInstances=2, Secret 연결 0, 기존 export 유지.
- manifest 검사는 오프라인 discovery다. Secret 값/접근 권한이나 현재 운영 mode 확인을 의미하지 않는다. 출력의 aiDefaultMode=off는 설정 누락 시 기본 거절이라는 뜻이다.

## 배포 절차 — 운영자가 추후 실행

**배포 자체는 _aiControl/config를 생성하거나 수정하지 않는다. 이미 mode=test이면 배포 후에도 test다.** 이번 작업에서는 이를 변경하지 않았으므로 현재 off라고 단정할 수 없다.

1. Firebase Console에서 대상 프로젝트가 senior-transport-app인지 확인한다. _aiControl/config의 mode를 읽는다. off가 아니라면 운영자가 별도 승인 하에 mode 필드만 off로 바꾼 뒤 진행한다. allowlist·사용량·요청 기록을 삭제/초기화하지 않는다. 예약/실행 중 요청이 없는지 확인한다.
2. 현재 코드 리비전과 직전 정상 suggestSchedule 소스를 보관한다. 기존 Secret 연결, GEMINI_MODEL 설정과 기존 함수 상태를 확인한다. 키를 터미널에 출력하거나 재등록하지 않는다.
3. Emulator 관련 환경 변수가 없는 새 PowerShell에서 저장소 루트를 열고 실행한다. 아래는 안내이며 이번에는 실행하지 않았다.

```powershell
node tools/verify-functions-build.cjs
firebase.cmd functions:list --project senior-transport-app
firebase.cmd deploy --only functions:suggestSchedule --project senior-transport-app
firebase.cmd functions:list --project senior-transport-app
firebase.cmd functions:log --only suggestSchedule --project senior-transport-app
```

4. Console에서 suggestSchedule의 ACTIVE 상태·asia-northeast3·새 리비전·Secret 연결을 확인한다. confirmSchedule/setStaffAbsence가 선택 배포 대상에 없었는지 확인한다. functions:list만으로 소스 동일성이나 Secret IAM을 검증했다고 판단하지 않는다.
5. _aiControl/config.mode가 여전히 off인지 읽기 전용으로 확인한다. 누락이어도 AI는 거절되지만, 명시적 off가 더 쉽게 확인된다. 배포가 mode를 자동으로 껐다고 가정하지 않는다.
6. 아래 AI 요청 비활성 빌드로 미리보기 catalog·인원·AM/PM·7가지 상황·돌아가기 동작을 확인한다. 사진/확정 버튼이 없어야 한다. 기존 운영 화면의 미확정 변경사항은 유지되어야 한다.

```powershell
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=false --dart-define=ENABLE_AI_CATALOG_PREVIEW=true --dart-define=ENABLE_PRODUCTION_AI=false --dart-define=ENABLE_AI_CATALOG_PREVIEW_REQUESTS=false
```

7. mode=off 상태의 서버 거절 검증을 별도 승인해 수행할 경우에만 아래 opt-in 빌드를 사용해 한 번 요청한다. failed-precondition으로 거절되고 호출 단계 로그가 없으며 _aiUsage/_aiRequests가 늘지 않아야 한다. 이번 점검에서는 실제 Callable도 호출하지 않았다.

```powershell
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=false --dart-define=ENABLE_AI_CATALOG_PREVIEW=true --dart-define=ENABLE_PRODUCTION_AI=true --dart-define=ENABLE_AI_CATALOG_PREVIEW_REQUESTS=true
```

8. 실제 Gemini 1회 테스트는 별도 승인 작업이다. mode=test, 승인 관리자 UID, allowedCatalogVersions 배열의 ai-test-25x80-v1, 작은 한도를 검토한 후 진행한다. 프로젝트/관리자 한도를 1로 설정해도 이미 소비한 사용량을 지우지 않는다. 성공/실패 후 자동 재시도하지 않는다. 결과는 관리자 승인 후 메모리에만 적용되는지 확인하고, 종료 후 mode=off로 되돌린다. 실제 일정 확정은 테스트하지 않는다.

이 절차에는 Hosting·confirmSchedule·setStaffAbsence·Rules·Storage 배포, 포인터 변경이 포함되지 않는다. 미리보기 진입은 Flutter 빌드 옵션이 필요하며 함수만 업데이트해 기존 Hosting에 버튼이 생기지는 않는다.

## 장애 대응과 검증 한계

오류가 나면 재호출보다 먼저 mode=off로 중단한다. 안전 로그의 component/stage/code/violation/diagnosticId를 확인하고 원문 응답·개인정보·키는 수집하지 않는다. off 전 이미 전송한 외부 요청의 비용은 취소되지 않는다. 완료 전 재승인 검사에서 거절되어도 요청 관리 기록은 남는다.

필요하면 보관한 직전 정상 소스에서 suggestSchedule만 다시 선택 배포한다. 기존 두 함수/데이터/출처 필드를 되돌리거나 삭제하지 않는다. 구버전은 previewContext를 지원하지 않으므로 미리보기 AI 요청 옵션도 끈다.

실제 배포 리비전·설정·Secret IAM·실제 Gemini 모델 접근·실과금은 로컬 모의 테스트로 확인할 수 없다. 이 문서는 그 항목이 완료되었다는 보고가 아니다.

## 이번 로컬 검증

권한 거절 테스트를 추가했다. off/잘못된 mode/설정 없음/UID 미승인/catalog 미승인/App Check 필수 토큰 없음/비활성 관리자에서 generator 호출과 사용량 증가가 모두 없는지 확인한다. 기존 정상 미리보기 테스트는 App Check 선택 상태의 성공 경로를 검증한다.

운영 manifest 검사 VERIFIED, flutter analyze 문제 없음, Flutter 전체 242개 통과, Emulator 전체 164개 통과(실패/취소 0), git diff --check 통과. Emulator는 파일 단위 직렬 실행으로 기존 동시 요청 테스트도 모두 실행했다. 제품의 모델/시간 제한은 변경하지 않았다.

결과 및 로그는 작업 완료 보고와 `.local-tools/preview-final-review-emulator.log`, `preview-final-review-analyze-verified.log`, `preview-final-review-flutter-verified.log`를 참고한다. 테스트는 demo 프로젝트와 별도 loopback 포트에서 고정 AI 응답만 사용하며 기존 Emulator snapshot을 import/삭제하지 않는다.
