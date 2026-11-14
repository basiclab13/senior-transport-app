# 10명·24명 가상 catalog 확장 및 전환

이 문서는 로컬 구현과 향후 운영자 실행 절차다. 실제 Firebase 등록·계정 생성·포인터/AI/사진 설정 변경·Gemini 호출·배포는 실행하지 않았다. 기존 운영 함수·Rules·AI 미리보기·사진 저장 방식은 변경하지 않는다.

## 구성과 기존 데이터 보존

`docs/fixtures/demo-10x24-v1.baseline.json`은 `tools/demo10_fixture.cjs`의 결정적 생성 결과다. `makePlan`은 파일 전체가 생성 결과와 같은지 검사한다. 직원 10명, 차량 8대(모두 정원 4명), 어르신 24명, 오전 8·오후 8코스(각 3명), 자식 58 + 부모 1 = **59문서**다.

- 담당 `s1`~`s8`, 예비 `s9`·`s10`. metadata.fixture에 두 목록을 명시한다.
- 기존 직원 `s1`~`s3`의 데이터와 기본 휴무일을 보존한다. **s3는 금요일 휴무**이므로 금요일에는 예비 직원에게 인계해야 확정할 수 있다.
- 기존 차량 `v1`~`v3` ID·이름을 보존하되 새 catalog 안에서만 정원을 4명으로 설정한다.
- 어르신 `p1`~`p5` ID·가상 주소·안내사항을 보존하고 이름만 자연스러운 가상 이름으로 바꾼다. `p6`~`p24`를 추가한다.
- 기존 morning/afternoon-a,b ID와 방문 순서를 보존한다. B코스 뒤에 p6을 추가한다. 새 6개 코스에 p7~p24를 배정한다. 오후 A코스의 p3,p1,p2 순서도 그대로다.
- 개인정보·GPS·지오코딩 없이 24명 모두에게 `fictionalLocation: {xKm: number, yKm: number}`를 생성한다. 원점은 거리 평가용 가상 센터이며 실제 주소가 아니다.
- 기본 코스에는 실제로 약속하지 않은 방문 시각을 생성하지 않는다. 현재 [방문 시간 단순화 정책](appointment-time-simplification.md)에 따라 오전 직접 입력 약속 시간은 선택 사항이며 오후는 순서만 표시한다. B-1/B-2는 제거되었고 기존 자동 계산값은 기록으로 보존한다.
- `deploy-test-v2` 및 `ai-test-25x80-v1`은 전혀 수정하지 않는다. 화면의 테스트 데이터 표시에 새 버전을 추가했다.

## 도구의 안전 경계

`tools/register-demo10-catalog.cjs`는 `register`, `switch`, `rollback` 세 작업을 제공한다. 기본은 읽기 전용 dry-run이다. 실제 프로젝트는 `senior-transport-app`만, 로컬은 demo-*와 loopback Firestore만 허용한다. 기존 ai25 도구의 프로젝트/환경 가드와 canonical SHA256, 서버 validateSchedule을 재사용한다. 기존 등록 도구와 manifest는 그대로다.

register는 고정 새 catalog 경로에만 tx.create 59개를 같은 트랜잭션에서 실행한다. 기존 부모·자식·예상 밖 컬렉션·고아 하위 데이터가 있으면 중단한다. 전체 데이터·참조를 검증한 뒤 부모 ready:true와 자식이 원자적으로 커밋된다. 중간 ready 상태는 없다. 완료 후 다시 읽어 metadata·개수·해시·실제 문서 내용을 검증한다. 동일 데이터가 이미 있어도 등록을 반복하지 않고 --verify만 허용한다.

switch/rollback은 settings 전체와 updateTime을 사전 읽기 후 트랜잭션 안에서 재검사한다. 예상 이전 catalog와 다르거나 사전 확인 이후 변경이 있으면 재시도 중에도 중단한다. 대상 부모 ready/fictional·전체 자식 내용·활성 직원 계정 연결을 검사한다. settings의 catalogVersion 한 필드만 tx.update하며 다른 필드는 보존한다. 계정·확정 일정·직원별 일정·결근·사진·AI/사진 제어 설정에는 쓰지 않는다.

대상 컬렉션 열거/예상 밖 하위 경로 검사와 사진 count/기능 설정 조회는 별도의 읽기 API다. 사진 수와 기능 상태는 영향 점검용 스냅샷이며 원자적 시점 보장은 아니다. **등록/전환 중 다른 운영자 도구로 catalog를 편집하지 않는다.** 일반 앱의 catalog 직접 쓰기는 기존 Rules로 금지돼 있다. 트랜잭션은 대상 정상 하위 컬렉션 전체를 다시 읽는다.

dry-run 출력은 활성 직원 계정 수/잘못된 연결 수, 기존 확정 일정의 catalog별 개수, s1~s10의 기존 Blob/Storage 사진 기록 개수, 대상 hash, AI/사진의 대상 허용 여부를 포함한다. 비밀번호·UID·프로필·사진 bytes·Secret은 출력하지 않는다. 사진 보존 기간 정책에 따른 기존 만료/정리는 이 도구가 수행하지 않는다.

## 운영에서 실행하기 전 필수 확인

1. 실제 등록된 deploy-test-v2와 로컬 baseline이 일치하는지 확인한다. 원복은 기존 baseline의 자식 내용과 ready/fictional을 확인하므로 임의 수정된 기존 catalog는 차단된다. 차이가 있으면 먼저 읽기 전용으로 검토하며 덮어쓰지 않는다.
2. 기존 활성 직원 계정의 staffId가 s1~s10 안에 있고 원래 s1~s3 연결이 바뀌지 않았는지 확인한다. **rollback 대상은 s1~s3만 존재**하므로 s4~s10 활성 계정이 있으면 원복은 차단된다. 기존 계정만으로 시작하는 것을 권장한다. 추후 새 계정을 만들었다면 운영자가 원복 전 별도로 해당 계정의 이용 중지 여부를 결정해야 한다. 도구가 자동 중지하지 않는다.
3. 모든 관리자에게 편집 중인 내용을 정리하고 전환 후 새로고침하도록 알린다. 로컬 미확정 변경사항은 서버에 저장되지 않는다.
4. 새 데이터를 시험할 날짜·시간대에 기존 확정 일정이 없는지 확인한다. 기존 확정 일정은 자신의 catalogVersion을 계속 사용한다. 기존 일정을 새 catalog로 바꾸려 하지 않는다.
5. 사진 등록까지 시험하려면 **한국 시간 오늘의 미확정 시간대**가 필요하다. 오늘 이미 오전·오후 모두 확정되어 있으면 기존 일정을 삭제하지 않고 다음 적절한 날을 사용한다.
6. 기존 날짜별 결근은 catalog 구분 없이 staffId를 공유하므로 새 일정에도 그대로 적용된다. 기본 휴무일과 함께 확인하고 예비 직원으로 인계한다.
7. 아래 AI·사진 서버/빌드 요건을 확인한다. manifest 검사만으로 실제 배포·버킷·IAM 상태가 확인된 것은 아니다.

## 실제 Firebase 명령어 (운영자가 추후 명시적으로 실행)

실제 실행용 터미널에는 Emulator 관련 환경변수가 없어야 한다. Google Cloud 운영자 ADC/IAM을 사용하며 비밀키 파일을 저장하지 않는다. ADC가 아직 없을 때만 운영자가 `gcloud auth application-default login`을 수행한다. Firebase CLI 로그인과 ADC는 별개다. 로그에 토큰을 출력하지 않는다.

```powershell
# 네트워크를 사용하지 않는 고정 manifest 검사 및 등록 계획
node tools/register-demo10-catalog.cjs register --project senior-transport-app --plan

# 읽기 전용 등록 사전 점검
node tools/register-demo10-catalog.cjs register --project senior-transport-app

# catalog만 생성: settings 등 기존 데이터는 수정하지 않음
node tools/register-demo10-catalog.cjs register --project senior-transport-app --apply --confirm-project senior-transport-app --approve-catalog demo-10x24-v1

# 읽기 전용 완료 검증: VERIFIED, verified:true, 자식58·생성전체59 확인
node tools/register-demo10-catalog.cjs register --project senior-transport-app --verify

# 읽기 전용 전환 영향 점검: from은 반드시 deploy-test-v2
node tools/register-demo10-catalog.cjs switch --project senior-transport-app

# 실제 포인터 전환: 별도 승인, 다른 settings 필드 보존
node tools/register-demo10-catalog.cjs switch --project senior-transport-app --apply --confirm-project senior-transport-app --approve-catalog demo-10x24-v1
```

전환 후 앱을 새로 열고 확정 일정 없는 날짜에서 10명/24명/8대·8코스를 확인한다. 오전·오후 각각 관리자 확인 후 기존 confirmSchedule로 확정한다. 기존 staffSchedules도 해당 날짜·시간대만 생성/변경된다.

새 catalog 등록은 59문서 원자적 처리다. 응답 유실 등 결과가 불명확하면 **등록을 자동 재시도하지 말고 --verify부터 실행**한다. VERIFIED이면 재등록하지 않는다. 일부/변조 데이터면 자동 보충·삭제·덮어쓰기는 하지 않으며 사용을 보류한다. 전환 결과가 불명확하면 settings.catalogVersion을 읽기 전용으로 확인한다. 재실행은 예상 이전 값 불일치로 중단할 수 있다.

## AI·사진 허용 절차 (도구가 자동 변경하지 않음)

기존 값/목록은 보존하면서 운영자가 Console에서 필요한 필드만 편집한다.

**_aiControl/config**

- `allowedCatalogVersions` (array of string): 기존 목록에 `demo-10x24-v1` 추가.
- `mode` (string): 실호출할 때만 기존 정책에 따라 `test`. 기본/종료 시 `off`.
- `allowedAdminUids` (array of string): 승인할 기존 관리자 Auth UID. staffId가 아니다.
- `projectDailyLimit` / `adminDailyLimit` (integer): 일일 실제 호출 테스트는 각각 1 권장. 이미 오늘 사용한 횟수 이상 여유가 있어야 하며 사용 기록을 삭제해 우회하지 않는다.
- `cooldownSeconds` (integer): 허용 범위1~3600, 기존값 유지 가능.
- `requireAppCheck` (boolean): 기존 정책 유지. false면 토큰 부재만으로 거절하지 않는다.
- `allowFictionalLocations` (boolean): 가상 좌표를 Gemini 입력에 포함하려면 true. false면 서버 입력에서 locationModel이 제거되며 서버 거리 비교 자체는 별도로 유지된다.

Secret Manager의 기존 GEMINI_API_KEY, 모델/접근 권한, 배포된 일반 suggestSchedule가 준비돼 있어야 한다. 서버는 기존 catalog 일치·관리자 승인·비식별화·크기64KB·요청 중복/일일 제한·예비 인원·배정/정원 규칙을 계속 검사한다. 추천은 저장하지 않고 관리자 적용과 B-2/최종 확정을 거친다. AI 미리보기 플래그나 previewContext를 이 일반 일정에 사용하지 않는다. 자동 재시도나 실제 Gemini 호출은 이번 검증에 없다.

**_workPhotoControl/config**

- `allowedCatalogVersions` (array of string): `deploy-test-v2` 등 기존 목록을 유지하고 `demo-10x24-v1` 추가.
- `enabled` (boolean): 실제 사진 등록을 승인할 때 true. 서버 등록 off여도 기존 권한으로 조회 가능하다.
- `requireAppCheck` (boolean): 기존 정책 유지.

사진 함수 배포, 전용 비공개 버킷·WORK_PHOTO_BUCKET·실행 서비스 계정 IAM은 기존 사진 배포 문서에 따라 별도로 준비돼 있어야 한다. 서버는 활성 직원·본인 일정·오늘 날짜·확정본/직원별 투영 일치·일정/결근 버전·결근 여부·중복 사진·파일 검사를 계속 수행한다. 출근 사진을 먼저 등록한 뒤 종료 사진을 등록한다. 관리자와 기록 소유 직원만 서버 경유로 조회하며 공개 URL을 발급하지 않는다. 보존 기간은 기존30일 정책이다.

과거 Emulator Blob attendance 기록과 운영 Storage workPhotoRecords는 기존 설계대로 별도 경로다. 이 도구는 둘 다 보존하지만 getWorkPhotos가 Blob 기록까지 통합 조회하도록 바꾸지는 않는다. 같은 날짜·시간대·코스·종류의 기존 사진을 덮어쓰거나 중복 등록하지 않는다. 이번 작업은 운영 버킷/IAM/배포 현황을 새로 조회한 작업이 아니므로 실제 사용 준비 여부는 운영자가 배포 문서에 따라 확인해야 한다.

Web은 다음 기존 빌드 도구로 준비할 수 있다. 이는 **로컬 빌드만** 하며 배포하지 않는다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build-hosting.ps1 -EnableProductionAi -EnableStorageWorkPhotos
```

이미 운영 Web에 두 기능 플래그가 활성화돼 있다면 catalog 전환을 위해 업무 Functions·Rules를 다시 배포할 필요는 없다. 새 테스트 데이터 표시를 포함한 UI 변경은 추후 별도 승인 후 Hosting에 반영한다.

실제 적용 순서는 로컬 검증 → 새 catalog만 등록/verify → 기존 설정 보존하면서 AI·사진 준비 점검 → 새 테스트 데이터 표시가 포함된 Web 준비/별도 승인 배포 → switch dry-run/승인 전환 → 모든 클라이언트 새로고침 → 미확정 날짜의 오전·오후 명시적 확정 → 직원 사진/관리자 조회 순서다. 사진용 서버/버킷이 아직 없다면 catalog 전환만으로 사진 기능이 생기지는 않으므로 기존 사진 배포 절차가 먼저 필요하다.

## 원복

```powershell
# 읽기 전용 원복 영향 점검. from은 반드시 demo-10x24-v1
node tools/register-demo10-catalog.cjs rollback --project senior-transport-app

# 문제가 없고 운영자가 승인한 경우에만 기존 포인터로 복귀
node tools/register-demo10-catalog.cjs rollback --project senior-transport-app --apply --confirm-project senior-transport-app --approve-catalog deploy-test-v2
```

일정·결근·사진·새 catalog는 지우지 않는다. **이미 새 catalog로 확정한 날짜는 원복 후에도 새 catalog를 사용**한다. 원복은 전체 과거 상태 복원이 아니라 앞으로 미확정 날짜에 사용할 기본 데이터 선택만 되돌린다. 활성 신규 직원 연결이 있거나 이전 catalog가 변조/누락되었으면 중단한다. 필요하다면 별도로 AI mode를 off로 돌리고 사진 enabled 정책을 검토하되, 기존 기록/허용 목록을 자동 삭제하지 않는다.

## 로컬 검증

새 Functions 테스트 `demo10.test.cjs`는 별도 demo-* 프로젝트 namespace에서 기존 등록·전환·원복과 일반 업무 함수들을 실행한다. 실제 환경을 가장한 원격 연결이나 Gemini 호출은 하지 않는다. Storage에는 작은 프로그램 생성 JPEG만 사용한다. Flutter 테스트는 실제 새 JSON을 읽어 320/390/768/1280px에서 현황과 상세 편집·오후 전환을 검사한다. 기존 전체 테스트도 유지한다.

최종 실행 결과는 작업 완료 보고와 이 문서의 아래 검증 결과를 따른다.

고정 manifest SHA256: `56087b4bc16ba7131e61fa2c5cc7a18e95b6482c0fc26ef22a46032941091ce1`

고정 collections SHA256: `f32d08ae68d1d5c79660cafaefa3cf76557a928d514076def5e8fea6a0d037e0`

등록/전환 dry-run도 실제 프로젝트에서 실행하면 Firestore 읽기/집계 비용이 발생할 수 있다. 등록은59문서, 포인터 전환은1문서 쓰기다. 이 도구는 Gemini·사진 업로드·일정 확정을 호출하지 않으며 이후 기능 사용 비용은 기존 AI·사진 정책을 따른다.

### 검증 결과 (2026-11-14)

- flutter analyze: 문제 없음.
- Flutter 전체: **282개 통과**(신규5개 포함). 새 catalog로 320/390/768/1280px 현황·직원별 편집·오후 전환을 실제 widget render/overflow 검사했다. 오전/오후 시각 표현 기존 회귀도 유지한다. 실기기 브라우저 카메라 검증은 수행하지 않았다.
- Auth/Firestore/Functions/Storage Emulator 전체: **184개 통과**, 실패/취소/생략0. 신규 catalog9개 테스트 포함. 새 catalog 등록 실패 원자성, 동시 등록/전환/확정, 원복 제한, 과거 일정 pinning·기존 결근/Blob 보존, 사진 등록·권한·원복 후 Storage 사진 조회, 일반 운영 AI 경로의 가상 좌표 비식별화/예비 직원 추천을 검증했다. AI는 모의 generate만 사용했다.
- 추가 집중 Emulator 검증9개도 통과. 기존계정 로그인/Auth와 직접 Storage 거부/HTTP Callable 사진 검사는 전체 회귀에 포함된다. 계정/사진은 모두 로컬 demo namespace와 생성 JPEG다.
- Functions manifest: 기존5개 함수·리전 asia-northeast3·Node22·Secret은 suggestSchedule에만1개. 원격 요청0.
- 실제 Firebase 연결용 Web release 빌드 및 Hosting 파일 검사 성공(AI/Storage 사진 플래그 활성). fingerprint `7c146cf7460e01697e79be0abade76dc8cc8a608ded44e94a3599abdb71ad6b0`. 로컬 파일 검사이며 배포하지 않았다. 기존 Web 플러그인의 Wasm 호환 안내는 JS release 빌드를 막지 않았다.
- git diff --check: 통과(CRLF 변환 안내만 있음).

초기 검증에서 좌표의 -0과 JSON의0 차이, 테스트별 demo 프로젝트와 runner GCLOUD_PROJECT 충돌을 바로잡았다. 전체 회귀에서는 Firebase CLI가 FUNCTIONS_EMULATOR_HOST를 제공하지 않아 기존 HTTP 사진 테스트1개가 중단되었다. tools/test-emulators.ps1이 firebase.json의 검증된 loopback endpoint를 명시하도록 수정 후 전체184개를 재실행해 통과했다. 운영 함수의 제한이나 검증을 완화하지 않았다.

로그: `.local-tools/demo10-analyze.log`, `demo10-flutter.log`, `demo10-emulators-verified.log`, `demo10-targeted-final.log`, `demo10-manifest.log`, `demo10-web.log`. 초기 실패 로그는 진단용으로 보존하며 최종 결과와 구분한다.
