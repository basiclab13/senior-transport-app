# 최신 Flutter Web 호환 배포 준비

대상: `senior-transport-app`. 로컬 수정일: 2026-11-14.

## 구현 범위

- `functions/index.js`: 운영에서는 기존 이름·리전·인스턴스 설정의 `confirmSchedule`, `setStaffAbsence`만 export한다. `FUNCTIONS_EMULATOR === 'true'` **및** `GCLOUD_PROJECT === 'demo-senior-transport'`일 때만 AI 모듈을 로드한다. 운영 함수 검색 시 AI 코드·Gemini 파라미터·Secret 선언을 로드하지 않는다.
- `functions/emulator-ai.js`: 기존 AI Callable 구현과 Secret·모델 선언을 이동했다. Gemini 모델, 제한 시간, 프롬프트, 서버 검증·loopback 검사·관리자 승인 흐름은 변경하지 않았다.
- `tools/verify-functions-build.cjs`: 설치된 Firebase Functions SDK의 `loadStack`으로 별도 프로세스에서 운영 manifest를 생성·검증한다. 환경 파일을 읽거나 Callable을 실행하지 않는다. 실제 Firebase 요청은 없다. 두 함수의 이름·리전·v2·인스턴스 수·Secret 연결 부재와 파라미터 0개, AI 모듈 미로드를 검사한다. 잘못된 Emulator 셸은 거절한다. SDK 내부 loader 경로를 사용하므로 SDK 업그레이드 시 이 검사를 다시 확인한다.
- `firebase.json`: Functions predeploy에 위 로컬 검사를 연결했다. Hosting 설정·프로젝트 식별자·Rules 경로는 유지한다.
- `functions/test/function-entry.test.cjs`: 운영/Emulator manifest와 Secret 분리 및 잘못된 프로젝트 조합을 검증한다.
- `functions/test/emulator.test.cjs`: 실제 Emulator Callable HTTP 경로로 기존 출처 없는 일정 → 수동/고정 간격 혼합 출처 저장 → 직원 본인 조회 → 동일 요청 재시도 → 잘못된 출처 원자적 거절을 추가 검증한다.

Firestore Rules, Storage Rules, 계정·권한, 스키마 및 Flutter 제품 코드는 이번 작업에서 바꾸지 않았다. 기존 미커밋 UI 변경도 보존했다.

## 방문 시각과 기존 데이터 호환성

현재 로컬 `validation.js`는 선택 필드 `estimatedVisitSources`에 `manual`, `fixedInterval`만 허용하고, 방문 시각에 없는 이용자 참조·잘못된 타입을 거절한다. `existing-schedule.js`는 기존 출처 없는 schemaVersion 1 일정과 새 출처 맵을 모두 수용한다. `schedule-service.js`는 검증한 routes를 관리자 확정 문서와 해당 직원의 조회 문서에 함께 저장한다. 이 코드는 이미 구현되어 있어 이번에는 완화하거나 다시 작성하지 않았다.

출처 없는 기존 시각은 클라이언트에서 직접 입력한 시각으로 보호한다. 결근 버전·일정 버전·요청 ID·권한 검증과 이전 직원 조회 문서 삭제/새 직원 문서 생성 트랜잭션을 유지한다. `users/{uid}`의 active/role/staffId, catalog ID, settings 포인터, 날짜별 확정 일정을 변경하거나 변환할 필요가 없다.

AI·사진은 계속 Emulator 전용이다. 실제 프로젝트에 이를 개방하거나 Secret Manager·Storage 서비스를 활성화하는 배포가 아니다. 사진 저장은 기존 Firestore Blob 방식과 기존 Rules를 사용한다.

## 배포 절차 — 아직 실행하지 않음

Node.js 22, Flutter, Firebase CLI가 PATH에 있는 **새 PowerShell**에서 저장소 루트를 기준으로 실행한다. Emulator 실행 중인 프로세스에서 배포하지 않는다. `GCLOUD_PROJECT`를 설정했다면 대상과 일치해야 하며 `FUNCTIONS_EMULATOR`, `FIRESTORE_EMULATOR_HOST`, `FIREBASE_AUTH_EMULATOR_HOST`, `FIREBASE_EMULATOR_HUB`는 없어야 한다. 이 검사에 실패하면 우회하지 말고 새 셸에서 실행한다.

### 1. 변경 기록·배포 대상 확인

현재 수정 사항을 검토하고 배포할 commit/파일 묶음을 기록한다. Console에서 현재 Hosting release·함수 revision·Rules 게시본을 기록한다. 관리자들은 편집 중인 작업을 마무리하고 배포가 끝날 때까지 일정 편집을 멈춘다. 기존 계정·catalog·일정 초기화 도구를 실행하지 않는다. 기존 결제 연결·예산 및 사용량은 운영자가 확인한다.

```powershell
firebase.cmd functions:list --project senior-transport-app
node tools/verify-functions-build.cjs
```

예상 검사 결과: `VERIFIED`, endpoints `confirmSchedule`, `setStaffAbsence`, parameters 0, secretBindings 0, aiModuleLoaded false, remoteRequests 0. `suggestSchedule`은 운영 배포 대상이 아니다.

### 2. 로컬 회귀 검사

```powershell
flutter analyze
flutter test
node --test functions/test/function-entry.test.cjs
```

Auth/Firestore/Functions 회귀는 `tools/test-emulators.ps1`로 수행한다. 기본 포트의 시연 Emulator가 실행 중이면 중복 실행하지 않고 별도 demo 설정/포트를 사용한다. 이 작업에서는 9198/8190/5102와 hub 4412/logging 4512로 격리했고, 기존 snapshot을 import·삭제하지 않았다. 실제 프로젝트로 fixture 도구를 실행하지 않는다.

### 3. 서버 먼저 갱신

```powershell
firebase.cmd deploy --only "functions:confirmSchedule,functions:setStaffAbsence" --project senior-transport-app
firebase.cmd functions:list --project senior-transport-app
```

두 함수 모두 ACTIVE / Node.js 22 / `asia-northeast3`인지 확인한다. 현재 코드에서는 Gemini Secret 입력이 필요하지 않다. 원치 않는 Secret 생성·서비스 활성화·다른 함수 삭제 요청이 나오면 중단하고 설정을 확인한다. 일반 `firebase deploy` 또는 `--only functions`를 사용하지 않는다. 함수 배포 자체의 기존 Cloud Build/Artifact Registry/Run 사용 비용은 별도 발생할 수 있다.

이번 UI·일정 관리 반영에는 Firestore Rules 재배포가 필수가 아니다. 직전 원격 점검에서 A-1 조회 규칙은 이미 있었으며, 로컬과의 차이는 Emulator 사진 규칙뿐이었다. 원격 규칙이 그 이후 바뀌었다면 다시 비교한다. Storage 배포는 하지 않는다.

### 4. 실제 Firebase용 Web release를 만들고 Hosting을 마지막에 갱신

```powershell
powershell.exe -ExecutionPolicy Bypass -File tools/build-hosting.ps1
node tools/verify-hosting-build.cjs
firebase.cmd deploy --only hosting --project senior-transport-app
```

빌드 옵션은 `--release --dart-define=USE_FIREBASE_EMULATORS=false --base-href /`이다. predeploy가 별도로 동일 산출물을 검증한다. 테스트/debug 빌드로 덮어쓴 뒤 배포하지 말고 다시 빌드한다. 실제 Firebase 설정의 공개 Web 식별자를 서버 비밀 키와 혼동하지 않는다.

### 5. 관리자·직원 확인

- 새 브라우저 세션에서 기존 관리자/직원 가상 계정 로그인과 새로고침·직접 URL 접속을 확인한다.
- 관리자는 송영 현황·날짜/오전·오후·검색·간소화한 상세 화면을 확인한다.
- 운영자가 선택한 가상 테스트 날짜에서 직접 입력 시각 보호, 계산 비교·적용, 전체 확정, 직원의 최신 시각 조회를 확인한다.
- 결근 등록·취소, 결근 직원 잔존 확정 차단, 전체 코스 인계 후 새 직원 조회와 다른 날짜/시간대 보존을 확인한다.
- 두 관리자의 오래된 일정·결근 버전 충돌을 확인한다. 통신 재시도에서 중복 확정되지 않아야 한다.
- 직원의 다른 직원 일정·사진 및 관리자 데이터 접근 거부를 유지한다. 로그아웃 이후 접근도 확인한다.
- 실제 환경의 AI·사진 기능은 계속 비활성인 것이 정상이다. Emulator 시연과 구분한다.

## 복구와 버전 주의사항

서버를 먼저 갱신하면 출처가 없는 기존 클라이언트 요청과 기존 일정도 계속 수용한다. 그러나 오래된 탭은 출처 맵을 전달하지 않을 수 있으므로 편집 전 브라우저를 새로고침한다. 새 클라이언트와 이전 서버의 조합은 출처 필드로 확정이 거절될 수 있으므로 Hosting부터 배포하지 않는다.

새 출처 맵이 저장된 뒤에는 B-1 이전 `confirmSchedule`로 되돌리면 안 된다. 이전 서버는 새 일정을 추가 필드가 있는 호환 불가 문서로 판단할 수 있다. 호환 수정본 소스를 기록해 두고 필요한 경우 이 버전을 재배포하거나 출처 지원을 유지한 수정본으로 복구한다. 출처 필드를 지우거나 기존 일정을 삭제해 우회하지 않는다.

UI 문제는 기존 호환 서버를 유지한 채 Hosting release history에서 이전 UI로 되돌리는 방안을 우선 검토한다. 구형 UI로 돌아간 경우에는 편집을 중지하고 검증된 최신 UI를 복구한다. A-1 이전 Rules로 되돌리거나 권한을 완화하지 않는다. 서비스 장애 중에는 관리자 편집을 멈추고 안전한 오류 유형·함수 revision을 확인한다.

이전 담당 직원의 결근/인계 완료 표시 한계는 `known-issues.md`의 후속 과제로 남아 있다. 문서 부재를 인계 완료로 추정하지 않는다.

## 이번 검증 결과

- `flutter analyze`: 문제 없음.
- Flutter 전체 테스트: **229개 통과**.
- Auth/Firestore/Functions Emulator 회귀: **114개 통과**(기존 110개 + 진입점 검색 3개 + Callable 출처 호환 1개). 20명/80명과 기존 40명/79명 가상 fixture, 결근·인계·동시 변경·권한·AI 고정 응답·사진 규칙 검증을 포함한다.
- 운영 Functions 사전 검사: **VERIFIED**. Node.js 22, v2, `asia-northeast3`, 두 함수만 노출, 파라미터 0, Secret 연결 0, AI 모듈 미로드. Firebase 원격 요청 0.
- 실제 Firebase용 Flutter Web release 빌드 성공. Hosting 사전 검사 통과: release / 실제 프로젝트 / 38개 파일 / 비밀정보·Emulator 번들 혼입 검사. fingerprint `b2626f97b776603ffc806cdeb3c2c3845068c0984af277246759657336e4e8ac`.
- Hosting 안전 검사 테스트 **5개 통과**, 로컬 Hosting HTTP 검사 **10건 통과**. 루트·직접 URL·SPA fallback·실제 JS 파일 일치·캐시 헤더를 확인했다. 애플리케이션 JavaScript는 실행하지 않아 실제 Firebase 요청은 없다.
- `git diff --check` 통과.

첫 Emulator 실행은 테스트 클라이언트가 기본 5001 포트를 사용하여 격리된 사용자 문서를 찾지 못했다. `FUNCTIONS_EMULATOR_HOST=127.0.0.1:5102`를 명시해 해결했다. 추가 테스트의 브라우저 SDK/Admin SDK Timestamp 객체 비교도 동일 SDK 기준으로 수정했고, 최종 전체 회귀는 실패 없이 통과했다. 이 과정에서 권한 규칙·업무 검증을 완화하지 않았다.

로그: `.local-tools/compatibility-analyze.log`, `compatibility-flutter.log`, `compatibility-emulator-passed.log`, `compatibility-release.log`, `compatibility-hosting.log`. 임시 Emulator 설정은 검사 후 제거했다. 기존 시연 Emulator와 snapshot은 삭제하지 않았다.

실제 Firebase 배포·운영 데이터 변경·유료 서비스 활성화 및 실제 Gemini API 호출은 수행하지 않았다. 따라서 실제 서버는 이전 점검 때의 배포 상태이며, 실제 계정별 staffId 연결과 배포 후 쓰기 테스트는 운영자가 위 절차에서 확인해야 한다.
