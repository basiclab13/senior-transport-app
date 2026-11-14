# 25명·80명 AI 검증 catalog

2026-11-14. 새 버전: **`ai-test-25x80-v1`**. 기존 `deploy-test-v2`, 20명/80명 운영 fixture, 40명/79명 부하 fixture와 분리했다. 이번에는 로컬 코드·파일·격리된 Emulator만 사용했다. 실제 Firebase 조회/등록·포인터/AI 설정 변경·외부 Gemini 호출·배포는 하지 않았다.

후속 로컬 구현으로 같은 등록기에 실제 프로젝트의 dry-run·명시적 승인 apply·읽기 전용 `--verify`를 추가했다. 실제 Firebase에서는 아직 실행하지 않았다. 현재 운영자 실행·복구 절차는 [실제 등록 준비](ai25-production-registration.md)를 따른다. 아래 데이터·시나리오 검증은 최초 fixture 준비 기록이다.

등록 이후 운영 포인터 변경 없이 조회·편집할 수 있는 [catalog 미리보기 테스트 모드](catalog-preview-test-mode.md)를 로컬에 추가했다. AI 요청은 별도 opt-in이며 저장·실제 결근 등록·확정을 제공하지 않는다. 서버의 새 테스트 문맥은 추가 배포 전까지 실제 환경에서 사용할 수 없다.

## 데이터와 표시

| 항목 | 구성 |
|---|---|
| 직원 | 25명, `s1`~`s20` 코스 담당, `s21`~`s25` 예비 |
| 차량 | 20대, `v1`~`v20`, 각각 이용자 정원 4명(운전자 제외) |
| 이용자 | 80명, `p1`~`p80` |
| 코스 | 오전 20개 + 오후 20개, 각각 4명 |
| 시간대 재사용 | 같은 직원·차량을 오전/오후에 재사용. 같은 시간대에는 중복 없음 |
| 자식 문서 | staff 25 + vehicles 20 + passengers 80 + baseRoutes 40 = **165개** |
| 부모 문서 | metadata 1개. 전체 등록 166개 문서 |

직원 이름 25개와 이용자 이름 80개는 합쳐서도 중복이 없다. 개별 이름에는 '가상'을 붙이지 않는다. 예: 김다정·문예준·노채원, 김영숙·이정호·임종수. 차량은 `1호차`~`20호차`, 코스는 `오전 1코스`~`오후 20코스`로 구분한다. 모든 이름은 기존 시연용 이름/성·이름 조합으로 구성했으며 실존 인물 자료나 외부 개인정보를 사용하지 않았다. 흔한 이름이 실제 사람과 우연히 같을 수 있다는 점은 가상 데이터의 출처와 별개다.

주소는 '햇살연습마을 느티길 …'처럼 만들어 낸 방문 위치다. 좌표는 중심 `(0,0)`의 km 단위 가상 평면값이며 위도·경도나 주소 변환 결과가 아니다. 기본 코스별 네 지점을 같은 방향으로 배치해 정상 일정에서는 방문 순서나 이용자를 억지로 바꿀 이유가 없게 했다.

현재 앱은 알려진 새 fixture 버전을 명시적으로 식별해 관리자·직원 화면 상단에 **테스트 데이터**를 표시한다. 따라서 향후 실제 연결로 이 버전을 읽더라도 개별 이름에 접두사를 넣을 필요가 없다. 직원별 확정 조회 문서에서도 catalogVersion으로 같은 표시가 된다. 기존 catalog의 이름·표시 규칙과 기존 Emulator 이름 alias는 바꾸지 않았다. 이 표시는 보안 승인을 대신하지 않는다.

## 파일

- `docs/fixtures/ai-test-25x80-v1.baseline.json`: 등록할 전체 데이터와 metadata.
- `tools/ai25_fixture.cjs`: 결정적인 생성기, manifest 검증, 시나리오 생성. 이름·개수·참조·정원 및 기존 서버 검증을 재사용한다.
- `docs/fixtures/ai-test-25x80-v1-scenarios/*.json`: 7개 시나리오의 입력·고정 추천안·결근 직원 목록.
- `tools/ai25_registration.cjs`, `tools/register-ai25-catalog.cjs`: 새 버전 전용 create-only Emulator 등록기.
- `functions/test/ai25-fixture.test.cjs`: 데이터·CLI·트랜잭션·시나리오·직원 조회·운영 비식별 경로 검증.
- `lib/models/schedule_catalog.dart`, `lib/screens/schedule_screen.dart`: 새 fixture의 상단 테스트 표시만 추가.
- `test/ai25_catalog_test.dart`: manifest 파싱, 기존 alias와의 분리, 390px/1280px 화면 검증.

metadata는 `schemaVersion:1`, `ready:true`, `fictional:true`, `testData:true` 및 `fixture` 정보를 갖는다. `fixture`에는 명시적 담당/예비 직원 ID 목록, 개수, 버전, `procedural-fiction-only` 출처, 가상 좌표 방식과 자식 데이터 `contentSha256`이 있다. 등록 시 부모에는 전체 manifest의 `manifestSha256`도 넣는다. 부모에 직원/이용자 데이터를 배열 필드로 넣는 방식이 아니라 네 하위 컬렉션 문서로 등록한다.

최종 manifest SHA-256:

```text
1d9288075fc24a9f6c806f88eaa941b3bc535cc92a43de0c07c132e9034be38c
```

## 시나리오와 결과

정적 JSON은 재현용 초기 입력이다. 고정 requestId/버전 값을 실제 운영 Callable에 그대로 보내면 안 된다. 실제 앱은 최신 일정·결근 버전과 새 요청 ID를 생성한다. 등록 도구는 시나리오의 일일 일정·결근 문서·계정·승인 설정을 자동 생성하지 않는다.

| 시나리오 | 준비한 상황 | Emulator 검증 결과 |
|---|---|---|
| `unchanged` | 정상 20개 코스에 4명씩 | 변경 없는 추천이 유효. 휴리스틱도 변경을 만들지 않음 |
| `passenger-absence` | p2 결석, 79명·빈자리 1개 | 결석자를 제외한 기존 코스 유지도 유효. 결석만으로 불필요한 이동을 강제하지 않음 |
| `order-improvement` | 한 코스의 수동 시각은 현재 순서에 맞지만 순서에 우회가 있음 | 코스 구성 유지·순서만 개선. 가상 왕복 직선거리 **234→232km**, 기존 수동 시각 충돌 경고 후 재검토·확정 |
| `absence-capacity-improvement` | 두 코스가 교차 배정된 변경 중 일정에 p2 결석으로 빈자리 발생 | 한 명을 빈자리로 이동. **272→252km**, 정원 4명·거리 이득/업무량 정책 통과, 시각 재검토 후 확정 |
| `staff-absence` | s1 오전 결근 | s21이 기존 차량·4명·방문 순서를 그대로 인계. 새 직원 조회·이전 직원 조회 문서 정리 검증 |
| `five-staff-absent` | s1~s5 오전 결근 | s21~s25로 5코스 인계, 같은 시간대 중복 없음 |
| `six-staff-absent` | s1~s6 오전 결근 | 가용 직원은 19명으로 20코스 담당 불가. 추천/확정 차단, 기존 일정 보존 |

거리값은 모든 코스가 가상 중심에서 출발해 복귀하는 직선거리 합이다. 실제 도로 거리·운행 시간 절감·최적해를 의미하지 않는다. 특히 272→252km 사례는 의도적으로 교차 배정한 **현재 변경 중 일정**과 비교한 값이며 정상 기본 일정 대비 개선이라고 주장하지 않는다. 실제 Gemini가 같은 안을 제안하거나 유효한 결과를 내는지는 검증하지 않았다. 고정 응답으로 업무 규칙과 적용 흐름을 검증한 것이다.

정상 일정은 `20대 × 4명 = 80명`으로 빈자리가 없다. 한 명을 다른 코스로 단순 이동하면 정원 초과이므로 서버가 거절한다. 같은 시간대 직원 1코스 제약도 유지한다. 차량 변경이나 예비 직원의 다중 코스 담당으로 규칙을 우회하지 않는다.

개선 사례에서는 기존 시각·출처를 보호한 추천안을 먼저 검증하고 B-2 경고를 확인했다. 이어 테스트에서 명시적 시간 검토·적용에 해당하는 값을 구성해 기존 confirmSchedule로 확정했다. 반대 시간대의 기존 확정 문서가 변하지 않는 것도 확인했다. 테스트의 가상 직원 context는 자기 조회 문서만 읽을 수 있고 다른 직원 조회는 거절된다.

## 개인정보 정책과 좌표

새 catalog는 모든 이용자 문서에 명시적인 `fictionalLocation: {xKm, yKm}`를 갖는다. 기존 서버의 좌표 오버레이 대상인 `operations-20x80-v1`와 달리, 이 버전의 좌표는 추측하지 않고 데이터에서 읽는다.

운영 비식별 경로의 모의 테스트에서도 코스 20개·이용자 80명·직원 25명과 가상 위치가 정상 처리됐다. 외부 전달용 데이터에는 임시 ID만 있고 원래 문서 ID·이름·주소는 없음을 검사했다. 실제 API는 호출하지 않았다.

운영 설정의 `allowFictionalLocations`는 기본 false를 유지한다. 나중에 별도 승인된 테스트에서 가상 좌표 출처를 검토한 경우에만 true를 사용할 수 있다. 승인 UID와 catalog 버전도 서버 allowlist에 필요하다. `allowedCatalogVersions`는 문자열이 아닌 **문자열 배열**이어야 한다. 이번에는 운영 제어 문서를 읽거나 수정하지 않았다.

## 등록 도구와 실행 방법

기존 `register-initial-catalog.cjs`/`initial-catalog-registration.cjs`는 deploy-test-v2의 15개 문서만 허용한다. 그대로 재사용할 수 없으며, 그 제한을 완화하지 않았다. 기존 `fictional_catalog.registerCatalog`는 settings 포인터까지 쓰므로 이번 목적에 직접 사용하지 않았다. 기존 데이터 계약·서버 검증·create-only/충돌 검사의 원칙을 재사용한 별도 등록기다.

현재 도구는 demo loopback 경로와 명시적 `senior-transport-app` 경로를 구분한다. 아래는 기존 Emulator 사용법이다. 실제 경로는 ADC/IAM·프로젝트 재확인·별도 catalog 승인이 필요하며, Gemini Secret은 사용하지 않는다. [실제 등록 준비](ai25-production-registration.md)에 정확한 명령을 정리했다.

먼저 네트워크 접속이 없는 계획만 확인한다. Node.js 22와 기존 functions 의존성이 필요하다.

```powershell
node tools/register-ai25-catalog.cjs
# 같은 결과를 명시적으로 요청
node tools/register-ai25-catalog.cjs --plan
```

이미 실행 중인 demo Firestore Emulator를 사용할 때는 해당 포트와 프로젝트를 명시한다. 다음 8080은 기존 기본 설정의 예시다. 실제 사용하는 로컬 포트가 다르면 그 포트로 지정한다. 기존 Emulator를 초기화·삭제·import하거나 다른 프로세스를 종료할 필요는 없다.

```powershell
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:GCLOUD_PROJECT = 'demo-senior-transport'
node tools/register-ai25-catalog.cjs --project demo-senior-transport --dry-run
```

`DRY_RUN_OK`를 확인한 뒤 **로컬 새 catalog 등록**을 명시적으로 실행할 때만:

```powershell
node tools/register-ai25-catalog.cjs --project demo-senior-transport --apply --confirm-project demo-senior-transport
```

165개 자식과 부모 1개를 단일 트랜잭션에서 create한다. 모든 읽기는 쓰기보다 먼저이며, 사전 검증된 모든 자식과 ready 부모가 원자적으로 공개된다. 커밋 후 전체 문서·metadata를 다시 대조한다. settings·users·일일 일정·결근·AI 설정에는 쓰지 않는다.

성공 결과는 `APPLIED`, `createdChildDocuments:165`, `createdMetadataDocuments:1`, `verified:true`, `settingsWrites:0`, `accountWrites:0`, `scheduleWrites:0`다. Emulator에서 정확히 일치하는 기존 데이터는 `ALREADY_REGISTERED`이며 쓰지 않는다. 하나라도 다르거나 부모 없이 자식만 남아 있으면 `BLOCKED_EXISTING_DATA`로 멈춘다. 실제 Firebase는 일치 여부와 관계없이 기존 데이터가 있으면 `BLOCKED_EXISTING_CATALOG`로 중단하며 `--verify`로만 확인한다. 자동 수리·삭제·덮어쓰기는 하지 않는다. manifest가 생성 기준과 달라도 접속 전에 거절한다. 이름이나 좌표를 수정하려면 새 fixture 버전을 별도로 검토해야 한다.

등록만으로 앱의 기본 catalog는 전환되지 않는다. 이번 UI 점검은 manifest를 직접 주입한 Flutter 테스트로 수행했다. 서버 시나리오는 새 demo namespace의 초기 데이터만 사용했다. 기존 포인터 변경 없이 운영 앱에 후보 catalog 선택 기능이 생겼다고 가정하지 않는다.

## 향후 실제 Firebase 적용 전 필요한 승인

1. manifest/hash/가상 좌표와 이름, 계정 staffId 연결을 검토한다. s1~s25는 새 버전의 직원 ID이며 기존 users 문서를 자동 변경하지 않는다. 예비 직원의 실제 로그인 계정은 이번에 생성하지 않았다.
2. 후속 로컬 작업에서 운영자 ADC/IAM과 명시적 프로젝트·catalog 승인을 사용하는 새 버전 전용 운영 dry-run/apply/verify를 구현했다. 실제 실행은 [실제 등록 준비](ai25-production-registration.md)의 순서로 운영자가 결정한다. 기존 초기 등록기의 버전·개수 검사를 제거하지 않는다.
3. 미래 등록도 대상 catalog 경로만 create하고 기존 데이터·포인터·승인 설정은 보존해야 한다. 동일 버전이 있으면 checksum/문서 충돌을 확인하고 중단한다.
4. 실제 AI 요청에는 별도 제약이 있다. 현재 서버는 요청 catalogVersion이 선택한 확정 일정의 고정 버전 또는 기본 settings 포인터와 일치해야 한다. **새 catalog를 등록하고 allowlist에 넣는 것만으로 실호출할 수 없다.** 기존 포인터나 확정 문서를 건드리지 않는 별도 테스트 환경/전환 절차를 먼저 승인해야 한다. 이 검사를 우회하지 않는다.
5. 그 이후에만 승인된 관리자·가상 catalog·작은 호출 한도로 별도의 실호출 검증을 진행한다. 이번 작업에서는 운영 설정, 키, 모델, 호출 기록을 변경하지 않았다.

## 검증 결과

- `flutter analyze`: 문제 없음.
- Flutter 전체 **233개 통과**. 최종 fixture 이름으로 390px/1280px 새 UI 테스트 **3개 재확인**.
- Auth/Firestore/Functions Emulator 전체 **140개 통과**. 새 fixture·생성 재현성·원자적 등록/동시 재실행·CLI dry-run/apply/반복·기존 데이터 보존·7개 일정 시나리오·운영 비식별 경로와 기존 AI/사진 회귀를 포함한다.
- 외부 Gemini 요청 **0회**. 실제 Firebase 읽기/쓰기·배포 **0회**.
- 등록기 offline plan: 자식 165개 + 부모 1개, 포인터 쓰기 0.
- `git diff --check` 통과.

검증은 별도 Emulator 포트 9198/8190/5102, hub 4412/logging 4512 및 새 demo namespace에서 수행했다. 기존 시연 Emulator·snapshot은 보존했다. 재현용 테스트는 namespace 안에 최초 settings/users 문서를 만들지만 기존 설정·계정·일정 문서를 바꾸지 않는다. 임시 Emulator 설정은 검사 후 제거했다.

로그: `.local-tools/ai25-analyze.log`, `ai25-flutter.log`, `ai25-ui-final.log`, `ai25-emulator-verified.log`. 시작 전부터 있던 미커밋 변경과 환경 파일은 보존했다.
