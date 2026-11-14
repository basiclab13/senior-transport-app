# 운영 AI 제한적 테스트 준비

2026-11-14 로컬 구현. 실제 배포·Secret 등록·운영 Firestore 변경·서비스/결제 활성화·실제 Gemini 호출은 하지 않았다.

## 기본 동작과 변경 범위

운영 Functions manifest에 `suggestSchedule`을 추가했다. 기존 `confirmSchedule`, `setStaffAbsence`의 handler·리전·인스턴스 설정과 서비스 구현, 사진 코드, Firestore/Storage Rules, 기존 일정 스키마는 변경하지 않았다. Gemini Secret은 `suggestSchedule`에만 연결된다. 운영 함수 discovery에는 이제 Gemini Secret/모델 파라미터가 의도적으로 나타나며, 예전의 "함수 두 개·파라미터 0개" 검사는 현재 기준이 아니다.

운영 AI는 `_aiControl/config`가 없거나 `mode`가 `test`가 아니면 거절한다. `test`에서도 서버가 active 관리자·승인 UID·승인 가상 catalog·선택적 App Check를 확인한다. 일반 운영 전체 개방 모드는 구현하지 않았다. Flutter도 `ENABLE_PRODUCTION_AI` 기본값이 false이며, 실제 프로젝트와 명시적 빌드 옵션이 맞아야 버튼/요청이 활성화된다. 클라이언트 옵션은 서버 권한을 대신하지 않는다.

Emulator는 기존 `emulator-ai.js`를 그대로 사용한다. 공통 `suggestCore`는 서버 전용이며, Emulator wrapper는 기존 환경 검사를 유지한다. 운영 wrapper도 실제 프로젝트 및 Emulator 환경 변수 부재를 검사한다. 운영 정책 테스트는 별도 demo namespace에서 service를 직접 호출하고 외부 생성 함수를 모의 구현한다.

변경 파일:

- `functions/index.js`, `production-ai.js`: 운영 Callable 진입점, Secret, 호출 옵션, 안전한 연결 검사.
- `functions/suggestion-service.js`: 공통 추천 엔진과 기존 Emulator guard 분리. 기존 관리자·가상 catalog·확정 일정/결근 버전·배정·거리 평가·응답 이후 재검증은 유지.
- `functions/production-ai-service.js`: 운영 승인, 호출 예약, 비식별화, 모의 주입 가능한 서버 생성 경로, 완료/오류 처리와 로그.
- `functions/ai-request-policy.js`: Firestore 트랜잭션 기반 호출 횟수와 요청 생명주기.
- `functions/ai-privacy.js`: 요청마다 임시 ID 생성, 외부 전송 allowlist 재구성, 원본 ID 잔존 검사, 응답 ID 복원과 금지 필드 차단.
- `lib/services/schedule_repository.dart`, `schedule_controller.dart`: 명시적 운영 opt-in, 요청마다 고유 ID, 쉬운 오류 안내. 관리자 승인·B-2·확정 동작은 유지.
- `tools/verify-functions-build.cjs`, `tools/build-hosting.ps1`: manifest 계약 및 기본 비활성/제한 테스트 빌드.
- `functions/test/production-ai.test.cjs`, `function-entry.test.cjs`, `test/ai_schedule_suggestion_test.dart`: 운영 정책·manifest·Flutter 요청 식별자 검증.

## 개인정보와 추천 검증

외부 요청은 원본 객체를 복사하지 않고 허용 필드만 새로 만든다. 직원·차량·코스·이용자 ID는 요청별 무작위 alias로 치환한다. 원래 날짜는 요일로 축소한다. 이름·주소·이메일·Auth UID·원래 문서 ID·자유 메모·기존 시각·출처·사진은 보내지 않는다. JSON 문자열과 숫자도 허용 alias/상수 및 유한 숫자인지 확인한다. 비식별 입력이 64,000 bytes를 넘으면 예약·API 호출 전에 차단한다.

기본적으로 좌표도 전송하지 않는다. 운영자가 승인 catalog의 모든 위치가 가상임을 검토하고 `allowFictionalLocations: true`를 설정한 경우에만 가상 평면 좌표와 후보를 전송한다. `fictional: true`만 믿고 실제 주소·위치를 사용하지 않는다. 알려진 가상 fixture 외의 좌표를 새로 추측하거나 주소를 지오코딩하지 않는다.

AI 응답에서 원래 ID, 알 수 없는 alias, 차량/시각 등 허용하지 않은 변경 필드를 거절한다. 외부의 자유 형식 추천 이유는 운영 응답에서 그대로 표시하지 않고 안전한 안내 및 서버 거리 계산 결과로 대체한다. 복원 후 기존 서버 검증으로 코스·이용자 누락/중복, 직원 근무/결근, 차량 정원/중복, 기존 배정 유지·거리/업무량 기준을 검증한다. 시각은 AI가 변경하지 않으며 순서와 충돌하면 B-2에서 재검토하고 최종 확정에서 차단한다.

추천 결과는 Firestore에 저장하지 않는다. 일정·결근·계정 문서도 수정하지 않는다. 실제 API를 시도한 요청의 식별 해시·상태·횟수만 새 내부 경로에 남긴다. 관리자 승인은 로컬 변경에 적용하는 단계이며 저장은 기존 `confirmSchedule`만 수행한다.

## 호출 횟수와 중복 방지

- 기본 프로젝트 하루 100회, 관리자 하루 20회, 간격 30초. 설정으로 낮출 수 있으며 상한을 넘는 설정은 거절한다.
- 일자는 한국 시간 자정을 기준으로 계산한다. Gemini 공급자 자체 quota의 일자/한도와 별개다.
- `_aiUsage/{한국날짜}`: 전체/관리자별 시도 횟수, 진행 예약. 동일 트랜잭션에서 검사·차감하므로 동시 요청으로 한도를 넘을 수 없다. 잘못된 사용량 기록은 차단한다.
- `_aiRequests/{SHA256(uid:requestId)}`: 입력 해시, 예약 상태, 일자, 만료 시각, 접수·종료 시각. UID와 requestId 원문이나 추천안은 저장하지 않는다.
- 예약 120초. `reserved → running → completed/failed/expired`. API는 트랜잭션 밖에서 호출하며, 일회성 running 전환 이후에만 실행한다.
- 같은 관리자·요청 ID는 입력 변경·실패·중단·시간 초과·예약 만료 후에도 재사용할 수 없다. 중단된 예약도 다시 열지 않는다. 이미 예약된 ID를 다시 받으면 `already-exists`로 안내한다. 결과는 저장하지 않으므로 재조회할 추천 원문은 없다.
- 오래된 예약은 이후 동일 ID 조회 시 expired로 표시된다. 별도 스케줄러가 없어도 시간 경과 후 새 ID를 접수할 수 있고, 오래된 완료가 새 요청의 잠금을 해제하지 않는다. 종료된 API 호출이 예약 만료 후 돌아오면 결과를 적용 대상으로 반환하지 않는다.
- **요청 문서에 TTL을 설정하거나 삭제하지 않는다.** 삭제하면 과거 ID의 중복 방지 근거가 사라진다. 사용량 문서를 수동 초기화하지 않는다.
- 보수적으로 예약 시 횟수를 사용하며 실패/만료도 환급하지 않는다. 함수 종료나 통신 장애 때 외부 API가 이미 처리했는지 확정할 수 없으므로 자동 재시도하지 않는다. 새 ID는 관리자의 새 요청이며 별도 비용이 발생할 수 있다. 외부 공급자의 과금/처리까지 정확히 한 번임을 보장하는 것은 아니다.

기존 Rules의 기본 거부 규칙이 새 내부 경로의 모든 클라이언트 읽기/쓰기를 차단한다. Admin SDK를 사용하는 서버/운영자만 관리한다. 관리자 앱도 설정·횟수를 직접 수정할 수 없다. Functions 로그에는 진단 ID·단계·경과 시간·안전한 코드만 기록한다. 입력·응답 원문·UID·비밀 키·예외 원문은 기록하지 않는다.

## App Check 준비와 제한

Callable의 `enforceAppCheck`는 false로 두었다. SDK가 검증한 `request.app`을 받아 서버 설정의 `requireAppCheck: true`일 때만 필수로 검사한다. 클라이언트 payload에 app을 넣어 우회할 수 없다.

이번에 실제 Web App Check 토큰 발급이나 Flutter App Check SDK 연결을 완료했다고 판단하지 않는다. 현재 Flutter에는 App Check 초기화를 추가하지 않았다. 운영자가 Firebase Console Web App Check 등록·도메인·provider 설정과 Flutter SDK 연결을 완료하고 실제 토큰이 서버에서 검증되는 것을 확인한 뒤에만 `requireAppCheck`를 true로 바꾼다. 그전에는 false를 유지한다. 기존 두 함수에는 App Check를 강제하지 않는다. [Firebase 공식 안내](https://firebase.google.com/docs/app-check/cloud-functions).

## 필요한 Firebase 설정 — 운영자가 향후 수행

1. Firebase와 Gemini 키 소유 프로젝트의 결제·quota 및 모델 접근을 확인한다. Secret Manager와 Gemini API가 필요하면 서비스 활성화 여부·비용을 직접 승인한다. 기존 Firebase Blaze 연결만으로 Gemini 접근까지 검증된 것은 아니다.
2. Secret Manager에 `GEMINI_API_KEY`를 등록한다. `suggestSchedule`에만 secret accessor가 연결되는 것을 확인한다. 키는 대화창·명령 인자·Git·Flutter 코드·dart-define에 넣지 않는다. Secret 등록은 CLI 대화형 입력을 사용한다. 모델은 현재 `gemini-3.8-flash`이며 접근/JSON 출력 지원은 실제 키로 별도 확인해야 한다. [Firebase Secret 안내](https://firebase.google.com/docs/functions/config-env).
3. 먼저 Console/Admin SDK로 `_aiControl/config`를 다음처럼 등록한다. 아직 mode는 off다. 이 신규 설정도 이번 작업에서는 실제 Firebase에 쓰지 않았다.

```json
{
  "mode": "off",
  "allowedAdminUids": [],
  "allowedCatalogVersions": [],
  "projectDailyLimit": 3,
  "adminDailyLimit": 2,
  "cooldownSeconds": 30,
  "requireAppCheck": false,
  "allowFictionalLocations": false
}
```

등록하지 않아도 off다. 테스트할 관리자 Auth UID와 현재 실제로 등록된 가상 catalog 버전을 검토한 뒤 두 allowlist에 직접 넣는다. 예시 문자열을 실제 UID/버전으로 착각하지 않는다. 기존 users·catalog·settings 포인터는 변경하지 않는다.

## 배포 및 제한적 실호출 절차 — 아직 실행하지 않음

새 PowerShell, 저장소 루트, Node.js 22/Flutter/Firebase CLI를 기준으로 한다. Emulator 환경 변수가 없는 셸에서 진행한다. 기존 시연 Emulator를 중지/삭제할 필요는 없다.

```powershell
flutter analyze
flutter test
node tools/verify-functions-build.cjs
firebase.cmd functions:secrets:set GEMINI_API_KEY --project senior-transport-app
firebase.cmd deploy --only functions:suggestSchedule --project senior-transport-app
firebase.cmd functions:list --project senior-transport-app
```

기존 두 함수는 선택 배포하지 않는다. Rules/Storage도 배포하지 않는다. 새 manifest의 Gemini 파라미터는 운영 AI를 위한 의도된 선언이며 Secret은 AI에만 연결된다. 전 codebase의 파라미터를 처리하는 CLI 특성상 이후 두 함수만 배포할 때도 등록된 AI Secret이 필요할 수 있다. 키 등록 전 predeploy 통과를 실제 Secret 준비 완료로 간주하지 않는다.

함수가 ACTIVE인지 확인한 후, 우선 mode off인 상태에서 테스트용 UI를 준비한다. 아래 빌드는 AI 버튼을 켤 뿐 서버의 off/승인 검사를 우회하지 않는다.

```powershell
powershell.exe -ExecutionPolicy Bypass -File tools/build-hosting.ps1 -EnableProductionAi
node tools/verify-hosting-build.cjs
firebase.cmd deploy --only hosting --project senior-transport-app
```

1. 관리자 가상 계정에서 mode off가 API 호출 전에 거절되는지 확인한다.
2. allowlist에 승인된 관리자·검토한 가상 catalog만 넣고 mode를 test로 전환한다. 다른 관리자·직원·다른 catalog는 외부 API 전에 거절되어야 한다.
3. 승인된 관리자가 가상 날짜의 추천을 **한 번** 요청한다. 정상 JSON·서버 검증·거리 설명·검토 화면을 확인하고, 취소해도 기존 일정과 버전이 바뀌지 않아야 한다.
4. `_aiRequests`, `_aiUsage`와 안전한 로그에서 접수/횟수/종료를 확인한다. AI Studio에서 실제 token 사용·과금을 별도 확인한다. 원문·사진·키를 로그로 확인하지 않는다.
5. 확인 후 mode를 off로 되돌린다. App Check와 비용·모델 검증이 완료되기 전 광범위하게 개방하지 않는다. 실제 확정 저장 테스트는 별도 승인을 받은 가상 날짜에서 기존 confirmSchedule 절차로만 수행한다.

일반 UI를 AI 버튼 없이 빌드할 때는 다음 기본 명령을 쓴다.

```powershell
powershell.exe -ExecutionPolicy Bypass -File tools/build-hosting.ps1
```

장애 시 mode를 off로 변경하고, 이미 실행 중인 요청은 완료 전 재승인 검사에서 거절된다. 이미 보낸 외부 API 요청의 비용까지 취소되지는 않는다. 기존 일정 기능과 서버 버전을 되돌리거나 출처 필드를 삭제하지 않는다.

## 비용과 남은 확인

비용 발생 지점은 Gemini token, Functions 실행/네트워크, Firestore 관리 문서 읽기·쓰기·저장, Secret Manager, 배포 Build/Artifact 저장이다. 모델의 출력 제한은 기존 8192 token, 외부 API 제한은 45초, 함수는 90초를 유지했다. 입력 bytes 제한이나 요청 횟수는 정확한 금액 상한이 아니다. 모델별 요율과 실제 token 사용량을 확인한다. 공급자 quota는 프로젝트 단위로 적용되며 앱의 한국 날짜별 제한과 별개다. [Gemini 요금](https://ai.google.dev/gemini-api/docs/pricing), [공급자 한도](https://ai.google.dev/gemini-api/docs/rate-limits).

처음에는 프로젝트 3회·관리자 2회처럼 작게 시작하고, 예산/사용량 알림과 앱 한도를 함께 사용한다. 실제 키·모델 응답, Secret 접근 IAM, 실제 Web App Check, 실사용 과금, 네트워크 지연은 모의 테스트로 검증되지 않는다. 본 테스트에서는 전부 외부 호출을 모의 응답으로 대체했다.

## 로컬 검증

- `flutter analyze`: 문제 없음.
- Flutter 전체 테스트 **230개 통과**. 고유 요청 ID와 기존 검토·오래된 결과 차단·시간 조정·확정·사진 UI 회귀 포함.
- Auth/Firestore/Functions Emulator 전체 **126개 통과**. 기존 114개와 운영 AI 정책 그룹/하위 테스트 12개를 포함한다. 20명/80명 fixture로 승인·비활성·App Check 선택 검사·가상 catalog·비식별화·금지 필드·읽기 전용 결과·영구 중복 방지·예약/실행 중단/만료·동시 한도·설정 취소·결근 변경·클라이언트 내부 경로 접근 거부를 확인했다. 모든 생성 응답은 모의 응답이다.
- 운영 manifest 검사 **VERIFIED**: 세 Callable, `GEMINI_API_KEY` Secret은 AI 한 함수에만 연결. 기존 두 함수의 Secret 연결 0. API 요청 0.
- AI opt-in release 빌드 및 Hosting 안전 검사 통과: fingerprint `6c56bec7e61871ba92bd29bc358470eda0269679e003d8b18d92e87f069072e1`.
- AI 기본 비활성 release 빌드 및 Hosting 안전 검사 통과: fingerprint `72099b0350d5aeca96eb5f3dc3798b24aea6689838279cf0f22ed42c5b48a933`. **현재 `build/web`은 이 기본 비활성 빌드다.**
- Hosting 빌드 안전 검사 테스트 **5개 통과**. `git diff --check` 통과.

Emulator는 기존 환경을 보존하고 별도 포트 Auth 9198, Firestore 8190, Functions 5102, hub 4412/logging 4512에서 실행했다. 임시 설정은 제거했고 기존 시연 데이터·snapshot은 삭제하거나 import하지 않았다. 작업 시작 전부터 있던 `.firebase/hosting.*.cache` 변경도 보존했다.

로그는 `.local-tools/production-ai-analyze.log`, `production-ai-flutter.log`, `production-ai-emulator-verified.log`, `production-ai-release-test-mode.log`, `production-ai-release-disabled.log`에 있다. 실제 키·Secret 접근·실제 API 성공·App Check 토큰·운영 통합/과금은 여전히 별도 확인 대상이다.
