# 운영 포인터를 바꾸지 않는 가상 catalog 미리보기

2026-11-14 로컬 구현. 사용자가 `ai-test-25x80-v1` 실제 등록과 검증 완료를 알려준 후, 이 버전을 기존 운영 데이터와 섞지 않고 검토하는 경로를 추가했다. **이번 작업에서는 실제 Firebase 조회/변경·일정 확정·외부 Gemini 호출·추가 배포를 하지 않았다.**

## 기존 흐름과 선택한 방법

기존 관리자 조회는 `schedules/{날짜}_{시간대}`, 직원 조회는 본인의 `staffSchedules/{staffId}/days/{날짜}_{시간대}`를 읽는다. 확정 문서가 있으면 그 문서의 `catalogVersion`, 없으면 `settings/schedules.catalogVersion`을 사용한다. 기본 코스에서 날짜·시간대별 변경 중 일정을 생성하고 `confirmSchedule`에서 전체를 검증·저장한다. 직원 화면은 확정된 본인 조회 문서만 사용한다.

기존 AI도 요청 버전이 선택한 확정 일정 또는 기본 포인터와 같아야 한다. 따라서 새 버전을 드롭다운에 넣기만 하거나 기존 포인터를 몰래 변경하는 방식은 사용하지 않았다.

대신 **저장 기능 없는 관리자 전용 미리보기**를 별도 화면·저장소 인스턴스로 만들었다. 정상 운영 컨트롤러와 선택 날짜·변경사항을 공유하지 않는다. 새 Firestore 컬렉션·테스트 일정 저장 구조·Rules는 추가하지 않았다. 이 단계에서 테스트 일정을 서버에 확정하는 기능은 제공하지 않는다. 실제 일정 확정은 기존 운영 화면의 별도 절차이며 미리보기 결과를 자동 전달하는 기능도 없다.

## 화면과 데이터

- 명시적인 빌드 옵션이 있을 때만 관리자 상단에 **AI 테스트**가 나타난다. 직원에게는 제공하지 않는다.
- catalog 선택은 임의 버전 입력이 아닌 고정 `ai-test-25x80-v1`이다. 메타데이터·네 하위 컬렉션만 서버에서 직접 읽으며 `settings`, 운영 일정, 실제 결근 기록을 가져오지 않는다. 실패하면 기존 catalog나 메모리 가상 데이터로 대체하지 않는다.
- 직원 25명/이용자 80명/차량 20대/정원 4명/오전·오후 각 20코스를 검증한다. metadata의 명시적인 담당 20명·예비 5명 목록을 사용하며, Firestore 문서 조회 순서나 이름·번호로 역할을 추정하지 않는다. 예비 직원 이름은 접힌 안내에서 확인할 수 있다.
- 기존 검색·직원별 상세 편집·이용자 결석/제외·방문 순서·코스 인계·B-1/B-2를 재사용한다. 기존 날짜·오전/오후 자동 선택도 유지한다. 날짜를 바꿔도 운영 일정은 조회하지 않고 해당 날짜·시간대의 독립적인 메모리 변경사항으로 취급한다.
- 테스트 상황은 정상/이용자 결석/방문 순서 개선/교차 배정과 결석 후 이동/직원 1·5·6명 결근의 7개다. 상황 변경에는 현재 변경사항을 버리는 확인이 있다. 실제 결근 저장 버튼·사진 기능·일정 확정 버튼은 제공하지 않는다.
- 결근은 선택한 테스트 상황으로만 재현한다. 실제 `staffAvailability`에 저장하지 않는다. 6명 결근 시 가용 직원 19명으로 20코스가 불가능하므로 UI와 서버에서 **Gemini 생성·호출 횟수 예약 이전에** 차단한다.
- **AI 추천 검토 → 명시적 적용 → 시간 확인**은 기존 흐름이다. 변경이 없으면 억지로 적용하지 않는다. 시각·수동 입력 출처는 보호한다. 저장은 UI뿐 아니라 컨트롤러와 저장소에서도 차단한다.
- 미리보기 화면을 나가면 그 컨트롤러를 폐기한다. 기존 운영 화면의 catalog·날짜·원래 편집 내용은 그대로 남는다. 새로고침에 테스트 변경사항이 유지된다고 표시하지 않는다.

## 서버 테스트 문맥

기존 `suggestSchedule`에만 선택적인 `previewContext` 입력/응답을 추가했다. 새 Callable·Secret은 없다. 일반 요청은 이 필드가 없으며 기존 버전·실제 결근 검사 경로를 그대로 사용한다.

```json
{
  "kind": "ai25-catalog-preview",
  "scenario": "staff-absence",
  "manifestSha256": "1d9288075fc24a9f6c806f88eaa941b3bc535cc92a43de0c07c132e9034be38c"
}
```

명시적 미리보기 요청에서만 다음을 적용한다.

1. 입력의 고정 버전·종류·7개 scenario·해시·`expectedVersion:0`을 검사한다. 임의 catalog·결근 ID·추가 필드·실제 확정 버전은 허용하지 않는다.
2. 운영 경로의 기존 active 관리자, `_aiControl/config` 테스트 모드/승인 UID·catalog, 선택적 App Check를 먼저 검사한다. 일반 관리자 권한만으로 AI 승인을 대신하지 않는다.
3. 서버가 원본 catalog와 metadata를 다시 읽고 **전체 내용의 해시를 재계산**한다. 등록된 고정 manifest와 같아야 한다. 실제 설정·일정·결근 문서는 읽지 않는다.
4. metadata 담당 직원 목록과 선택한 시나리오로 가상 결근 및 버전 0/1을 서버에서 도출한다. 클라이언트가 보낸 25명분 버전과 정확히 일치해야 한다. 실제 근무 기록을 우회하는 것이 아니라 서버에 저장하지 않는 별도의 가상 입력이다.
5. 기존 추천 엔진의 직원 가용성·중복·차량·정원·이용자 누락/중복·거리/업무량·시각 재검토를 그대로 적용한다. 비식별 임시 ID 변환, 가상 좌표 opt-in, 트랜잭션 호출 제한·요청 ID 중복 방지도 동일하다. `previewContext`나 해시는 외부 Gemini 입력에 전달하지 않는다.
6. 응답 전 catalog·권한을 다시 읽어 변화를 거절한다. 응답에도 같은 previewContext를 넣고 Flutter에서 확인한다. 요청 중 날짜/초안/상황/결근 버전이 바뀌면 기존 오래된 결과 차단을 사용한다.

미리보기 AI도 실제로 실행하면 기존 `_aiUsage`, `_aiRequests` 관리 기록은 생성된다. 운영 AI와 같은 프로젝트/관리자별 한도를 공유하므로 이미 오늘 한도를 소모했다면 추가 테스트도 거절된다. 기록을 초기화하거나 삭제해 우회하지 않는다. 일정·직원 조회·실제 결근·포인터·사용자·운영 제어 설정은 수정하지 않는다. 이는 호출 제한을 유지하기 위한 기존 동작이며 테스트 일정 저장이 아니다.

`confirmSchedule`은 previewContext가 들어간 요청을 기존 허용 필드 검사에서 거절한다. 클라이언트 미리보기 저장소는 publish/확정 확인/결근 저장 메서드를 모두 거절하고 컨트롤러도 호출 전에 차단한다. 일반 운영 화면의 confirmSchedule·setStaffAbsence 및 Rules는 변경하지 않았다.

## 실제 Firebase에서 먼저 조회·편집만 확인하는 절차

**현재 배포된 suggestSchedule은 새 previewContext를 지원하지 않는다. 이번에는 배포하지 않았다.** 먼저 AI 요청이 꺼진 상태에서 로컬 Flutter Web만 실행한다. 이 명령은 사용자가 향후 실행할 안내이며 이번 작업에서는 실행하지 않았다.

```powershell
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=false --dart-define=ENABLE_AI_CATALOG_PREVIEW=true --dart-define=ENABLE_PRODUCTION_AI=false --dart-define=ENABLE_AI_CATALOG_PREVIEW_REQUESTS=false
```

1. 기존 active 관리자 계정으로 로그인하고 **AI 테스트**를 연다. 기존 직원 화면/계정은 바꾸지 않는다.
2. 상단 테스트 표시와 25/80/20·담당 20·예비 5를 확인한다. 정상·결석·순서·코스 이동·직원 결근 상황을 바꾸며 선택한 날짜/오전·오후를 확인한다.
3. 검색·상세·인계·방문 시간 검토는 이 화면 안에서만 수행한다. 실제 결근 등록/일정 확정 버튼이 없어야 한다. AI 요청 버튼도 비활성 설정에서는 표시하지 않는다.
4. 화면을 닫아 기존 deploy-test-v2 화면과 선택/변경사항이 유지되는지 확인한다. catalog 포인터를 바꾸거나 테스트 일정을 미리 서버에 등록할 필요가 없다.

이 단계는 인증·catalog 읽기만 발생하며 Gemini를 호출하지 않는다. 일반 운영 화면의 읽기 구독은 기존대로 유지되지만 테스트 화면이 그 변경사항을 공유하거나 저장하지 않는다.

## 향후 실제 AI 검증에 추가로 필요한 절차

실호출은 이번 범위에서 수행하지 않았다. 기존 운영 함수를 그대로 둔 상태에서 새로운 미리보기 요청이 성공한다고 판단하면 안 된다. 별도 배포 승인 후 다음 단계를 진행한다.

1. 로컬 manifest 검사와 전체 테스트 결과를 확인하고 **suggestSchedule만** 새 문맥 지원 버전으로 배포한다. 기존 두 함수/Rules/Storage를 함께 배포하지 않는다. 이 작업에서는 실행하지 않았다.

```powershell
node tools/verify-functions-build.cjs
firebase.cmd deploy --only functions:suggestSchedule --project senior-transport-app
```

2. 운영자가 `_aiControl/config`의 mode/test 승인 관리자·`allowedCatalogVersions` 문자열 배열에 새 버전을 허용한다. 호출 한도는 전체/관리자 각각 1처럼 작게 둔다. 실제 UID·catalog가 맞는지 검토하고 기존 기록을 삭제하지 않는다. 이 설정 변경도 이번에는 수행하지 않았다.
3. Secret·모델·권한은 기존 운영 AI 설정을 사용한다. App Check는 실제 토큰 확인 전 강제하지 않는다. 가상 좌표 활용은 기존 `allowFictionalLocations` 정책을 따른다.
4. 승인된 후에만 아래 세 AI 관련 옵션을 명시적으로 켠다. 선택한 가상 상황에서 추천 버튼을 한 번 누르고 결과를 검토한다. 자동 호출·재시도는 없다.

```powershell
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=false --dart-define=ENABLE_AI_CATALOG_PREVIEW=true --dart-define=ENABLE_PRODUCTION_AI=true --dart-define=ENABLE_AI_CATALOG_PREVIEW_REQUESTS=true
```

5. AI 결과 적용도 미리보기 메모리에만 반영된다. 테스트를 종료하고 기존 운영 제어 정책에 따라 AI를 off로 되돌린다. 실제 일정 확정이나 운영 화면으로의 자동 복사는 제공하지 않는다.

미리보기의 메타데이터/가상 결근 검사는 **새로운 테스트 입력 API 계약**이며, 운영의 포인터 일치 검사를 완화한 것이 아니다. 서버 검증이 없는 단순 client-side catalog override·직접 Firestore 쓰기·가짜 Emulator 환경값으로 해결하지 않았다.

## 변경 파일과 검증

- `lib/services/catalog_preview_repository.dart`: 고정 catalog 읽기, 메모리 상황/결근, 쓰기 차단.
- `lib/screens/catalog_preview_screen.dart`: 별도 테스트 화면·상황 선택·명시적 초기화·예비 직원 구분.
- `auth_gate.dart`, `schedule_screen.dart`, `admin_schedule_view.dart`: 관리자 opt-in 진입, 테스트 안내, 확정/실제 결근 버튼 제외.
- `schedule_repository.dart`, `schedule_controller.dart`: scope 표시·메모리 초기 입력·추천 문맥 확인·컨트롤러 저장 차단. 일반 운영 동작은 유지.
- `functions/catalog-preview-context.js`: 고정 manifest·역할·시나리오·버전/내용 재검증. tools 폴더를 서버 소스에서 참조하지 않는다.
- `functions/suggestion-service.js`, `production-ai-service.js`: 새 scope에서만 테스트 context reader 사용. 기존 Secret·quota·비식별화·일반 context는 유지.
- `test/catalog_preview_test.dart`, `functions/test/catalog-preview.test.cjs`: 새 UI·서버 회귀.

검증 결과:

- `flutter analyze`: 문제 없음.
- Flutter 전체 **242개 통과**. 320×568/390×844/1280×900, 원래 운영 화면 복귀, 7개 입력 재현, 예비 직원 순서, 권한/쓰기 차단, 명시적 AI 적용·B-2·오래된 결과·응답 scope 확인을 검증했다.
- Auth/Firestore/Functions Emulator 전체 **163개 통과**(기존 149개 + 새 테스트 14개). 운영 포인터·확정 일정·직원 조회·사용자·실제 결근 sentinel을 보존하고, 테스트 요청 중 이 경로를 읽으려 해도 실패하도록 spy로 검사했다. 생성 결과는 모두 고정 모의 응답이다.
- 운영 Functions manifest 검사 통과. 새 함수나 Secret 연결을 추가하지 않았다.
- 실제 Firebase용 Web release와 Hosting 파일 안전 검사 통과. 현재 `build/web`은 미리보기 진입만 켜고 AI 요청은 끈 빌드다. fingerprint: `0f2fd4a9fe976bfc6fcd3bfc965199fc37e648b33c2d7fdbad808bf6ca753daa`. 기존 운영 화면의 명시적 확정 기능은 유지하며 테스트 화면에서만 저장을 차단한다. Hosting 배포는 하지 않았다.
- `git diff --check` 통과.
- 실제 Firebase·외부 Gemini·배포 작업은 수행하지 않았다. 기존 Emulator와 snapshot은 보존하고 새 demo namespace와 포트 9198/8190/5102에서 검사했다.

로그: `.local-tools/catalog-preview-analyze-final.log`, `catalog-preview-flutter-verified.log`, `catalog-preview-emulator-verified.log`, `catalog-preview-web-final.log`. 첫 Flutter 실행에서 발견한 작은 화면 공간 문제는 테스트 안내를 접고 높이를 제한해 수정했다. 초기 스타일 경고도 정리했다.

후속 병렬 Emulator 재실행에서는 기존 동시 HTTP 테스트의 fetch 응답 대기와 종속 테스트 취소가 발생했다. 이후 로컬 테스트 실행기를 파일 단위 직렬·검사 시간 제한 180초로 구성해 전체를 다시 검증했다. 개별 테스트의 동시 요청·동시 수정 검사는 그대로 실행하며 생략하지 않는다. 실제 Functions/API 제한 시간·모델이나 업무 검증 규칙은 바꾸지 않았다. 병렬 실행의 불안정성은 별도 테스트 환경 한계다.
