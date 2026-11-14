# Flutter Web Firebase Hosting 준비

이 작업은 로컬 설정·빌드·검증이다. 실제 Hosting/Functions/Rules 배포, preview channel 배포, 사이트 생성, 운영 데이터 변경을 수행하지 않는다. 기본 사이트 목록 메타데이터만 읽어 `projects/senior-transport-app/sites/senior-transport-app`, `DEFAULT_SITE`, `https://senior-transport-app.web.app`을 확인했다. 실제 사이트의 기존 파일·릴리스는 변경하지 않았다.

## 설정과 보존 범위

`firebase.json`에 정적 Hosting만 추가했다.

- public: `build/web` (저장소 루트, functions, docs, lib를 제공하지 않음)
- SPA: 존재하지 않는 경로를 `index.html`로 rewrite. 기존 JS·이미지·manifest 파일은 정적 파일로 제공한다.
- rewrite와 헤더의 `regex: "^.*$"`는 공식 지원 RE2 정규식이다. 현재 Windows CLI의 glob 경로 구분자 문제를 피하고 루트·하위 URL에 동일하게 적용한다.
- Cache-Control: 모든 경로에 `no-cache, max-age=0, must-revalidate`. 현재 해시 없는 main.dart.js/부트스트랩이 이전 버전에 고정되지 않도록 재검증한다. 파일 저장 자체를 금지하거나 이미 열린 탭의 JS를 자동 교체한다는 뜻은 아니다.
- `X-Content-Type-Options: nosniff`.
- 숨김 파일·node_modules·소스맵·로그·개인 키/서비스 계정 파일 패턴을 업로드에서 제외한다.
- Hosting 전용 `predeploy`는 `node tools/verify-hosting-build.cjs`로 검증된 빌드인지 확인한다. Functions/Rules 전용 배포에는 이 훅을 실행하지 않는다.
- 로컬 Hosting Emulator: 127.0.0.1:5000.

기존 flutter(FlutterFire), functions, firestore와 원래 Emulator 항목을 변경 전 JSON 사본과 비교해 값이 동일함을 확인했다. `lib/firebase_options.dart`, Firebase Authentication 공급자·역할 확인 코드, `web/index.html`, Functions/Rules 구현은 이번 작업에서 변경하지 않았다. `.firebaserc`는 추가하지 않고 모든 실제 배포 명령에 `--project senior-transport-app`을 명시한다. 별도 site/target을 지정하지 않아 해당 프로젝트의 기본 Hosting 사이트를 사용한다.

SPA 설정은 경로 새로고침/직접 접속 때 앱 진입 HTML을 전달하는 서버 설정이다. 현재 앱의 인증 게이트와 날짜 선택 정책을 유지한다. `/schedule/날짜` 같은 URL로 날짜·직원을 자동 선택하는 새 라우팅 기능을 추가한 것은 아니다. Hosting HTML은 공개 정적 파일이며 실제 일정 접근 권한은 기존 Auth·Rules·Functions가 담당한다.

설정 근거: [Firebase Hosting 구성](https://firebase.google.com/docs/hosting/full-config), [Flutter Web 배포](https://docs.flutter.dev/deployment/web).

## 실제 Firebase용 빌드와 배포 전 검사

프로젝트 루트에서 다음 스크립트를 사용한다. 로컬 빌드와 파일 검사만 실행하고 Firebase에 접속하지 않는다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build-hosting.ps1
```

내부 Flutter 명령은 다음과 같다.

```powershell
flutter build web --release --dart-define=USE_FIREBASE_EMULATORS=false --base-href /
```

`USE_FIREBASE_EMULATORS=false`는 `DefaultFirebaseOptions.currentPlatform`의 실제 `senior-transport-app`을 사용하며, Functions 리전은 기존 `asia-northeast3`다. `<base href="/">`는 Web 도메인 루트 제공에 맞춘다. `EMULATOR_HOST`나 Node용 환경 변수로 Flutter의 컴파일 상수를 대체할 수 없다. 기존 Authentication 계정은 그대로 사용하며 새 도메인의 브라우저 저장소가 다르면 기존 계정으로 다시 로그인할 수 있다.

스크립트는 배포에 쓰이지 않는 생성 메타데이터 `build/web/.last_build_id` 한 파일만 제거하고 산출물을 검사한다. 현재 Windows Hosting Emulator는 ignore 대상인 해당 파일을 로컬에서 제공할 수 있어 실제 업로드와 로컬 검증을 맞추기 위해 제거한다. 실제 Hosting에서도 숨김 파일 ignore 규칙은 유지한다. 소스·계정·일정 파일은 삭제하지 않는다.

`verify-hosting-build.cjs`는 다음을 검사한다.

1. public 경로, 필수 Flutter 파일과 루트 base href.
2. 실제 프로젝트 ID 포함, Emulator 프로젝트/키와 앱 debug 로그 marker 미포함.
3. 심볼릭 링크, 서버 소스 폴더·Dart/운영 스크립트·키 파일·서비스 계정 파일 이름 거부.
4. PEM 개인 키 본문, JSON 서비스 계정·private_key·refresh/access token·client_secret 값 검사. 값 자체는 로그로 출력하지 않는다.
5. Hosting 설정과 모든 산출물의 경로·크기·SHA-256으로 검증 기록 생성. 기록은 공개 디렉터리 밖의 `.local-tools/hosting/verified-build.json`에 둔다.
6. 배포 직전 같은 설정·파일인지 다시 확인. 기록이 없거나 빌드/설정이 바뀌었거나 Emulator/다른 프로젝트 환경이면 차단한다. Emulator 빌드가 build/web을 덮어쓴 뒤 그대로 배포하는 실수를 방지한다.

이 검사는 운영자 실수 방지용이며 서버 인증/권한을 대체하지 않는다. Firebase Web 설정의 apiKey·appId·projectId는 브라우저 SDK에 필요한 공개 식별 설정이다. 이를 서비스 계정 개인 키나 개발 계정 비밀번호처럼 취급해 추가하거나, 빌드 후 임의 치환하지 않는다. 현재 배포 소스에 개발용 비밀번호·서비스 계정 비밀키는 없다. 알려진 credential 형식 스캔 결과를 기록하며, 파일 내용 자체를 로그에 나열하지 않는다.

plain `flutter build web`만 실행해 검증 기록이 없거나 바뀌면 predeploy는 실패한다. 검사를 제거하지 말고 빌드 스크립트를 다시 실행한다. 검증 기록은 Git에 포함하지 않으며 새 PC/CI에서는 새로 생성한다. 미래에 Wasm/해시 파일명 빌드로 전환할 때는 현재 main.dart.js 기반 검사도 함께 검토해야 한다.

## 로컬 검증

```powershell
flutter analyze
flutter test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/test-hosting.ps1
```

검증 스크립트는 Node 빌드 검사 테스트와 `firebase emulators:exec --only hosting --project demo-senior-transport`만 실행한다. HTTP로 바이트를 받으며 실제 연결용 JavaScript를 브라우저에서 실행하거나 로그인하지 않는다. 따라서 실제 Auth/Firestore/Functions로 요청을 보내지 않는다.

HTTP 검사는 루트·index, 하위 직접 URL과 동일 URL 재요청, JS/manifest의 실제 파일 동일성·MIME·캐시/보안 헤더를 확인한다. 존재하지 않는 `/functions/index.js`, 숨김 생성 메타데이터 URL, 소스맵 URL은 SPA HTML이 반환되는지 확인한다. SPA 때문에 200 응답이어도 서버 소스나 비밀 파일을 제공한다는 뜻은 아니다.

최종 검증 결과:

| 항목 | 결과 |
|---|---|
| 실제 Firebase용 release 빌드 + 산출물 검사 | 성공, 준비된 파일 38개, 키/서비스 계정/토큰 미검출 |
| 실제 CLI 업로더의 로컬 파일 열거 | 38개, 숨김 파일·소스맵 제외 확인. 업로드 함수는 호출하지 않음 |
| 빌드 보호 Node 테스트 | 5개 모두 통과 |
| demo Hosting Emulator | 10개 HTTP 검사 모두 통과, 종료 후 Emulator 자동 종료 |
| `flutter analyze` | No issues found |
| `flutter test` | 기존 122개 모두 통과 |
| 기존 Firebase 설정 값 비교 / `git diff --check` | 통과 |

검증 기록과 파일별 해시는 Git 제외 `.local-tools/hosting/verified-build.json`, 실제 업로더 파일 목록은 `publish-files.json`, 로그는 `hosting-tests.log`와 `flutter-tests.log`이다. 산출물 검사와 HTTP 검증은 자격 증명 값을 로그에 출력하지 않는다. HTTP 테스트에서 앱 JavaScript 실행·원격 Firebase 요청은 0건이다. 실제 Firebase 서버를 통한 로그인·A-1/A-2 검증은 서버/Rules와 Hosting을 승인된 순서로 반영한 뒤 수행해야 한다.

## 승인 후 사용자가 실행할 배포 순서

아래는 **실제 배포 명령**이며 이번 작업에서 실행하지 않았다. 기존 일정·계정을 보존하고 관리자 변경을 동결한 상태에서 [A-1/A-2 점검 문서](firebase-a1-a2-deployment-checklist.md)의 백업·비용·권한 확인을 먼저 완료한다. 전체 firebase deploy, init, --force, seed/import 명령은 사용하지 않는다.

```powershell
# 1. 결근 검증·기존 일정 보존을 포함하는 서버를 먼저 갱신
firebase.cmd deploy --only functions:confirmSchedule --project senior-transport-app
firebase.cmd functions:list --project senior-transport-app

# 2. 관리자 결근 API 배포
firebase.cmd deploy --only functions:setStaffAbsence --project senior-transport-app
firebase.cmd functions:list --project senior-transport-app

# 3. 결근 조회 권한 게시
firebase.cmd deploy --only firestore:rules --project senior-transport-app

# 4. 실제 연결용 release 빌드와 검증 기록 생성
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build-hosting.ps1

# 5. 기본 사이트가 의도한 대상인지 확인 후 Hosting만 배포
firebase.cmd hosting:sites:list --project senior-transport-app
firebase.cmd deploy --only hosting --project senior-transport-app
```

각 단계 성공과 예상한 리전/설정을 확인한 후 다음 단계로 진행한다. 배포 명령 터미널에는 `GCLOUD_PROJECT`가 다른 프로젝트로 설정되어 있거나 `FIRESTORE_EMULATOR_HOST`, `FIREBASE_AUTH_EMULATOR_HOST`, `FIREBASE_EMULATOR_HUB`가 남아 있지 않게 한다. 로컬 Emulator 테스트 스크립트는 자식 프로세스 환경만 사용한다. Node 22와 로그인된 기존 Firebase CLI 운영자를 사용한다. Hosting predeploy에서 프로젝트·파일 검증이 실패하면 업로드를 진행하지 않는다.

이번에 확인한 기본 URL은 `https://senior-transport-app.web.app`이며 기본 `firebaseapp.com` 도메인과 사용자 지정 도메인 설정은 Console에서 확인한다. Firebase Authentication의 이메일/비밀번호 공급자와 해당 Hosting 도메인의 Authorized domains 상태도 확인하되 기존 설정을 재생성하지 않는다. 유료 기능·App Check 강제 활성화·추가 사이트 생성은 자동 수행하지 않는다.

**서버 두 함수와 Rules가 먼저 준비되지 않은 상태에서 새 Web 앱만 게시하지 않는다.** 기존 함수는 새 결근 버전 필드를 거부하거나 결근을 검사하지 않을 수 있고, 이전 Rules는 새 조회를 거부한다. 첫 결근 등록 전에 관리자와 직원의 기존 탭/PWA를 종료하고 새 버전으로 재접속한다. 열린 앱의 편집 초안은 먼저 정리한다. 캐시 헤더만으로 열린 구버전 앱이 갱신되었다고 판단하지 않는다.

배포 후에는 루트/직접 경로 새로고침, 정적 파일 로드, 기존 관리자·직원 로그인/복원/로그아웃, 결근 없는 날짜 조회, A-1 등록/취소, A-2 초안/요약/확정·직원 조회와 다른 날짜 보존을 승인된 가상 테스트 날짜에서 확인한다. 사용자 계정을 다시 만들지 않는다.

문제 발생 시 관리자 쓰기를 중지하고 게시된 두 함수·Rules·Web 산출물의 버전을 비교한다. 새 결근이 존재하면 결근을 모르는 이전 Web/confirmSchedule로 단순 롤백하지 않는다. 검증된 A-1 보호를 유지한 수정 버전으로 복구하고, 필요 시 이전 안전한 Hosting 릴리스를 Console에서 선택하되 서버와의 호환성을 먼저 확인한다. Hosting 롤백은 Firestore나 계정 데이터를 되돌리지 않는다. 조회 실패를 무시하거나 Rules를 전면 허용하는 방식으로 해결하지 않는다.

## 변경 파일

| 파일 | 변경 |
|---|---|
| `firebase.json` | Hosting public/SPA/헤더/ignore/predeploy, 로컬 Hosting 포트 |
| `tools/build-hosting.ps1` | 실제 Firebase용 release 준비, 생성 메타데이터 한 파일 제외, 검증 기록 |
| `tools/verify-hosting-build.cjs` | 공개 산출물 검사와 Hosting 전용 배포 전 검증 |
| `tools/test/hosting-build.test.cjs` | 다른 프로젝트·Emulator·변조·개인 키/토큰·불완전 빌드 거부 테스트 |
| `tools/test-hosting.ps1`, `tools/test-hosting-http.cjs` | demo Hosting Emulator의 실제 HTTP 응답 검증 |
| `docs/firebase-hosting.md`, `docs/firebase-a1-a2-deployment-checklist.md` | Hosting 절차와 기존 배포 안내 갱신 |
