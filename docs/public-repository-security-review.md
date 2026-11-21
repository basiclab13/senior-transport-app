# Public 전환 전 보안 점검 보고서

검사일: 2026-11-16 (한국 시간). 검사 대상은 이 작업 폴더와 그 안의 로컬 Git 객체입니다. 비밀정보의 값, 사용자 UID, 실제 이메일 주소는 이 보고서에 기록하지 않았습니다.

## 후속 로컬 보안 정리 (2026-11-16)

이번 후속 작업에서는 `.gitignore`와 이 보고서만 수정했습니다. 아래 최초 점검의 S-01~S-06 및 원격·운영 설정의 미확인 항목은 계속 유효하며, **최종 판정은 공개 보류로 유지**합니다. 제외 규칙 보완은 이미 저장된 키의 폐기나 과거 Git 객체 제거를 대신하지 않습니다.

### 보완한 제외 규칙

| 구분 | 보완 내용 |
| --- | --- |
| 환경변수·Secret | 모든 폴더의 `.env`, `.env.*`, `.secret`, `.secret.*`, `.secrets/`, `.credentials/` 제외 |
| 공유 예제 | `.env.example`, `.env.sample`, `.env.template`만 예외 허용. 반드시 실제 값 없이 작성해야 함 |
| 검토된 기존 설정 | `functions/.env.senior-transport-app`은 명시적 예외 유지. 현재 필드는 `GEMINI_MODEL`, `WORK_PHOTO_BUCKET`뿐이며 인증 비밀정보가 아님 |
| 서비스 계정·OAuth | 서비스 계정 관련 파일명, Firebase Admin SDK 키 파일명, ADC, `credentials.json`, OAuth client secret 파일 제외 |
| 인증 저장소 | `.git-credentials`, `.gitcookies`, `.netrc`, `.npmrc`, `.pypirc`, 로컬 AWS·GCloud·SSH 폴더 제외 |
| 비공개 키·서명 | PEM, KEY, P12, PFX, JKS, keystore, `key.properties` 제외 |
| Firebase 로컬 자료 | `.firebase/` 및 Auth·Firestore·Storage 내보내기 폴더·메타데이터 제외 |
| 브라우저 | 이름이 `chrome-profile`, `chrome-device`, `chromium-profile`, `browser-profile`로 시작하는 프로필 폴더 제외 |
| Flutter 임시 자료 | 기존 `.dart_tool/`·빌드 제외 유지, 구형 플러그인 임시 목록과 플랫폼별 ephemeral·로컬 환경 생성 파일 제외 |

Firebase 공개 설정 파일, 가상 fixture JSON, 패키지 잠금 파일, 정상 플러그인 등록 소스는 무조건 제외하거나 삭제하지 않았습니다. 기존 `lib/firebase_options.dart`, `android/app/google-services.json`, `functions/.env.senior-transport-app`은 여전히 추적 중입니다. 공개 Firebase 키의 Google Cloud API 제한은 별도로 확인해야 합니다.

파일 이름이 임의로 지어진 서비스 계정 JSON, 소스에 직접 쓴 키, 예제 파일에 넣은 진짜 비밀번호까지 `.gitignore`가 내용으로 판별하는 것은 아닙니다. 허용된 설정·예제 파일도 변경할 때마다 내용 검토가 필요합니다. `git add -f`, 제외 파일까지 보관하는 `git stash --all`, 전체 폴더 ZIP은 이 보호를 우회할 수 있습니다.

### 재검사 결과와 공유 후보

| 항목 | 결과 |
| --- | --- |
| 추적 중인 파일 | 334개. 민감한 stash 파일·Chrome 프로필은 현재 추적 파일 목록에 없음 |
| 일반 미추적 파일 | 이 보고서 1개. 실제 키 파일은 새로 일반 미추적 목록에 나타나지 않음 |
| 이번 변경 파일 | `.gitignore`, `docs/public-repository-security-review.md` 두 개 |
| Git 추가 상태 | staged 파일 0개. `git add`, commit, push 미실행 |
| 전체 공유 후보 검사 | 기존 추적 334개 + 보고서 1개, 총 335개 파일의 내용·경로 재검사 |
| 고위험 패턴 | Gemini 인증키, GitHub/OAuth 토큰, JWT, 완전한 PEM 비공개 키, 서비스 계정 JSON 패턴 미검출 |
| 일반 Git 이력 | 14개 커밋에서 고유 파일 내용 객체 508개 재검사. 위 고위험 패턴 및 공개 Firebase 설정 밖의 Google 키 패턴 미검출 |
| `.gitignore` 동작 | 제외돼야 하는 경로 54개, 유지돼야 하는 경로 17개, 총 71개 확인 통과. 실제 비밀파일을 만들거나 Git에 추가하지 않고 가상 경로를 검사함 |
| 형식 검사 | `git diff --check` 통과 |

공유 후보의 위치별 개수는 다음과 같습니다. **이는 지금 모든 파일을 Commit·Push하라는 승인이 아니라 검사한 목록의 요약**입니다. 현재 공유 후보와 과거 커밋 공개 위험도 구분해야 합니다.

| 위치 | 파일 수 | 위치 | 파일 수 |
| --- | ---: | --- | ---: |
| 최상위 | 11 | `.firebase/` | 1 |
| `.github/` | 3 | `android/` | 20 |
| `docs/` | 60 | `functions/` | 36 |
| `ios/` | 40 | `lib/` | 47 |
| `linux/` | 10 | `macos/` | 28 |
| `test/` | 30 | `tools/` | 24 |
| `web/` | 7 | `windows/` | 18 |

이미 추적 중인 `.firebase/hosting.YnVpbGRcd2Vi.cache` 1개는 이제 제외 규칙에도 해당하지만 **계속 추적 중**입니다. 확인한 내용에서는 비밀정보가 발견되지 않았으며, 이번 범위에서는 Git 인덱스에서 제거하지 않았습니다. 향후 필요하면 담당자가 별도 승인 후 추적 해제를 검토합니다. 제외 규칙에 들어갔다고 현재 업로드 후보에서 자동으로 빠진 것으로 판단하면 안 됩니다.

### 민감 기록의 GitHub 전송 여부

- 민감 커밋 `9f9a05bc4fda52a1bba56d8097c6fc76fa7210b6`을 포함하는 로컬 참조는 여전히 `refs/stash`뿐입니다. 일반 브랜치·태그·현재 로컬 `origin/*`에서는 연결되지 않습니다.
- 보고서에 기록한 `.dart_tool/chrome-device/`의 로그인 자료는 현재 추적되지 않으며, 일반 Git 이력 재검사에서도 해당 JWT 패턴은 발견되지 않았습니다. 원본 파일은 수정·삭제하지 않았습니다.
- `git ls-remote --heads --tags origin`으로 참조 변경 없는 조회를 시도했지만 원격 목록을 얻지 못했습니다. 네트워크·인증 등의 정확한 실패 원인을 단정하지 않습니다. 따라서 실제 GitHub의 현재 브랜치·태그 상태는 이번에도 미확인입니다.
- 로컬 원격 설정에는 개인 저장소의 `origin` 하나만 있습니다. Organization 저장소의 독립 기록은 확인하지 못했습니다.
- 정상 Push는 보통 로컬 stash·브라우저 폴더를 자동 전송하지 않지만, 과거 mirror Push, PR 전용 참조, 삭제된 원격 기록, ZIP·릴리스·Actions 첨부물까지 안전하다고 보장하지 않습니다.

### 여전히 수동으로 필요한 확인

1. 민감 stash의 키가 현재 사용 중인지·이미 폐기됐는지 담당자가 비공개로 확인합니다. 유출됐거나 전송 범위가 불명확하면 키 교체·폐기를 별도 작업으로 진행합니다.
2. 개인·Organization 저장소를 각각 별도 검사용 복제본에서 확인하고 브랜치·태그·PR·Actions·릴리스·첨부 자료 및 Secret scanning 결과를 확인합니다. 브라우저·stash가 포함된 폴더 ZIP은 공유하지 않습니다.
3. stash에 필요한 코드가 있다면 민감한 제외 파일과 분리하는 계획을 먼저 세웁니다. 이번에는 stash 삭제나 이력 재작성을 하지 않았으며, 정상 브랜치의 무조건적인 재작성도 권하지 않습니다.
4. 현재 추적된 호스팅 캐시와 커밋 작성자 이메일의 공개 여부를 검토합니다. 키·사용자 UID·토큰이 포함된 로그나 스크린샷을 확인 자료로 GitHub에 올리지 않습니다.
5. 배포된 Rules·버킷 IAM·Secret 접근 권한·Firebase 공개 키의 API 제한·AI와 사진 제어·비용 설정을 운영 담당자가 별도로 확인합니다.
6. 공개 직전 Desktop Changes에서 이번 수정 파일 두 개와 실제 diff를 확인하고, staged 파일 목록과 새 공개 대상 기록을 다시 검사합니다. 이후 Public 여부를 재판정합니다.

비밀정보가 들어 있는 파일, 앱 코드, Firebase 설정, Git 인덱스·기록·참조, stash, 브라우저 데이터는 수정하거나 추가하지 않았습니다. 키 폐기, 계정 변경, Firebase/Gemini 호출·배포도 하지 않았습니다. 앱 코드 변경이 없어 Flutter 분석·테스트 대신 제외 규칙과 Git 공개 대상에 대한 검사를 수행했습니다.

## 최종 판정: 공개 보류

로컬 Git stash에 실제 Gemini 인증키 형태의 값이 남아 있습니다. 로컬 브라우저 저장소에는 운영 프로젝트 로그인 토큰 형태의 데이터도 있습니다. **일반 브랜치에 키가 올라간 것으로 확인된 것은 아닙니다.** 확인한 14개 일반 브랜치·원격 추적 브랜치·태그의 커밋 범위에서는 중대한 인증 비밀정보를 찾지 못했습니다.

그러나 키의 현재 유효성·폐기 여부, 개인 저장소와 Organization 저장소 양쪽의 실제 원격 기록, GitHub의 PR·Actions 기록, 배포된 Firebase 권한은 미확인입니다. 이 상태에서 두 저장소 모두 안전하게 공개할 수 있다고 단정하지 않습니다. 아래 필수 확인이 완료되면 다시 판정합니다. 로컬 stash가 존재한다는 이유만으로 정상 브랜치 전체를 재작성할 필요가 있다고 판단하지는 않습니다.

## 최초 점검 범위와 방법

| 대상 | 확인 결과 |
| --- | --- |
| 현재 추적 파일 | 334개. 검사 시작 시 수정 파일과 일반 미추적 파일 없음 |
| 현재 파일 내용 | `.git`을 제외한 1,616개 파일, 약 1.24GB. 제외된 캐시까지 두 번째 검사에서 포함 |
| 일반 브랜치·원격 추적 브랜치·태그 | 도달 가능한 커밋 14개, 누적 경로 342개 |
| stash와 로컬 객체까지 포함 | 커밋 17개, 고유 파일 내용 객체 10,596개, 약 866MB |
| 삭제된 과거 파일 | Git 객체에서 검사. 현재 파일만 검사하지 않음 |
| 도달 불가능한 파일 객체 | 로컬 객체 전체 목록에도 포함하여 패턴 검사. 경로·커밋이 연결되지 않는 객체는 완전한 맥락 확인 불가 |
| 커밋 메시지와 로컬 Git 설정 | 키·토큰·비공개 키·인증정보 포함 URL 패턴 검사 |
| 이미지 | 현재 추적 이미지 35개는 앱 아이콘·시작 이미지 경로. 일반 브랜치 과거 기록에서도 그 밖의 사진·스크린샷 경로 미발견 |
| 과거 비일반 기록의 이미지 | 비표준 이미지 객체 163개도 존재. 전체 화면·얼굴·문자에 대한 OCR/육안 검수는 하지 않음 |
| 실제 Firebase·Gemini·GitHub 서버 | 접속·호출·조회하지 않음. 공개 공식 문서만 참고 |

검사는 로컬 정규식·파일 구조·Git 도달 관계 확인과 서버 코드 정적 검토로 수행했습니다. 외부 스캐너에 파일을 보내지 않았습니다. Google/Gemini 키, GitHub/OAuth 토큰, JWT, 서비스 계정, PEM 비공개 키, 환경변수·비밀번호 대입, 인증정보 포함 URL, 개인 이메일·한국 휴대전화·주민번호 유사 패턴을 검사했습니다. 압축 파일 내부 전체 해제, 암호화된 브라우저 정보 복호화, 키 유효성 확인, 모든 임의 문자열의 비밀 여부 판별은 하지 않았습니다. 패턴 검사 무검출은 비밀정보가 절대 없다는 증명이 아닙니다.

검사 중간 결과와 검사 스크립트는 프로젝트 밖 임시 폴더에만 작성했습니다. 결과 파일에는 경로·행·객체 식별자·위험 유형만 남겼고 비밀정보 값은 저장하지 않았습니다. 프로젝트에서는 이 보고서만 추가했습니다.

## 발견 사항

### S-01. Gemini 인증키 형태의 값이 로컬 stash에 존재

- 심각도: **높음**. 키가 유효한 채 외부로 전송되면 서비스 사용과 비용 발생 위험이 있음.
- 위치: `functions/.secret.local:1`, 필드 `GEMINI_API_KEY`.
- 포함 커밋: `9f9a05bc4fda52a1bba56d8097c6fc76fa7210b6`.
- 연결된 stash 참조: `refs/stash`, 현재 끝 커밋 `dbe43e7d3e2f47c2eb5d826365fefa2addd11b38`.
- 위 포함 커밋은 현재 stash의 세 번째 부모로, 미추적·제외 파일을 보관한 부분임. 일반 작업 브랜치의 소스 커밋과 구분해야 함.
- 확인 내용: 공백·예제 표시가 아닌 인증키 형태의 값이 존재함. 실제 API에 보내 유효성을 시험하지 않았으며, 운영 Secret과 같은 키인지도 확인하지 않음.
- 공개 범위 구분: 해당 커밋은 현재 로컬 일반 브랜치·태그·`origin` 추적 브랜치에서는 도달하지 않음. 이 로컬 stash가 곧 GitHub 공개 기록이라는 뜻은 아님. 통상적인 브랜치 Push와 저장소 Public 전환이 로컬 stash를 자동 업로드하지 않음.
- 위험 경로: 저장소 폴더 통째 공유, `.git` 포함 ZIP 제출, stash를 다른 참조에 옮긴 Push, 모든 참조를 보내는 mirror Push 등에 주의. 다른 원격에 이미 보내졌는지는 별도 확인 필요.
- 권장 조치: 담당자가 해당 키의 사용·폐기 상태와 전송 이력을 확인. 노출됐거나 확인할 수 없다면 교체·폐기하고 기존 키 차단을 확인. 로컬 stash 정리는 필요한 작업을 안전하게 분리한 뒤 별도 승인으로 진행. 현재 브랜치 파일 삭제나 `.gitignore` 추가만으로 이 객체가 사라지지 않음.

### S-02. 로컬 브라우저의 운영 로그인 정보와 과거 개발 자료

- 심각도: **높음 — 로컬 폴더를 통째로 공유할 경우**.
- 현재 위치:
  - `.dart_tool/chrome-device/Default/Local Storage/leveldb/000003.log`
  - `.dart_tool/chrome-device/Default/Local Storage/leveldb/000004.log`
  - `.dart_tool/chrome-device/Default/Local Storage/leveldb/000005.ldb`
- 확인 내용: 운영 프로젝트를 대상으로 하는 서명된 Firebase JWT 형태가 중복 포함 총 37회 검출되고 `refreshToken` 필드도 존재함. 37명의 사용자 또는 37개의 서로 다른 토큰이라는 뜻은 아님. 서명·만료·갱신 가능 여부는 검증하지 않음. 토큰 안의 이메일·UID는 출력하지 않음.
- 현재 추적 여부: 위 파일은 Git 제외 대상이며 추적되지 않음. 검사한 Git 파일 객체에서는 같은 JWT 패턴을 찾지 못함. GitHub의 정상 브랜치 공개와 로컬 폴더 공유는 별개임.
- 과거 위치와 커밋: S-01의 `9f9a05bc4fda52a1bba56d8097c6fc76fa7210b6`에 `.local-tools/*/chrome-profile/`의 History, Cookies, Login Data, Local Storage, 세션 파일 및 `.emulator-data/operations-20x80-20261113/auth_export/accounts.json` 등이 포함됨.
- Emulator 내보내기에는 가상 이메일 계정 21개의 인증 관련 필드가 있음. 이메일은 모두 예제용 도메인이지만 비밀번호 해시 등 계정 정보를 공개할 이유는 없음. 브라우저 DB 파일의 존재만으로 유효한 운영 쿠키·비밀번호가 저장됐다고 단정하지 않음.
- `.local-tools/config/configstore/firebase-tools.json`도 과거 stash에 있었지만 확인한 내용은 빈 객체였음. 이 파일에서 Firebase CLI OAuth 토큰이 발견됐다고 판단하지 않음.
- 권장 조치: `.git`, `.dart_tool`, `.local-tools`, `.emulator-data`를 포함하는 전체 폴더 ZIP은 제출하지 않음. 실제 토큰·브라우저 자료가 외부로 전달됐다면 담당자가 해당 세션·갱신 토큰 폐기와 계정 보호를 검토. stash·캐시 정리는 이번 검사에서 수행하지 않음.

### S-03. `.gitignore`의 비밀파일 제외 범위가 제한적

- 심각도: **중간**.
- 위치: `.gitignore:49`~55 및 `.firebase/hosting.YnVpbGRcd2Vi.cache`.
- 현재 장점: `node_modules/`, `.dart_tool/`, `.local-tools/`, `.emulator-data/`, `build/`, 로그, `functions/.secret.local`, `functions/.env.local`을 제외함.
- 빈틈: 루트 또는 다른 폴더의 `.env`·다른 `.env.*`·`.secret.*`, 서비스 계정 JSON, ADC JSON, PEM·개인키·서명 키 파일에 대한 포괄적 제외가 없음. 호스팅 캐시도 현재 추적됨.
- 실제 발견과 구분: 이 빈틈을 통해 현재 서비스 계정이나 비공개 키가 추적되고 있다는 증거는 찾지 못함. 캐시 파일 자체에서도 인증 비밀정보는 찾지 못함.
- 권장 조치: 공개 전 실제 비밀파일 변형을 제외하도록 별도 수정하고 필요하다면 안전한 예제 파일만 예외로 허용. JSON 전체를 무조건 제외하지 않음. 이미 추적되거나 과거 객체에 들어간 파일에는 제외 규칙이 소급 적용되지 않으므로 재검사가 필요함.
- `functions/.env.senior-transport-app`은 예외적으로 의도된 추적 설정인지 담당자가 결정해야 함. 확인한 현재·과거 내용은 모델명과 버킷명으로, 비밀키 파일은 아님. 향후 Secret을 이 파일에 추가하지 않음.

### S-04. 커밋 작성자 이메일 노출

- 심각도: **낮음 / 개인정보 공개 여부 확인 필요**.
- 위치: 일반 공개 대상 커밋 14개 중 12개의 작성자 또는 커미터 메타데이터.
- 위험 이유: 개인 이메일 주소는 파일이 없어도 Git 기록으로 공개될 수 있음. 직원·어르신 개인정보가 발견됐다는 뜻은 아님.
- 권장 조치: 작성자에게 공개 동의를 확인하고 이후 커밋은 필요하면 GitHub 비공개 이메일을 사용. 과거 기록을 바꾸려면 팀 협의와 별도 승인 필요. 이번에는 이름·주소 출력 및 기록 수정을 하지 않음.

### S-05. 두 원격 저장소와 배포 환경에 대한 확인 공백

- 심각도: **높음 / 공개 판정 미확인 항목**.
- 위치: 로컬 `origin` 설정 및 외부 개인·Organization 저장소, 실제 Firebase/GCP 설정.
- 확인한 로컬 원격: 개인 저장소 `baek-jaekwang/senior-transport-app`의 `origin` 하나. Organization 원격은 이 로컬 설정에서 확인되지 않음.
- 제한: `origin/*`는 마지막 동기화 당시의 로컬 기록임. 현재 GitHub의 모든 브랜치·태그·PR 전용 참조·삭제된 브랜치·Actions 로그·Artifacts·Releases·과거 저장소 업로드 파일을 보장하지 않음. shallow 저장소는 아니지만 서버에만 있는 기록까지 포함하지는 않음.
- 권장 조치: 두 저장소를 각각 별도 검사용 복제본에서 확인하고 Secret scanning 결과, PR 첨부물, Actions 이력, 릴리스 파일, fork·팀원 복제본을 점검. GitHub 기본 브랜치 화면만 확인해서 끝내지 않음. 현재 작업 폴더의 fetch·참조·브랜치를 바꾸지 않기 위해 이번에는 원격 동기화를 하지 않음.

### S-06. 공개 후 호출 남용과 비용 방어 설정 확인 필요

- 심각도: **중간**, 실제 권한·한도 설정에 따라 달라짐.
- 위치: `functions/production-ai.js:10`, `functions/ai-request-policy.js:11`, `functions/work-photos.js:8`, `functions/work-photo-service.js:61`.
- AI에는 관리자 권한, 승인 UID·catalog, `mode: test`, 일별 한도, 대기시간, 중복 요청 방지가 있음. 그러나 함수 전반의 `enforceAppCheck`는 false이고 별도 제어 문서의 `requireAppCheck`를 통해 선택적으로 확인함. 실제 제어값은 읽지 않았음.
- 사진에는 인증·소유권·중복 등록·파일 크기 제한은 있으나 별도의 관리자별/직원별 호출량 제한은 확인되지 않음. `maxInstances`는 요청 수나 누적 비용을 완전히 차단하는 일일 한도가 아님.
- 권장 조치: AI 미사용 시 비활성 상태를 유지하고 최소 호출량을 운영자가 확인. App Check 토큰 발급을 검증한 뒤 필요 기능에 강제 적용을 검토. 등록 권한이 없는 계정 생성이나 반복 실패 요청도 비용·남용 관점에서 확인. 예산 알림을 비용의 자동 차단 장치로 간주하지 않음.
- 인증을 우회하거나 Rules를 완화할 필요는 없음. 코드 공개 자체가 기존 권한 정책을 바꾸지는 않지만 API 주소와 호출 형식은 공개된다고 가정해야 함.

## Firebase 공개 설정과 오탐 분류

| 위치/탐지 | 판단 |
| --- | --- |
| `lib/firebase_options.dart:44` 등 플랫폼 설정 | Firebase 클라이언트 공개 설정. 서비스 계정·관리자 비밀키와 다름 |
| `android/app/google-services.json:18` | Firebase 클라이언트 설정. 서비스 계정 JSON과 다름 |
| `functions/.env.senior-transport-app` | 현재·과거 확인 필드는 `GEMINI_MODEL`, `WORK_PHOTO_BUCKET`. 모델명·버킷명은 인증 비밀정보가 아님 |
| `docs/TEAM_GUIDE.md`의 Secret 예제 | 공백 차단값이며 실제 Gemini 키가 아님 |
| `tools/test/hosting-build.test.cjs:47`~58 | 유출 방지 검사를 위한 모의 자격증명과 PEM 시작 표시. 완전한 비공개 키로 판단하지 않음 |
| `functions/test/gemini-schedule.test.cjs` | 모의 fetch를 사용하는 단위 테스트의 키 자리값. 실제 키 형식 미검출 |
| `tools/test/prepare-operations-diagnostics.test.cjs` | 계정 생성에 쓰는 운영 비밀번호가 아니라 진단 테스트 입력 |
| 과거 포함된 의존성의 PEM·서비스 계정·이메일 문자열 | 파싱 코드, SDK 문서 예제, 제작자·라이선스 정보와 구분. 이 탐지만으로 실제 서비스 계정 유출로 판단하지 않음 |

현재 파일과 확인한 일반 브랜치 기록에서 실제 서비스 계정 JSON, 완전한 비공개 키, GitHub/OAuth 토큰 또는 실제 직원·어르신·보호자 연락처라고 식별되는 항목은 발견하지 못했습니다. 앱 데이터는 가상 fixture와 메타데이터를 사용하지만 자연스러운 이름·주소가 실제 사람과 무관하다는 최종 확인은 데이터 작성자가 해야 합니다.

Firebase 공개 키는 **Firebase 관련 API로만 제한됐다는 조건**에서 공개 가능한 설정입니다. 실제 Google Cloud 키 제한은 로컬 코드로 확인할 수 없습니다. 공개 Firebase 키에 Gemini/Generative Language API를 허용하지 않았는지 반드시 확인해야 합니다. Gemini 키는 별도 서버 Secret으로 유지해야 합니다. [Firebase 공식 API 키 보안 안내](https://firebase.google.com/docs/projects/api-keys), [Gemini 공식 키 관리 안내](https://ai.google.dev/gemini-api/docs/api-key).

## 서버 권한 정적 검토

| 기능 | 코드에서 확인한 보호 | 남은 확인 |
| --- | --- | --- |
| 사용자 역할 | `firestore.rules:19` 본인 문서 get만 가능, list/write 금지. 클라이언트의 관리자 생성·권한 변경 불가 | Auth 실제 로그인 공급자, 계정 관리·가입 허용 상태 |
| 일정·결근 | `schedule-service.js:26`, `staff-absence-service.js:43` 활성 관리자 서버 검사. 직접 클라이언트 write 금지, 버전·요청 식별자·트랜잭션 유지 | 배포된 함수·Rules와 로컬 동일 여부 |
| 직원 일정 | `firestore.rules:58` 본인 staffId와 확정 상태, 직원 활성 연결 확인. 서버 투영에는 담당 코스 자료만 포함 | 실제 users.staffId 연결·역할 관리 정확성 |
| AI | `production-ai.js:7` Secret은 서버 함수에만 연결. `ai-request-policy.js`에서 관리자·테스트 모드·허용 목록·트랜잭션 한도 검사. 만료돼도 같은 요청 ID는 재호출하지 않음 | 실제 Secret IAM·버전, 제어 문서, Gemini 측 API 한도 |
| AI 개인정보 | `ai-privacy.js:6` 허용 필드로 재구성, 임시 식별자로 치환. 이름·주소·원래 ID·사진을 전달하지 않음. 가상 좌표는 허용 설정에 따름 | 데이터가 실제로 가상인지, 호출 모델·관련 보관 정책 |
| AI 결과 | `suggestion-service.js`에서 직원·차량·정원·결근·누락·중복 재검증, 시간·입력 방식 보존. 일정 쓰기 없이 결과 반환. 최종 저장은 별도 confirmSchedule | 실제 배포 버전과 클라이언트 승인 흐름 |
| 사진 등록 | `work-photo-service.js:31`·61 본인 활성 직원, 오늘·확정 일정·결근·버전 검사, JPEG 재인코딩, 180KiB·400만 픽셀 제한, 업로드 뒤 재검사 | 버킷·전용 서비스 계정 IAM과 실제 제어 문서 |
| 사진 조회 | `work-photo-service.js:126` 활성 관리자 또는 본인 직원, 직원은 기록 UID도 확인. 파일 다운로드 후 재인증. 공개·서명 다운로드 URL 발급 코드 없음 | 버킷의 allUsers/allAuthenticatedUsers, 기존 URL·객체 ACL·IAM |
| Storage 직접 접근 | `storage.rules:5` 클라이언트 읽기·쓰기 전면 금지 | GCS IAM 공개 접근은 Rules와 별도로 확인 필요 |
| 내부 제어·사진 문서 | Firestore 최종 거부 규칙으로 `_aiControl`, 사용량, 요청, 운영 사진 기록의 직접 클라이언트 접근 차단 | Admin SDK는 Rules를 우회하므로 서버 IAM도 확인 |

정적 검토에서 다른 직원의 사진에 대한 직접 접근 우회, 일반 직원의 확정 권한 획득, 클라이언트의 Gemini 키 포함 경로는 확인하지 못했습니다. 침투 테스트나 실제 운영 권한 검증을 통과했다는 뜻은 아닙니다. 이번 작업에서는 Flutter·Emulator 테스트, 실제 사진 조회·등록, Gemini 호출을 하지 않았습니다.

## GitHub 공개·자동 배포 영향

- 현재 파일과 확인한 일반 브랜치 전체 기록에 `.github/workflows/` 파일은 없고 Issue 양식만 있습니다. 로컬 설정에서 GitHub Actions 자동 배포는 발견하지 못했습니다.
- `firebase.json`의 predeploy 검사는 CLI 배포 시 실행되는 검사이며 저장소 공개만으로 실행되는 배포 설정은 아닙니다.
- GitHub의 외부 앱, Firebase GitHub 연동, Cloud Build 트리거, 조직의 공통 워크플로, 저장소 Secrets·Environment 보호는 로컬 파일에 없을 수 있어 미확인입니다.
- 공개하면 누구나 소스와 공개된 과거 기록을 복사할 수 있습니다. 다시 Private으로 바꿔도 외부 복사본을 회수할 수 없습니다. Actions 과거 로그 공개 영향도 별도로 확인해야 합니다. [GitHub 공개 범위 변경 안내](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility).
- 비밀정보를 원격에 보낸 사실이 확인되면 키 폐기·교체를 먼저 합니다. 이후 두 저장소의 브랜치·태그·PR 참조·fork·캐시를 포함해 정리 범위를 결정합니다. 단순 파일 삭제 커밋으로 과거 내용이 없어지지 않습니다. [GitHub 민감정보 제거 안내](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository).

## Public 전환 전 필수 확인 순서

1. **공개·폴더 통째 제출을 우선 보류**합니다. 이 보고서는 키를 포함하지 않지만 원본 `.git`·브라우저 폴더를 첨부하지 않습니다.
2. **S-01 키 상태 확인**: 운영 담당자가 해당 키의 폐기 여부와 사용 위치를 비공개로 대조합니다. 유출·전송 범위가 불명확하면 교체·폐기하고 Secret 및 운영 함수 영향은 별도 승인 절차로 처리합니다. 이번 검사에서는 하지 않았습니다.
3. **양쪽 원격을 각각 검증**: 개인·Organization 저장소의 주소·전체 공개 대상 참조·PR·Actions·릴리스·첨부물을 별도 검사합니다. 민감 stash 커밋의 존재 여부를 확인합니다. 현재 `origin`에서 안 보인다는 사실을 Organization에도 그대로 적용하지 않습니다.
4. **Git과 로컬 공유 자료 정리 계획 확정**: stash 작업을 검토하고 필요한 소스만 분리합니다. 원격에 민감 커밋이 실제로 있을 때만 해당 원격의 기록 정리 범위를 협의합니다. 정상 브랜치의 불필요한 전면 재작성·무조건 force push는 하지 않습니다.
5. **제외 규칙 보완·재검사**: 실제 비밀파일·서명키·도구·내보내기 자료를 제외하고 이미 추적된 항목과 구분합니다. 커밋 작성자 이메일 공개 동의도 확인합니다.
6. **Firebase 담당자의 별도 확인**: 배포 Rules·함수, users 역할 관리, 버킷 IAM·공개 링크, Secret 접근 계정, 공개 Firebase 키의 API 제한, AI 비활성/한도, 사진 제어, App Check 적용 여부와 비용 경보를 확인합니다. 운영 문서나 UID·키 값을 GitHub에 첨부하지 않습니다.
7. **공개 대상의 새 검사용 복제본 재검사**: 코드·전체 공개 이력·빌드/릴리스 첨부물에서 같은 키·토큰·개인정보가 없는지 확인합니다. 과거 화면 캡처를 공개할 경우 별도 검수합니다.
8. 위 결과가 확인된 다음 학교 제출 대상 저장소만 Public으로 전환합니다. 나머지 개인·Organization 저장소도 자동으로 안전해진다고 가정하지 않습니다. 공개 직후 Secret scanning 경고와 예상 밖 호출·비용도 확인합니다.

## 최초 점검에서 수행하지 않은 작업

코드·설정·Rules·Auth·Git 커밋·브랜치·참조·stash·원격 설정을 변경하지 않았습니다. commit, push, fetch, 기록 재작성, Firebase 운영 데이터 조회·수정, 배포, IAM/Secret 변경, Gemini 실호출, 실제 사진 업로드를 하지 않았습니다. 이 보고서 추가 외 프로젝트 파일 변경은 없습니다.
