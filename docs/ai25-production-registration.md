# ai-test-25x80-v1 실제 등록 준비

2026-11-14 로컬 구현·테스트 결과. **실제 Firebase에 접속하거나 등록하지 않았다.** 이번에는 기존 도구에 운영 등록 경로와 읽기 전용 검증을 추가했다. 계정·확정 일정·Rules·Functions·AI 설정은 변경하지 않았다.

## 범위와 안전장치

- 실제 대상은 `senior-transport-app`의 `(default)` DB만 허용한다. 다른 실제 프로젝트·DB·catalog 선택 옵션은 없다.
- 생성 가능 경로는 `catalogs/ai-test-25x80-v1`과 고정된 staff/vehicles/passengers/baseRoutes 자식 165개뿐이다. 부모 포함 166개다.
- 기본은 쓰기 없는 dry-run이다. 프로젝트가 없는 기존 기본 실행은 오프라인 계획을 유지한다. 실제 읽기조차 `--project senior-transport-app`을 명시해야 한다.
- 실제 쓰기는 `--apply`, `--confirm-project senior-transport-app`, `--approve-catalog ai-test-25x80-v1`을 모두 요구한다. 라이브러리에서도 승인과 기본 DB를 재검사한다.
- 실제 프로젝트에 Emulator 환경 변수가 있거나 환경의 프로젝트가 다르면 SDK 초기화 전에 거절한다. demo 프로젝트는 반대로 loopback Firestore Emulator를 필수로 요구한다.
- 실제 등록은 부모나 자식 데이터가 하나라도 있으면 `BLOCKED_EXISTING_CATALOG`로 중단한다. 완전히 같은 데이터도 덮어쓰거나 이어 쓰지 않는다. 이미 있는 정상 데이터 확인은 별도 `--verify`로 한다.
- 기존 Emulator의 명시적 적용·동일 데이터 재실행 `ALREADY_REGISTERED` 동작은 유지했다. 실제 경로의 더 엄격한 중단 정책과 구분한다.
- `settings/schedules`, `deploy-test-v2`, `users`, Auth 계정, 날짜별 일정, 결근, `_aiControl`·사용량·요청 기록은 읽거나 쓰지 않는다. 생성 시 set/update/delete를 사용하지 않고 고정 경로의 create만 사용한다.
- credential·토큰·원본 예외·서버 문서 원문을 출력하지 않는다. 비밀 키 파일을 만들거나 Git에 넣지 않는다.

기준 데이터·7개 시나리오와 개인정보 정책은 [25명·80명 fixture 문서](ai25-test-catalog.md), 전체 등록 데이터는 [baseline manifest](fixtures/ai-test-25x80-v1.baseline.json)를 따른다. 데이터 자체는 변경하지 않았다.

## 변경 파일

- `tools/register-ai25-catalog.cjs`: 실제 프로젝트 선택, 승인 옵션, ADC, `--verify`, 안전한 결과/종료 코드.
- `tools/ai25_registration.cjs`: 프로젝트/DB/환경 재검사, 운영 기존 데이터 중단, 등록 전후 서버 검증, 불확실한 결과 분류.
- `tools/ai25_fixture.cjs`: 기존 canonical 해시 함수를 검증기에서도 재사용하도록 export만 추가. fixture 내용·해시는 동일하다.
- `functions/test/ai25-production-registration.test.cjs`: 운영 정책을 Emulator에만 연결해 검증하는 신규 9개 테스트.
- `functions/test/ai25-fixture.test.cjs`: 승인 검사 및 CLI 읽기 전용 검증 회귀.
- 이 문서 및 기존 fixture 문서의 운영 경로 설명 갱신.

## 등록 전후 검증

접속 전에 manifest가 고정 생성 기준과 완전히 일치하는지 검사한다. 직원 25명(담당 20·예비 5), 차량 20대/정원 4명, 이용자 80명, 오전/오후 각각 20코스와 이름·참조·정원·중복을 검증한다.

서버에서는 부모와 네 하위 컬렉션을 읽는다. 예상 외의 직속 하위 컬렉션, 자식 아래의 중첩 컬렉션, 부모가 누락된 하위 문서 참조도 검사한다. parent 문서가 없어도 하위 컬렉션이 하나라도 있으면 실제 등록을 중단한다. 부모/정해진 자식은 같은 읽기 트랜잭션 snapshot에서 검증한다. 컬렉션/문서 참조 열거는 별도 API이므로 운영자는 대상 경로를 다른 도구나 Console에서 동시에 수정하지 않아야 한다. 확인 결과는 검사 시점의 상태이며 이후 관리자 수동 변경까지 방지하는 잠금은 아니다.

새 등록은 모든 읽기 이후 **166개 create를 단일 트랜잭션**으로 커밋한다. ready 부모와 모든 검증된 자식이 동시에 보이며 정상적인 트랜잭션 실패로 일부만 저장되지 않는다. 충돌 시 SDK의 트랜잭션 재실행에서도 기존 문서를 발견하면 중단하므로 덮어쓰지 않는다. 외부 API 호출·포인터 활성화 작업은 트랜잭션에 없다. [Firestore 트랜잭션 안내](https://firebase.google.com/docs/firestore/manage-data/transactions).

커밋 후 다시 읽어 다음을 검사한다.

- 부모 1개, 자식 165개. 컬렉션별 25/20/80/40개.
- metadata 전체 값/타입, ready·fictional·testData 및 fixture 정보.
- 부모에 기록된 해시가 기준과 같은지.
- **서버에서 읽은 자식 내용으로 계산한** content 해시가 기준과 같은지.
- 부모 metadata와 서버 자식으로 다시 계산한 manifest 해시가 기준과 같은지. 부모에 적힌 해시만 믿지 않는다.
- 오전/오후의 직원·차량·이용자 참조, 중복, 근무 가능 여부, 차량 정원에 기존 서버 검증 적용.
- 예상하지 않은 문서/컬렉션·추가 필드·누락이 없는지.

고정 manifest SHA-256:

```text
1d9288075fc24a9f6c806f88eaa941b3bc535cc92a43de0c07c132e9034be38c
```

## 운영자가 향후 직접 실행할 순서

**아래 실제 연결·등록 명령은 이번 작업에서 실행하지 않았다.** 새 PowerShell에서 저장소 루트를 사용한다. Node.js 22와 기존 functions 의존성이 필요하다. 실제 등록 시 별도 IAM/사용량 검토 후 진행한다. `firebase deploy`나 서비스 활성화 명령은 필요하지 않다.

### 1. 오프라인 계획 검토

```powershell
node tools/register-ai25-catalog.cjs --project senior-transport-app --plan
```

`OFFLINE_PLAN`, 프로젝트·기본 DB·고정 버전·자식 165개/부모 1개·위 해시, `firebaseAccess:false`, `writes:false`를 확인한다. 오프라인 계획 통과는 ADC/IAM이나 실제 Firestore 상태 검증 완료가 아니다.

### 2. 운영자 ADC와 환경 준비

기존 유효한 ADC가 있으면 다시 로그인할 필요는 없다. 처음 준비하는 운영자가 직접 실행한다.

```powershell
gcloud auth application-default login
gcloud auth application-default set-quota-project senior-transport-app
```

일반 `firebase login`, 앱 관리자 계정, Gemini API 키는 Admin SDK의 ADC/IAM을 대신하지 않는다. ADC는 사용자 외부 인증 저장소에 두고 저장소 안에 서비스 계정 JSON을 생성하지 않는다. 도구는 `applicationDefault()`를 사용한다. [ADC 공식 안내](https://cloud.google.com/docs/authentication/provide-credentials-adc).

운영자가 조회·컬렉션 나열·트랜잭션·문서 생성에 필요한 IAM을 검토한다. 도구는 IAM을 부여하거나 Rules를 바꾸지 않는다. Admin SDK는 Firestore Security Rules를 우회하므로 앱의 관리자 role만으로 도구 실행 권한을 판단하지 않는다. 실제 읽기/쓰기는 Firebase 사용량이 발생할 수 있다.

셸에 `FIRESTORE_EMULATOR_HOST`, `FIREBASE_AUTH_EMULATOR_HOST`, `FIREBASE_EMULATOR_HUB`, `FUNCTIONS_EMULATOR`, `FUNCTIONS_EMULATOR_HOST`, `FIREBASE_STORAGE_EMULATOR_HOST`가 없어야 한다. `GCLOUD_PROJECT`, `GOOGLE_CLOUD_PROJECT`, JSON `FIREBASE_CONFIG.projectId`가 있으면 명시한 실제 프로젝트와 일치해야 한다. 거절되면 보호를 제거하지 말고 올바른 새 셸에서 실행한다. demo 등록 시에는 기존 loopback 환경을 사용한다.

### 3. 실제 읽기 전용 dry-run

```powershell
node tools/register-ai25-catalog.cjs --project senior-transport-app --dry-run
```

`--dry-run`은 생략해도 같은 동작이다. 신규 대상이 비어 있으면 `DRY_RUN_OK`, `before.parentExists:false`, `before.childDocuments:0`, `before.unexpectedCollections:0`, 생성 문서 수 0이다. 아직 등록하지 않았으므로 이 단계의 `verified:false`/참조 incomplete는 정상이다. 계획의 데이터 참조는 접속 전 이미 검증했다.

이미 무엇이든 있으면 실제 apply를 진행하지 않는다. 아래 읽기 전용 `--verify`로 기존 상태만 확인한다. dry-run 결과가 다르거나 읽기에 실패하면 인증·IAM·충돌을 해결하기 전 쓰지 않는다.

### 4. 명시적으로 승인한 실제 등록

dry-run과 manifest 해시가 검토한 내용과 같고 다른 운영자의 수정이 없는 경우에만 실행한다.

```powershell
node tools/register-ai25-catalog.cjs --project senior-transport-app --apply --confirm-project senior-transport-app --approve-catalog ai-test-25x80-v1
```

정상 결과: `APPLIED`, `createdChildDocuments:165`, `createdMetadataDocuments:1`, `verified:true`. `after.counts`는 staff 25, vehicles 20, passengers 80, baseRoutes 40이며 `after.referenceIntegrity`는 `verified`, metadata·기록된 해시·재계산한 두 해시 비교는 모두 true다. `unexpectedCollections`, `nestedCollections`, `missingParentDocumentReferences`는 모두 0이어야 한다. 문서 수는 정해진 네 직속 컬렉션 기준이며, 지원하지 않는 추가/중첩 구조는 별도 지표로 탐지해 거절한다.

`settingsWrites`, `accountWrites`, `scheduleWrites`, `aiControlWrites`는 모두 0이다. 등록해도 현재 앱의 catalog 선택이나 실제 AI 승인이 자동 전환되지 않는다. 기존 일정의 고정 catalogVersion 및 기본 settings와 요청 버전이 일치해야 하는 서버 검사를 우회하지 않는다.

### 5. 등록 후 별도 읽기 전용 검증

```powershell
node tools/register-ai25-catalog.cjs --project senior-transport-app --verify
```

`VERIFIED`, `verified:true`, 부모 1개·자식 165개, 두 재계산 해시 일치·참조 verified를 확인한다. `createdChildDocuments:0`, `createdMetadataDocuments:0`, `writesMayHaveCommitted:false`여야 한다. 이 명령은 데이터를 수정하거나 준비 상태로 바꾸지 않는다. 현재 존재하는 내용이 기준과 다르면 종료 코드 2로 실패한다.

## 실패·중단·응답 유실 복구

| 결과/상황 | 조치 |
|---|---|
| `READ_FAILED` 또는 연결/ADC 실패 | 오류 원문·토큰을 공유하지 않고 환경/IAM을 점검한다. 확인 전 쓰기 재시도하지 않는다 |
| `BLOCKED_EXISTING_CATALOG` | 같은 데이터여도 실제 등록은 중단. `--verify`만 실행한다 |
| `OUTCOME_UNKNOWN` | 커밋이나 후속 읽기 응답이 불명확하다. 생성 수가 null일 수 있다. **apply를 자동 재실행하지 않고 --verify부터 실행**한다 |
| `--verify`가 `VERIFIED` | 이미 전체 등록된 상태다. 추가 등록하지 않는다 |
| 검증 결과 부모/자식 모두 없음 | 미등록 상태. 새 dry-run과 운영자 판단 후에만 새 명시적 apply를 검토한다 |
| 일부만 존재·unknown 컬렉션·해시/참조 불일치 | 기존 자료를 보존하고 중단. 자동 이어쓰기·수리·삭제하지 않는다. 자료를 검토한 뒤 별도의 새 버전을 준비할지 결정한다 |
| `POST_WRITE_VERIFICATION_FAILED` | 커밋 뒤 다른 수정 등이 감지되었다. 포인터·AI 허용 목록에 사용하지 말고 readonly 검증/운영자 조사를 진행한다. 도구는 자동 rollback이나 ready 변경을 하지 않는다 |

원자적 커밋 때문에 이 도구가 정상적으로 반쪽 catalog를 생성하는 경로는 없다. 이전 수동 입력·다른 도구·외부 동시 수정으로 일부가 남아 있으면 기존 데이터를 존중해 중단한다. 성공 응답이 없어도 서버에는 전체가 등록되었을 수 있으므로 응답 유실 테스트는 반드시 `--verify`로 복구한다.

`writesMayHaveCommitted`는 쓰기를 시도한 경우 보수적으로 true로 표시한다. 최종 성공/실패는 `status`, `verified`, `before/after`를 함께 확인한다. SDK는 트랜잭션 충돌을 내부 재처리할 수 있지만, CLI는 불명확한 결과를 보고 새 등록을 자동 재시도하지 않는다. 도구에는 force·delete·수정·버전 우회·포인터 활성화 옵션이 없다.

## 로컬 검증

- `flutter analyze`: 문제 없음.
- Flutter 전체 **233개 통과**.
- Auth/Firestore/Functions Emulator 전체 **149개 통과**. 기존 140개와 새 운영 등록 정책/복구 테스트 9개.
- 실제 운영 프로젝트용 클라이언트를 만들지 않았다. 운영 분기 테스트는 **demo loopback Firestore에 모든 메서드가 연결된 테스트 전용 어댑터**를 사용했다. 실제 ADC·운영 IAM·네트워크 접근은 검증하지 않았으며 운영자의 첫 dry-run에서 확인해야 한다.
- scope 밖 문서 보존, 잘못된 프로젝트/DB/환경/승인 차단, 동시 등록 1회 생성, 기존 일치 catalog 중단, 부분/unknown 데이터 보존, 해시·참조 손상 탐지, 커밋 전 중단, 커밋 후 응답 유실, 후속 검증 실패를 확인했다.
- CLI Emulator dry-run/apply/재실행과 읽기 전용 `--verify`를 유지했다. 실제 프로젝트 ID를 붙인 **오프라인 --plan만** 실행했고 Firebase 연결은 없었다.
- `git diff --check` 통과. 원래 fixture·기존 미커밋 변경·환경 파일은 보존했다.

실제 Gemini 호출·Secret 등록·서비스 활성화·배포·실제 Firebase 읽기/쓰기는 수행하지 않았다. 별도 포트 9198/8190/5102와 새 demo namespace를 사용했고 기존 시연 데이터·snapshot을 삭제/import하지 않았다. 로그: `.local-tools/ai25-production-registration-verified.log`, `ai25-registration-analyze.log`, `ai25-registration-flutter.log`. 임시 Emulator 설정은 검사 후 제거했다.
