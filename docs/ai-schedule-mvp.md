# 생성형 AI 송영 일정 제안 MVP

> 현재 관리자용 쉬운 표현과 AI 선택 후 여러 코스의 시간을 함께 확인하는 동선은 [simple-admin-flow.md](simple-admin-flow.md)를 따른다. 기존 AI 선택·시간 확인·최종 확정은 별도 단계로 유지한다.

> 가상 위치·단순 휴리스틱 참고 후보·프로그램의 전후 거리 비교 추가 사항은 [ai-location-prototype.md](ai-location-prototype.md)를 참고한다. 기존 20명/80명 fixture를 덮어쓰지 않고 메모리 좌표 사본으로 지원한다.

## 구현 범위

기초프로젝트랩 시연용이다. Firebase Auth/Firestore/Functions는 `demo-senior-transport`의 로컬 Emulator만 사용한다. Gemini API만 실제 외부 호출한다. 운영 Firebase 배포·데이터 변경과 출근 기록 기능 변경은 없다.

관리자는 날짜/오전·오후의 현재 초안에서 `AI 일정 제안`을 요청한다. `suggestSchedule` Callable은 활성 관리자 권한을 검사하고 가상 catalog·확정 일정 버전·해당 날짜의 결근 버전을 확인한 다음 Gemini에 구조화 JSON 변경안 하나를 요청한다. 서버는 Firestore를 읽기만 하고, 추천 이력이나 일정을 저장하지 않는다. AI 호출은 Firestore 트랜잭션 밖에서 한 번만 수행한다. 호출 전후에 read-only 트랜잭션으로 컨텍스트를 확인해 서버 변경도 거부한다.

AI에 전달하는 내용은 ID 기반 현재 코스/직원/차량/이용자 순서, 기본 코스, 정원, 결석·제외 ID, 서버에서 계산한 근무 가능 직원 ID다. 이름·주소·이메일·Authentication UID·개인 메모·기존 예상 시각은 외부 API에 전달하지 않는다. 지도 이동시간이나 최적 경로를 계산하지 않는다.

AI 응답 필드는 `routes[{baseRouteId,staffId,passengerIds}]`, `reasons[string]`만 허용한다. 해당 시간대의 모든 기본 코스와 결석/제외 외 모든 이용자가 정확히 한 번 포함되어야 한다. 직원 활성/기본 휴무/날짜별 결근, 동일 시간대 직원 중복, 고정 차량의 중복과 정원을 기존 `validateSchedule`로 검증한다. 차량·날짜·결석 상태·시각 변경 필드를 응답에 넣으면 거부한다. 유효한 대안이 없거나 API가 실패하면 원본을 유지한다.

차량과 운행 구간은 기존 코스에 남긴다. 이용자 이동 시 기존 예상 시각·출처를 함께 옮기며, 출처 없는 시각도 그대로 보존한다. 응답이 이 값을 직접 제공하지 못하도록 서버와 Flutter에서 각각 원본으로 재구성한다. 추천의 배정 구조와 기존 시각 충돌은 구별한다. 배정이 유효하면 시각 충돌을 경고하며 초안 승인 대상으로 표시하고, 적용 후 B-2 미검토/시각 충돌이 남으면 기존 전체 확정이 차단된다. 최종 서버 검증을 면제하거나 Rules를 완화하지 않는다.

관리자 검토 대화상자는 요청 당시 초안과의 변경 요약·이유·시각 경고를 표시한다. `승인 · 초안에 적용`을 선택해야 `_update`로 한 번에 반영한다. 취소/실패에는 변경하지 않는다. 변경이 없으면 명확히 표시하고 적용 버튼을 비활성화한다. 요청 중/검토 중 초안·날짜·시간대·카탈로그·확정본·결근 리비전이 바뀌면 승인할 수 없다. 이후 B-1/B-2 검토와 기존 `confirmSchedule` 확정 절차를 별도로 사용한다.

## 서버 Secret과 모델 설정

이번 구현 시 `functions/.secret.local`과 프로세스의 키 설정 유무만 확인하며 값을 출력하지 않는다. 키가 없으면 실제 Gemini 호출을 수행하지 않는다. 테스트가 통과했다는 것은 실제 API 키/모델 접근 권한 검증을 의미하지 않는다.

1. 운영자 본인이 Google AI Studio에서 Gemini API 키를 발급하고 사용 가능 모델 및 사용 한도/요금을 확인한다. 이 과정에서 이 앱의 운영 Firebase 요금제나 서비스를 변경할 필요는 없다. 실제 AI 호출은 공급자 정책에 따라 비용이 발생할 수 있다.
2. 로컬 편집기로 `functions/.secret.local`을 생성하고 `GEMINI_API_KEY`에 발급받은 값을 설정한다. 아래는 형식 설명이며 실제 키가 아니다.

   ```dotenv
   GEMINI_API_KEY=<본인이 발급한 키>
   ```

3. 기본 모델은 `gemini-3.8-flash`다. 다른 사용 가능 모델을 쓰려면 `functions/.env.local`에 `GEMINI_MODEL=모델ID`를 설정한다. API가 모델 접근 오류를 반환하면 계정에서 `generateContent`와 구조화 출력을 지원하는 모델인지 확인한다.
4. 두 파일은 `.gitignore`와 Functions 배포 제외 목록에 포함한다. 키는 `defineSecret('GEMINI_API_KEY')`와 함수의 `secrets` 옵션을 통해 서버에서만 사용한다. Flutter의 코드·dart-define·Firebase 설정·빌드 결과물에 넣지 않는다. 응답·로그에 키나 공급자 원본 오류를 출력하지 않는다.
5. 파일 준비 후 Emulator를 재시작한다. 키 없이 추천 버튼을 눌러 Secret Manager에 의존하지 말고 로컬 Secret을 먼저 설정한다. 이번 MVP는 실제 프로젝트에서 실행을 거부하므로 배포용 Secret Manager 설정·배포 명령은 제공하거나 실행하지 않는다.

Firebase 공식 로컬 Secret 안내: https://firebase.google.com/docs/functions/config-env

Gemini 공식 REST/구조화 출력 안내: https://ai.google.dev/api/generate-content

## 빠른 시연 준비

새 로컬 Emulator 세션을 시작한다. 운영 데이터 import는 하지 않는다. 기존 `tools/start_operations_emulators.ps1`은 8080/9099/5001 포트와 demo 프로젝트를 사용한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/start_operations_emulators.ps1
```

다른 터미널에서 기존 20명/80명 fixture 등록 도구를 사용한다. 가상 계정 비밀번호는 직접 정한 로컬 시연용 값을 해당 터미널의 `EMULATOR_USER_PASSWORD` 환경 변수에 먼저 설정한다. 비밀번호를 소스에 저장하지 않는다. 등록 도구는 demo 프로젝트와 loopback을 확인하며 기존 계정·fixture 충돌은 거부한다. 기존 계정을 재사용할 때는 처음 설정한 비밀번호를 사용한다.

```powershell
$env:GCLOUD_PROJECT = 'demo-senior-transport'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
$fixturePassword = Read-Host 'Emulator용 비밀번호(12자 이상, 기존 계정은 처음 설정한 값)' -AsSecureString
$env:EMULATOR_USER_PASSWORD = [System.Net.NetworkCredential]::new('', $fixturePassword).Password
node tools/prepare_operations_emulator.cjs
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=true
```

관리자 가상 계정은 `ops-admin@example.invalid`, 예비 직원은 `ops-s3@example.invalid`다. 비밀번호는 위에서 운영자가 설정한 값이다. 초기 데이터는 오늘·내일 오전/오후를 생성한다.

### 등록 실패 진단

`node`는 Functions의 `.env.local`/`.secret.local`이나 Firebase CLI 기본 프로젝트를 자동으로 읽지 않는다. 위 환경 변수는 **등록 명령을 실행하는 같은 터미널**에 설정해야 한다. Gemini API 키는 로그인 비밀번호나 `EMULATOR_USER_PASSWORD`의 대체값이 아니다.

등록 도구는 실패 시 원본 예외/메시지/stack/계정 정보 대신 `errorCode`, `stage`, 허용된 `serviceCode`, **이번 실행에서 새로 생성된** 계정·일정 수와 정적인 안내만 출력한다. `PROJECT_MISMATCH`, `FIRESTORE_HOST_INVALID`, `AUTH_HOST_INVALID`, `PASSWORD_REQUIRED`, `PASSWORD_TOO_SHORT`는 SDK 초기화 전에 중단하므로 이 실행에서는 Firebase에 연결하거나 데이터를 만들지 않는다. `EMULATOR_UNAVAILABLE`/`AUTH_REQUEST_FAILED`는 해당 Emulator 연결·로그를 확인한다. `EXISTING_SETTINGS_CONFLICT`, `CATALOG_*_CONFLICT`, `ACCOUNT_DISABLED`, `PROFILE_CONFLICT`는 기존 데이터/계정과 기대 fixture가 다르다는 뜻이며 자동으로 덮어쓰거나 삭제하지 않는다.

이 도구는 catalog 확인·등록 후 Auth 계정과 users 문서를 만들고 마지막에 일정을 생성한다. 따라서 catalog 단계 이전 실패는 로그인 계정 미등록과 연결될 수 있고, 이후 실패에는 일부 데이터가 이미 생성되었을 수 있다. 실패 문구만 보고 Emulator를 초기화하지 않는다. 기존 계정은 새 비밀번호로 갱신하지 않고 재사용하므로, 재실행 때 비밀번호 변수를 바꿔도 기존 계정 비밀번호는 바뀌지 않는다.

Flutter의 `auth/user-not-found`는 로그인한 연결 대상에 해당 계정이 없다는 뜻이다. 등록 성공 여부와 로그인 이메일을 확인하고, 앱 시작 로그가 `project=demo-senior-transport environment=emulator`인지 확인한다. `flutter run -d chrome`만 실행하면 현재 기본 설정은 실제 Firebase이므로 위의 `--dart-define=USE_FIREBASE_EMULATORS=true`가 필요하다. Emulator를 데이터 export/import 없이 종료·재시작했다면 기존 메모리 계정도 유지되지 않을 수 있다. 이 경우에도 기존 데이터 상태를 먼저 확인한다.

권장 시연 순서:

1. 관리자 로그인 후 오전 선택. `김다정` 직원 결근을 해당 날짜 오전에 등록한다. 예비 직원 `박여유(s3)`가 근무 가능한 날짜를 선택한다. 기본 휴무 금요일에는 대체 불가하므로 다른 날짜를 사용한다.
2. 이용자 결석도 한 명 반영하고 `AI 일정 제안`을 누른다. 생성 중 표시 뒤 실제 Gemini 응답의 이유와 변경사항을 확인한다. 추천은 최적해를 보장하지 않으며 유효하지 않으면 적용할 수 없다.
3. 한 번 취소해 원본 초안이 보존됨을 보여주고 다시 요청한다. `승인 · 초안에 적용`으로 일괄 반영한다.
4. 영향 코스에서 B-2 재검토 표시를 확인하고 기존 시각 유지 또는 B-1 미리보기/적용을 진행한다. 수동 시각 변경은 기존 별도 확인을 거친다.
5. 전체 변경 검토 후 Emulator에 확정하고 새 담당 직원으로 로그인해 확정본을 확인한다.

현재 스키마는 빈 코스도 삭제하지 않으며 코스마다 서로 다른 근무 가능 직원이 필요하다. 대체 직원이 부족하면 AI가 코스를 합쳐 해결한다고 표시하지 않고 검증 실패를 안내한다. 사용자가 요청하지 않은 차량 변경·자동 결근 취소·이용자 누락으로 해결하지 않는다. AI 실패 시 기존 수동 조정 기능을 계속 사용할 수 있다.

## 변경 파일

| 파일 | 내용 |
|---|---|
| `functions/index.js` | v2 `suggestSchedule`, 리전/Secret/모델 설정 |
| `functions/gemini-schedule.js` | 실제 Gemini REST 호출, JSON Schema, 제한 시간, 안전한 오류 |
| `functions/suggestion-service.js` | Emulator/권한/버전 검사, 최소 입력, 응답 재구성·검증, 읽기 전용 처리 |
| `lib/models/ai_schedule_suggestion.dart` | 불변 추천안과 요청 당시 초안·컨텍스트, 보호 필드 재구성 |
| `lib/services/schedule_repository.dart` | Emulator 전용 Callable 요청 인터페이스 |
| `lib/services/schedule_controller.dart` | 중복 요청 차단, 오래된 응답/승인 거부, 초안 일괄 적용/B-2 연결 |
| `lib/screens/schedule_screen.dart` | 관리자 AI 버튼·로딩·오류·승인 동선 |
| `lib/widgets/ai_schedule_suggestion_dialog.dart` | 이유·변경 요약·시각 경고·적용/취소 |
| `.gitignore`, `firebase.json` | 로컬 Secret/설정 파일 제외, 기존 Firebase 설정 보존 |
| `functions/test/ai-suggestion.test.cjs`, `gemini-schedule.test.cjs` | 고정 응답으로 서버 검증 및 REST 어댑터 검사 |
| `test/ai_schedule_suggestion_test.dart` | 요청/승인/보존/실패/오래된 응답/권한/B-2/작은 화면 |

Firestore 스키마·Rules·기존 확정 함수·결근 등록 함수·출근 기록 기능은 이 MVP 때문에 변경하지 않는다. B-1/B-2 선행 변경은 그대로 유지한다.

## 로컬 검증

### Gemini는 성공했지만 추천 검증이 실패할 때

`gemini-schedule`의 HTTP 200 / `proposal-json completed`는 JSON 해석 성공이며 업무 규칙 통과를 뜻하지 않는다. 과거 `validate-suggestion invalid-argument` 로그만으로 해당 응답의 위반 종류는 확정할 수 없다. 원본 AI 응답을 저장하거나 출력해서 추적하지 않는다.

이제 같은 `diagnosticId`에서 `component=suggestSchedule`, `event=validation-failed`, `stage=validate-suggestion` 로그를 확인한다. `violationType`과 필요한/반환된 코스·이용자 수, 가용 직원 수, `insufficientAvailableStaff`만 기록한다. ID·이름·계정·일정·이유·응답 원문·원본 예외는 기록하지 않는다. 기존 검증은 첫 실패에서 중단하며 이 코드는 **처음 발견한 위반**이다. 하나의 응답에 여러 문제가 있을 수 있다.

| violationType | 의미 |
|---|---|
| `ROUTE_MISSING` / `ROUTE_COUNT_MISMATCH` | 일부 변경 코스만 반환했거나 전체 코스 수가 맞지 않음. 불가능하다고 빈 배열을 반환한 경우도 누락으로 거부 |
| `ROUTE_DUPLICATE` / `ROUTE_UNKNOWN` | 코스 중복 또는 현재 시간대에 없는 코스 |
| `PASSENGER_MISSING` / `PASSENGER_DUPLICATE` | 이용자 누락 또는 코스 내/코스 간 중복 |
| `PASSENGER_UNKNOWN` / `REMOVED_PASSENGER_ASSIGNED` | 잘못된 이용자 또는 결석·제외 이용자 배정 |
| `STAFF_DUPLICATE` | 같은 직원에게 여러 코스 배정 |
| `STAFF_ABSENT` | 날짜·시간대의 결근 직원에게 배정 |
| `STAFF_UNAVAILABLE` | 없는 직원, 비활성 직원 또는 기본 휴무 요일 |
| `VEHICLE_CAPACITY_EXCEEDED` | 해당 코스의 고정 차량 정원 초과 |
| `RESPONSE_FIELDS_FORBIDDEN` | 차량·시각·결석 상태 등 허용하지 않은 필드 출력 |
| `RESPONSE_FORMAT_INVALID` / `REASONS_INVALID` | 응답 구조 또는 이유 목록 형식/길이 위반 |

공통 `validation.js`의 판단 조건과 오류 HTTP 코드는 유지하고 안전한 enum `details.violation`만 추가했다. 직원/차량, 코스/이용자 등 묶여 있던 실패 분기를 같은 조건으로 나누어 진단한다. 최종 확정의 기존 검증도 그대로 유지한다. 시각 역전은 추천 구조 검증과 분리해 기존 B-2에서 검토하고, 미해결 상태의 확정은 차단한다.

현재 20명/80명 fixture에는 19개 코스와 예비 직원 1명이 있으며 예비 직원 `s3`는 금요일 휴무다. 금요일에 다른 직원도 한 명 결근하면 가용 직원은 18명으로 19개 코스를 모두 맡을 수 없다. 이때 `availableStaffCount=18`, `expectedRouteCount=19`, `insufficientAvailableStaff=true`로 확인할 수 있다. 이 예시는 코드/fixture에서 확인한 조건이며 사용자가 겪은 특정 요청의 실제 원인이라고 단정하지 않는다. 예비 직원이 근무 가능한 날짜의 가상 시나리오를 사용한다. 코스 삭제나 중복 배정, 결근/휴무 무시로 해결하지 않는다.

형식/ID 선택/누락 실수는 프롬프트와 응답 스키마로 줄일 수 있다. 최소 수정으로 다음을 반영했다.

- 변경 없는 코스와 빈 코스를 포함한 전체 배정을 반환하고, 코스 수·이용자 전체 집합·직원 유일성·정원을 자체 점검하도록 명시.
- 최소 입력에 `requiredRouteCount`, 결석·제외를 뺀 `requiredPassengerIds`, 각 코스 고정 차량의 `passengerCapacity`를 추가. 개인정보를 외부 입력에 추가하지 않음.
- 요청별 코스 ID, 근무 가능한 직원 ID, 대상 이용자 ID를 JSON Schema 문자열 enum으로 제한. 빈 enum을 만들지 않으며 대상 이용자가 없으면 배열 최대 길이를 0으로 설정.
- 전역 중복·누락·정원은 JSON enum만으로 보장되지 않으므로 서버 검증을 계속 수행. 자동 수정·재시도·데이터 저장·새 UI는 추가하지 않음.

Gemini의 enum/부분 JSON Schema 지원은 [공식 구조화 출력 문서](https://ai.google.dev/gemini-api/docs/structured-output)를 참고한다. 모델·API 제한 시간은 변경하지 않았다. 실제 API는 이번 수정에서 호출하지 않았으므로, 실행 중인 Functions에 변경이 반영된 뒤 동일 시나리오를 다시 요청해 안전한 코드로 원인을 확정해야 한다. 데이터 보존 없이 Emulator를 종료·초기화하지 않는다.

이번 변경의 관련 검증은 Node 고정 응답 테스트 32개(20명/80명 정상·오류, 실패 종류, 민감 문자열 비노출, 요청별 enum, 금요일 직원 부족), Flutter AI 관련 테스트 11개 통과 및 `flutter analyze` 오류 없음이다. Emulator 데이터에 등록/삭제하거나 운영 Firebase를 변경하지 않았으며, 전체 Emulator 재실행 대신 데이터 접근 없는 관련 검사를 수행했다.

### HTTP 503 / 약 45초 실패 진단

설정은 Gemini `AbortSignal.timeout(45000)`, Functions `timeoutSeconds:90`, Flutter Callable 105초다. 진단 추가 과정에서 제한 시간과 모델 설정은 변경하지 않았다. Gemini의 45초 signal은 응답 헤더 대기와 응답 본문 읽기에 모두 적용된다.

기존 코드는 Gemini HTTP 오류, 네트워크 오류, 서버의 45초 취소, 응답 JSON 오류를 모두 `HttpsError('unavailable', ...)`로 반환할 수 있었다. Firebase SDK의 `unavailable`은 브라우저에 HTTP 503으로 매핑된다. 따라서 브라우저의 503은 Gemini 원격 서버가 503을 반환했다는 증거가 아니다. 약 45181ms 실패는 서버 45초 취소와 일치하는 정황이지만, 과거 로그만으로 HTTP/네트워크/취소 중 하나로 확정할 수 없다. `auth: VALID`는 Callable 토큰 검증 결과이며 Gemini API 인증/응답 성공을 뜻하지 않는다.

Functions 로그에 `component=suggestSchedule`과 `component=gemini-schedule`의 JSON 진단을 추가했다. 서버 생성 `diagnosticId`로 같은 요청을 연결한다. Callable은 환경/초안 검증, 컨텍스트 읽기, Gemini 생성, 추천 검증, 컨텍스트 재확인 단계를 기록한다. Gemini는 요청 시작, 응답 헤더 수신, 완료/실패를 기록한다. 포함 필드는 실패 단계 `stage`, `elapsedMs`, `timeoutMs`, 원격 `httpStatus`(미수신이면 null), `errorType`, `timeoutTriggered`, 허용된 `networkCode`뿐이다. 원본 예외·메시지·stack, API 키·URL·헤더·모델 설정값, 입력 일정과 응답 원문은 로그에 넣지 않는다. Callable 마지막 로그에는 안전한 SDK 오류 코드도 포함한다.

| Gemini 실패 로그 | 해석 |
|---|---|
| `REQUEST_TIMEOUT`, `timeoutTriggered=true`, `httpStatus=null`, `stage=request` | 45초 제한으로 응답 헤더 수신 전 서버 요청 취소 |
| `REQUEST_TIMEOUT`, `httpStatus=200`, `stage=response-body` | 헤더 이후 본문을 읽는 동안 45초 제한 도달 |
| `GEMINI_HTTP_ERROR`, `httpStatus=4xx/5xx` | 실제 Gemini HTTP 오류. 키/모델/한도 등은 상태와 공급자 설정에서 확인하며 응답 본문은 출력하지 않음 |
| `NETWORK_ERROR` / `NETWORK_TIMEOUT` | DNS·소켓·TLS·연결 제한 등의 네트워크 실패. `ENOTFOUND`, `UND_ERR_CONNECT_TIMEOUT`, `ETIMEDOUT` 등 허용 코드만 기록 |
| `RESPONSE_JSON_ERROR` / `JSON_PARSE_ERROR` | 공급자 응답 JSON 또는 추천 JSON 해석 실패 |
| `GEMINI_INCOMPLETE_RESPONSE` | 정상 종료된 완전한 후보가 없음. 차단/생성 중단/출력 제한 등을 개별 원문 없이 구분 가능한 범주로 표시 |

Gemini 진단 없이 Callable이 `read-context` 등에서 실패했다면 해당 실패는 Gemini 외 단계에서 발생한 것이다. Flutter 자체 제한은 105초이므로 약 45초에 서버가 반환한 503만으로 클라이언트 타임아웃이라고 판단하지 않는다. 클라이언트가 `deadline-exceeded`를 보고했는지도 함께 구별한다.

로그 추가를 반영한 Functions가 로드됐는지 확인하고 한 번 다시 요청한 뒤, 동일 `diagnosticId`의 Gemini `failed`와 Callable `failed` 메타데이터를 비교한다. 실행 중 Emulator를 무조건 종료·초기화하지 않는다. 파일 감시의 재로딩이 반영되지 않아 재시작이 필요한 경우, 메모리 가상 계정/일정 보존을 먼저 확인한다. 실제 API 재호출과 설정 변경은 이번 진단 코드 추가 과정에서 수행하지 않았다.

진단 전용 테스트는 가짜 HTTP/즉시 취소 signal로 수행한다. 실제 45초를 기다리거나 Gemini를 호출하지 않으며, 45000ms 설정이 그대로 전달되는지와 헤더 전/본문 중 취소, 실제 HTTP 오류, 네트워크 코드, JSON 실패, 민감 문자열 비노출을 검증한다.

```powershell
flutter analyze
flutter test
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-emulators.ps1
flutter build web --debug --dart-define=USE_FIREBASE_EMULATORS=true
```

자동 테스트는 고정 응답/가짜 HTTP 전송만 사용하며 실제 Gemini API를 호출하지 않는다.

최종 결과:

- `flutter analyze`: No issues found.
- `flutter test`: 168개 통과. 기존 테스트와 AI 요청/취소/승인, 보호 필드 보존, 잘못된 배정·누락·중복, 결근 직원, 요청 도중 초안/결근/날짜 변경, 검토 중 변경, API 실패, 로딩, 작은 화면, B-2 재검토 및 확정을 포함한다.
- Firebase Emulator Node 테스트: 62개 통과. 기존 Auth/Rules/결근/확정 검증과 20명/80명 고정 AI 응답의 업무 규칙·읽기 전용 원본 보존·서버 동시 변경·시각 충돌 확정 거부·시각 검토 후 확정/직원 문서 반영을 검사한다. Gemini REST 어댑터는 가짜 HTTP 전송으로 요청 스키마와 Secret 헤더, 오류/한도/잘린 JSON을 검증한다.
- `flutter build web --debug --dart-define=USE_FIREBASE_EMULATORS=true`: 성공.
- `functions/.secret.local` 없음, 프로세스의 `GEMINI_API_KEY` 없음. 실제 Gemini 호출과 계정별 모델 접근 권한 확인은 미실행이다. 임의의 키나 앱용 가짜 응답 대체 기능을 만들지 않았다.
- Emulator가 `suggestSchedule` v2 Callable을 로컬 5001 포트에 정상 등록하는 것을 확인했다. 자동 검증 후 Emulator는 종료했다. 키 설정 후 실제 버튼→Gemini 응답까지의 시연 확인이 남아 있다.

로그는 Git 제외 디렉터리 `.local-tools/ai-flutter-tests.log`, `.local-tools/ai-emulator-tests.log`, `.local-tools/ai-web-build.log`에 있다. Web 빌드는 Emulator용이므로 운영 Hosting에 배포하지 않는다. 실제 Firebase 배포/데이터 변경과 출근 기록 변경은 수행하지 않았다.
