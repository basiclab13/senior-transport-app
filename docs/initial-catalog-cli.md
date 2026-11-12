# 운영자용 초기 가상 데이터 CLI

`tools/register-initial-catalog.cjs`는 일반 앱·Callable과 분리한 로컬 운영자 도구다. 실제 Firebase에서 실행하거나 데이터를 변경하지 않았으며 Functions/Rules 배포도 하지 않았다. 기존 Emulator 등록 도구는 변경하지 않았다.

## 대상과 인증 준비

- 고정 대상: `senior-transport-app`, `(default)` DB, `deploy-test-v1`.
- 입력: `docs/fixtures/deploy-test-v1.baseline.json`. 직원 3명, 차량 3대, 이용자 5명, 기본 코스 4개. 부하 테스트용 40명/79명 데이터와 `--scale`은 지원하지 않는다.
- 생성 가능 경로: `catalogs/deploy-test-v1/{staff,vehicles,passengers,baseRoutes}/{id}` 15개와 부모·`settings/schedules` 2개뿐이다.
- Node 22와 functions 의존성이 필요하다. 설치가 필요하면 저장소 루트에서 `npm.cmd --prefix functions ci`를 실행한다.
- 운영자 Application Default Credentials(ADC)와 해당 프로젝트의 Firestore IAM 권한을 사용한다. `firebase login`이나 일반 앱의 관리자 로그인은 ADC/IAM을 대신하지 않는다.
- 사용자가 신뢰할 수 있는 환경에서 `gcloud auth application-default login`을 직접 수행한다. quota project가 필요하면 `gcloud auth application-default set-quota-project senior-transport-app`을 사용한다. 읽기 점검에는 조회 권한, 적용에는 조회·생성·트랜잭션 권한이 필요하다. IAM 권한 부여는 운영자가 검토하며 도구가 부여하지 않는다.
- ADC는 저장소 외부의 사용자 인증 저장소에 둔다. 서비스 계정 JSON 키를 프로젝트·Git에 넣지 않는다. 도구는 키 파일 옵션, 비밀번호·토큰 출력 기능을 제공하지 않는다.
- Admin SDK는 Firestore Security Rules를 우회하므로 운영자 IAM과 CLI의 보호가 중요하다. 앱의 배포된 Rules 검증을 대신하지 않는다. Functions 배포·Blaze 전환은 수행하지 않는다. 실제 읽기·쓰기는 사용량 비용이 발생할 수 있다.

공식 참고: [운영자 ADC 설정](https://cloud.google.com/docs/authentication/provide-credentials-adc), [Firestore 트랜잭션](https://firebase.google.com/docs/firestore/manage-data/transactions).

## 사용자 직접 실행 순서

먼저 네트워크와 ADC를 사용하지 않는 계획만 확인한다.

```powershell
node tools/register-initial-catalog.cjs --project senior-transport-app --plan
```

실제 점검을 결정했을 때만 아래 명령을 실행한다. **기본 실행은 실제 Firestore를 읽는 dry-run이며 쓰지 않는다.** `--dry-run`은 생략 가능하다. 읽기 비용은 발생할 수 있다.

```powershell
node tools/register-initial-catalog.cjs --project senior-transport-app --dry-run
```

`DRY_RUN_OK`, 대상 프로젝트·경로·개수·`manifestSha256`·직원 연결 결과를 확인한다. `BLOCKED`가 있으면 적용하지 않는다. 이후 운영자가 실제 생성을 결정한 경우에만 두 옵션을 함께 사용한다.

```powershell
node tools/register-initial-catalog.cjs --project senior-transport-app --apply --confirm-project senior-transport-app
```

적용 후 다시 dry-run으로 `ALREADY_REGISTERED`와 `verification: passed`를 확인한다. 빈 대상에서는 자식 15개 + 메타데이터 2개, 총 17개가 생성된다. 기존 동일 자식은 건드리지 않으므로 생성 수는 작아질 수 있다. 완료 후 `verifiedChildDocuments: 15`와 `activated: true`를 확인한다.

성공 종료 코드는 0이다. 옵션 오류·충돌·연결/저장/검증 실패는 0이 아니다. JSON 결과는 문서 값, 사용자 UID/email, 인증 정보, 원본 SDK 예외를 출력하지 않는다. `--force`, 삭제, 덮어쓰기 옵션은 없다.

`GCLOUD_PROJECT`, `GOOGLE_CLOUD_PROJECT`, `FIREBASE_CONFIG`의 프로젝트가 다르거나 실제 모드에 Emulator 환경 변수가 있으면 연결 전에 거부한다. 환경 변수를 무조건 지우지 말고 운영자 셸의 대상과 인증을 먼저 확인한다.

## 보존·검증 및 실패 처리

1. 입력 필드/타입, 고정 ID·개수, 직원·차량·이용자 참조, 시간대별 중복·누락·정원을 검증한다. 휴무 요일 배열은 1~7 정수다. 날짜별 근무/시각 검증은 기존 일정 확정 기능의 책임이며 이 도구는 날짜별 일정을 만들지 않는다.
2. 기존 부모·네 종류의 전체 자식 컬렉션·settings·`active == true`인 users를 읽는다. 활성 `role == "staff"` 계정의 staffId는 문자열 s1/s2/s3여야 한다. 관리자에게 staffId를 요구하지 않으며 비활성 계정은 제외한다. users를 수정하거나 Auth API를 호출하지 않는다.
3. 기존 자식은 필드/타입/값이 정확히 같으면 보존한다. 다르거나 예상 외 자식이 있으면 전체 적용을 중단한다. 기존 문서의 updateTime도 바뀌지 않는다.
4. 기존 부모는 정확히 `{ready:true, fictional:true, schemaVersion:1}`이고 모든 자식이 검증되어야 보존할 수 있다. ready=false, 추가 필드, 잘못된 타입·배열은 자동 보정하지 않는다. 기존 settings가 같은 버전을 가리키면 다른 필드까지 보존한다. 다른 버전이거나 부모 없이 이미 포인터가 있으면 중단한다.
5. 자식 생성 트랜잭션은 사전 점검을 반복하고 없는 자식에 create만 사용한다. 저장 후 서버에서 재조회하고, 활성화 트랜잭션에서 모든 자식·계정·메타데이터를 재검증한 다음 부모와 포인터를 함께 생성한다. 모든 읽기가 쓰기보다 먼저이며 SDK 재시도에도 기존 문서를 덮어쓰지 않는다.
6. 활성화 직전 자식/직원 연결/포인터가 바뀌면 재검증으로 차단한다. 오류 뒤에는 dry-run부터 다시 수행한다. 커밋 응답 유실로 생성 여부를 단정할 수 없으면 생성 수·활성화 상태가 null일 수 있으므로 서버 재조회로 확인한다.
7. 자식은 저장됐으나 활성화가 실패하면 부모/포인터 없이 비활성 자식만 남을 수 있다. 자동 롤백 삭제는 하지 않는다. 정확히 같은 자식은 재실행 시 보존하고 부족한 단계만 수행한다. 이미 노출된 불완전 부모는 자동 복구하지 않는다.

### Console에서 이미 만든 부모의 잘못된 배열

`PARENT_ARRAY_FIELD`는 잘못된 필드 이름과 수정 안내를 출력하고 실행 전체를 중단한다. staff, vehicles, passengers, baseRoutes는 부모 배열이 아니라 하위 컬렉션이다. unavailableWeekdays는 staff/{id}의 배열이고 passengerIds는 baseRoutes/{id}의 배열이다.

운영자가 Console에서 기존 필드·자식·활성 포인터와 사용 여부를 확인하고 필요한 수정을 별도로 검토해야 한다. CLI는 ready=false 부모도 true로 바꾸지 않는다. 기존 부모의 수정/정리나 새 버전 등록 정책은 이 CLI 실행 범위가 아니다. 자식 검증 없이 ready=true로 바꾸지 않는다. staffId 오류도 올바른 Auth UID의 users 문서를 운영자가 별도로 확인한다.

Authentication, users, schedules, staffSchedules, commits는 쓰기 대상이 아니다. 계정·역할·날짜별 일정은 생성/변경되지 않는다.

## 로컬 테스트

```powershell
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '60'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/test-emulators.ps1
flutter analyze
flutter test
```

등록 테스트는 별도 demo-catalog-registration Emulator 네임스페이스만 사용한다. --emulator는 demo- 프로젝트와 loopback Firestore 주소를 함께 요구한다. 테스트 문서 정리는 이 로컬 demo 공간에만 한정된다. 실제 프로젝트 모드의 명령은 --plan 외 실행하지 않는다.

2026-11-12 로컬 결과: Emulator 전체 29개(기존 11 + 등록 도구 18) 통과, flutter analyze 문제 없음, flutter test 48개 통과, 오프라인 --plan에서 자식 15개 확인. 함수 탐색의 기본 10초 제한에 걸린 재실행은 제한을 60초로 늘려 단독 재실행했고 최종 29개 모두 통과했다. 같은 테스트 네임스페이스를 정리하므로 전체 테스트와 해당 파일의 개별 테스트를 동시에 실행하지 않는다. 실제 프로젝트 데이터·인증·IAM·배포 상태는 조회하거나 변경하지 않았다.
