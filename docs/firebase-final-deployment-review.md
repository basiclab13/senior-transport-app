# 실제 Firebase 반영 전 최종 점검

점검일: 2026-11-14, 한국 시간. 대상: `senior-transport-app`.

후속 로컬 수정: 운영 진입점·AI Secret 분리를 구현했다. 아래 원격 비교는 **수정 전 읽기 전용 점검 당시의 실제 배포 상태**이며, 실제 Firebase는 갱신하지 않았다. 최신 구현·검증 결과·실행 절차는 [호환 배포 준비 결과](firebase-compatible-deployment.md)를 따른다.

## 판단

**최신 화면만 먼저 배포하지 않는다.** 실제 `confirmSchedule`은 B-1 방문 시각 출처 필드를 지원하기 전 버전이다. 최신 앱이 계산·직접 입력한 시각의 `estimatedVisitSources`를 보내면 기존 서버가 허용하지 않는 필드로 거절한다. 서버 호환성 반영이 먼저다.

AI 추천과 사진 등록은 현재 **Emulator 전용 기능**이다. 최신 Hosting 배포로 실제 환경에서 사용할 수 있게 되는 기능이 아니다. 두 기능을 실제 환경에 개방하는 작업은 이번 점검 범위에 포함하지 않았다.

이번 작업에서는 설정·소스 비교, 공개 정적 파일 GET, 로컬 빌드·테스트만 수행했다. 배포, 실제 함수 호출, 실제 Firestore 문서·Auth 계정 조회/변경, Secret 값 열람, 서비스 활성화, 결제 설정 변경은 하지 않았다.

## 실제 환경과 로컬의 차이

| 항목 | 실제 배포 상태 | 현재 로컬 및 영향 |
|---|---|---|
| Hosting | `2026-11-13 13:48:02 KST`, 버전 `e3b3ff7b5b5d0068`. 공개 페이지·manifest의 이름은 **다정 송영 관리** | 현재 이름은 **송영도우미**. 현재 release 빌드와 공개 `index.html`, manifest, JS의 해시가 다르다. 최신 UI가 배포되어 있다고 볼 수 없다 |
| `confirmSchedule` | v2 / Node.js 22 / `asia-northeast3`, ACTIVE. `2026-11-13 13:43:54 KST`, 제한 60초, 최대 인스턴스 2 | `schedule-service.js`는 로컬과 동일하지만 `validation.js`, `existing-schedule.js`, `index.js`가 다르다. 배포본의 허용 route 필드에 `estimatedVisitSources`가 없다 |
| `setStaffAbsence` | v2 / Node.js 22 / `asia-northeast3`, ACTIVE. `2026-11-13 13:46:00 KST`, 제한 60초, 최대 인스턴스 2 | 핵심 `staff-absence-service.js` 및 `schedule-service.js`는 동일. 공유 진입점과 검증 모듈은 다르다 |
| `suggestSchedule` | 배포 목록에 없음 | 로컬에만 존재. 클라이언트와 서버 모두 demo Emulator 여부를 검사한다. 로컬 제한 90초·최대 인스턴스 1·서버 Secret 사용 |
| Firestore Rules | `2026-11-13 13:46:24 KST` 게시. A-1 `staffAvailability` 규칙 있음 | 차이는 `/attendance/{staffId}/records/{recordId}` 규칙 추가뿐이다. 사용자·catalog·확정 일정·결근 권한 규칙은 동일하다 |
| Storage Rules | Rules API 목록에 Storage release가 확인되지 않음 | 로컬 Storage Rules 파일·firebase.json Storage 항목·Storage 연동이 없다. 사진은 Storage가 아닌 Firestore Blob이다. 원격 버킷별 IAM·객체는 조사하지 않았다 |

함수 소스는 배포 메타데이터가 가리키는 아카이브에서 선택한 JS 파일만 읽어 줄바꿈을 정규화한 SHA-256으로 비교했다. 배포된 Git commit 식별자는 확인되지 않았으므로 정확한 commit으로 단정하지 않는다. Hosting도 정적 파일 비교이며 실제 서비스에 로그인하거나 화면 기능을 실행해 확인한 결과는 아니다.

로컬 근거: `lib/models/schedule_codec.dart`, `lib/services/schedule_repository.dart`, `lib/services/attendance_repository.dart`, `lib/data/emulator_display_names.dart`, `functions/index.js`, `functions/validation.js`, `functions/existing-schedule.js`, `functions/suggestion-service.js`, `firestore.rules`, `firebase.json`.

읽기 전용 비교 증거는 Git 제외 경로 `.local-tools/deployment-audit-20261114/summary.json`과 `published.*`에 보관했다. API 키, 비밀번호, Secret 값, 이용자·직원 문서, 전체 일정은 포함하지 않는다.

## 기능별 실제 환경 호환성

- **방문 시간 계산·확인(B-1/B-2)**: 계산과 미리보기·유지/적용은 기존 Flutter 로직을 사용한다. 최종 저장에는 최신 `confirmSchedule` 검증이 필요하다. 출처 없는 기존 시각은 수동 입력으로 취급하며, 자동으로 덮어쓰지 않는다. `estimatedVisitSources`는 선택 필드이므로 새 서버는 기존 필드가 없는 일정을 수용한다. 필드가 있는 새 일정을 저장한 후에는 구형 서버가 기존 일정 형식을 거절할 수 있으므로 서버를 B-1 이전 버전으로 되돌리지 않는다.
- **결근·코스 인계(A-1/A-2)**: 실제 Rules에 결근 조회가 허용되어 있고, 배포된 핵심 서비스 코드가 로컬과 같다. 관리자 권한 확인, 결근 버전 확인, 읽기 후 쓰기, 일정 버전 충돌 확인, 요청 ID 중복 방지, 이전 직원 조회 문서 삭제와 새 직원 문서 저장의 트랜잭션을 유지한다. 조회 실패와 기록 없음은 구분하며 실패 시 확정을 막는다. 기존 담당 직원의 결근·인계 완료 표시 문제는 `docs/known-issues.md`의 후속 항목이며 문서 부재만으로 인계 완료를 추정하지 않는다.
- **AI 추천**: `USE_FIREBASE_EMULATORS=true`와 demo 프로젝트, 서버의 Emulator·loopback 조건이 필요하다. 실제 프로젝트에서는 제안 버튼/요청이 활성화되지 않는다. `suggestSchedule`만 배포해도 사용할 수 없다. 모델 기본값의 실제 API 제공 여부·Secret 유효성·Gemini 결제/쿼터는 이번에 확인하지 않았으며 외부 AI 호출도 하지 않았다.
- **사진 등록·조회**: repository가 실제 프로젝트에서 비활성화된다. 로컬 사진 규칙도 `aud`가 `demo-*`인 직원의 생성만 허용한다. 현재 실제 규칙에는 사진 경로 자체가 없으므로 기본 거부된다. JPEG 최대 180KiB를 Firestore에 시각·직원·날짜·코스와 함께 저장하는 시연 구현이다. 이번 배포를 위해 Storage 서비스나 버킷을 만들 필요가 없다.
- **가상 이름·테스트 표시**: 20명/80명 이름 alias는 demo 프로젝트의 `operations-20x80-v1`에만 적용된다. 실제 Firebase에서는 저장된 이름을 그대로 표시하며, Emulator용 '테스트 데이터' 표기도 활성화되지 않는다. 실제 프로젝트에서 가상 데이터를 시연할 때 동일한 표시가 필요하면 별도 표시 조건 수정이 필요하다. catalog 문서나 계정을 자동 변경해서 해결하지 않는다.
- **코스 상세 간소화**: 읽기 전용 직원·차량 표시, 명시적 변경 버튼, 추가 설정은 UI 변경이다. 기본 차량 자동 배정이나 새 필드를 요구하지 않는다.

## 기존 데이터·계정 보존

- schemaVersion 1 유지. `settings/schedules.catalogVersion`은 신규 날짜의 기본 catalog 선택이고, 기존 확정 일정은 자신의 `catalogVersion`을 사용한다. 배포 시 포인터를 변경하거나 catalog를 재등록하지 않는다.
- 출처 맵은 선택 필드이며 기존 데이터 일괄 변환이 필요하지 않다. 알 수 없는 추가 필드가 있는 기존 일정은 기존 보호 로직대로 확정을 거절하고 보존한다.
- 계정은 Auth UID와 `users/{uid}`를 연결한다. `active: true`는 boolean, `role`은 `admin` 또는 `staff`, 직원의 `staffId`는 명시적인 catalog 직원 ID여야 한다. 직원이 자기 role/active/staffId를 쓰거나 다른 직원 일정·사진을 읽을 권한을 추가하지 않는다.
- 실제 문서 내용을 읽지 않았으므로 각 계정의 staffId 연결, 활성 catalog 완전성, 개별 일정 데이터의 호환성을 실데이터 기준으로 전수 검증했다고 판단하지 않는다. 배포 후 기존 가상 계정으로 확인할 항목이다.
- 등록 도구, fixture 준비 도구, Auth import, Firestore import/delete, settings 변경 명령은 배포 절차에 포함하지 않는다.

## 프로젝트·비용 확인

실제 메타데이터에서 프로젝트 ACTIVE, 결제 계정 연결 및 `billingEnabled: true`를 확인했다. 이메일/비밀번호 로그인과 비밀번호 필수 설정이 켜져 있다. 허용 도메인은 localhost, `senior-transport-app.firebaseapp.com`, `senior-transport-app.web.app`이다. 기본 Firestore는 Native / `asia-northeast3`이며 삭제 보호는 꺼져 있다. 이번에 변경하지 않았다.

Functions, Run, Cloud Build, Artifact Registry, Firestore, Hosting, Identity Toolkit API는 활성 상태다. 조회한 활성 서비스 목록에는 Secret Manager와 Firebase Storage API가 없었다. 그 서비스를 필요로 하는 작업은 자동으로 진행하지 않는다. 결제 계정 번호, 실제 청구액·예산 알림 설정은 보고서에 수집하지 않았다.

Functions 배포에는 Blaze가 필요하며 빌드·아티팩트 저장도 비용 발생 요인이 될 수 있다. Hosting 보관 버전·전송량, Firestore 읽기·쓰기·저장량, 함수 실행 비용도 확인한다. 기존 결제 연결이 무료 사용을 보장하지 않는다. 실제 AI 활성화 시 Gemini 사용량·결제와 Secret Manager를 별도로 검토해야 한다. [Functions 공식 안내](https://firebase.google.com/docs/functions/faq-and-troubleshooting), [Hosting 사용량 안내](https://firebase.google.com/docs/hosting/usage-quotas-pricing), [Firebase 요금제 안내](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans).

## 배포 전에 필요한 수정 범위 — 이번에는 미수정

1. **운영 함수 discovery에서 Emulator 전용 AI 선언 분리**: 현재 `functions/index.js`는 AI export와 `defineSecret('GEMINI_API_KEY')`, 모델 파라미터를 항상 선언한다. 설치된 Firebase CLI는 endpoint 필터 적용 전에 codebase 파라미터를 해석하는 경로가 있으므로 `--only` 두 함수만 지정해도 AI Secret 준비를 요구할 수 있다. 함수 필터가 Secret·API 설정을 전부 격리한다고 가정하지 않는다. 운영 진입점/패키징에서 두 일정 함수만 발견되도록 최소 수정하고, Emulator AI는 유지하는 것이 권장 범위다. 제품 진입점 수정과 회귀 테스트가 필요하다. Secret을 임의 생성하거나 AI guard를 제거하지 않는다.
2. **서버 갱신 우선**: 현재 로컬 `validation.js`·`existing-schedule.js`의 출처 선택 필드 지원을 포함해 `confirmSchedule`을 먼저 갱신한다. 공용 진입점 변경을 검증한 뒤 `setStaffAbsence`도 같은 소스 기준으로 맞춘다. 기존 중복·정원·시간·결근·권한 검증은 그대로 둔다.
3. **배포 범위 확정**: 이번에 가능한 범위는 UI·일정 관리다. 실제 AI·사진 사용까지 기대한다면 클라이언트, 서버/Rules, Secret·요금·개인정보 처리 범위를 별도로 설계하고 검증해야 한다. 현재 guard를 해제하는 소규모 배포로 간주하지 않는다.

UI·일정 관리만 배포할 때는 현재 실제 Firestore Rules를 유지해도 된다. 로컬 Rules의 유일한 추가분은 비활성 상태의 Emulator 사진 경로이므로 UI를 위해 꼭 배포할 필요가 없다. Storage 배포는 하지 않는다.

## 안전한 실행 순서와 명령어

**아래 deploy 명령은 이번 점검에서 실행하지 않았다. 위 운영 진입점 분리와 회귀 검증을 완료하고, 사용자가 배포를 승인한 뒤 실행할 절차다. 현재 소스를 그대로 전체 배포하는 명령이 아니다.** Node.js 22, Flutter, Firebase CLI가 PATH에 있는 PowerShell을 기준으로 한다. `.firebaserc`가 없으므로 항상 프로젝트를 명시한다.

1. 변경 파일을 검토·기록하고 Console에서 현재 Hosting release, 함수 버전, Rules 게시본을 보관한다. 기존 편집 중인 일정은 마무리하고 관리자의 동시 편집을 멈춘다. Console 결제 화면에서 예산·사용량을 확인한다. 계정·catalog·확정 일정을 재등록하지 않는다.

2. 로컬 검사. 기존 Emulator를 사용 중이라면 `test-emulators.ps1`를 중복 실행하지 않고, 별도 포트의 demo 설정으로 격리한다. 실제 프로젝트 ID로 Emulator 데이터를 준비하지 않는다.

```powershell
flutter analyze
flutter test
powershell.exe -ExecutionPolicy Bypass -File tools/test-emulators.ps1
```

3. 운영 discovery가 두 함수만 포함하는 것을 확인한 후 서버를 먼저 배포한다. 원치 않는 Secret 생성·API 활성화·함수 삭제 요청이 나오면 중단하고 범위를 다시 확인한다. 일반 `firebase deploy` 또는 `--only functions`는 사용하지 않는다.

```powershell
firebase.cmd functions:list --project senior-transport-app
firebase.cmd deploy --only "functions:confirmSchedule,functions:setStaffAbsence" --project senior-transport-app
firebase.cmd functions:list --project senior-transport-app
```

4. Rules는 현재 배포본과 로컬 diff를 다시 확인한다. UI·일정 전용 배포에서는 생략할 수 있다. 검토한 로컬 Rules를 함께 반영하기로 결정한 경우에만 다음을 실행한다. 이것으로 실제 사진 등록이 활성화되는 것은 아니다.

```powershell
firebase.cmd deploy --only firestore:rules --project senior-transport-app
```

5. 실제 Firebase용 release를 다시 만들고 검증한 뒤 **Hosting을 마지막에** 배포한다. 현재 빌드 산출물에 이후 테스트/debug 빌드가 덮어써졌으면 반드시 재빌드한다. 빌드 검증을 우회하거나 Emulator 옵션 true 산출물을 올리지 않는다.

```powershell
powershell.exe -ExecutionPolicy Bypass -File tools/build-hosting.ps1
node tools/verify-hosting-build.cjs
firebase.cmd deploy --only hosting --project senior-transport-app
```

build 스크립트는 `flutter build web --release --dart-define=USE_FIREBASE_EMULATORS=false --base-href /`와 안전 검사를 수행한다. `build/web` 제공, 루트 base, SPA rewrite 및 캐시 재검증 설정이 있다. Web Firebase 설정의 공개 식별자와 서버 비밀 키는 구별한다. 서버 Secret·서비스 계정·환경 파일·소스맵 등을 배포 폴더에 복사하지 않는다.

## 배포 후 핵심 확인 및 대응

관리자/직원 각각 새 브라우저 세션에서 기존 가상 계정으로 확인한다. 다음 쓰기 테스트는 **배포 승인 후 별도 선택한 가상 날짜·시간대에서만** 수행하며 이번 점검에서는 실행하지 않았다.

- 관리자: 송영 현황 기본 진입, 이름 검색·직원 상세 이동, 날짜·요일·오전/오후 표시, 09:30/19:00 한국 시간 선택 정책. 새로고침과 직접 URL 진입, 재로그인도 확인한다.
- 방문 시간: 기존 시각 조회, 일괄 계산 비교, 직접 입력 시각 변경 확인, 순서 변경 후 재확인/유지, 시간 충돌 확정 차단, 정상 전체 일정 확정과 직원 공유. `invalid-argument`가 나면 배포된 함수의 출처 필드 허용 여부부터 확인한다.
- 결근/인계: 오전·오후·종일, 등록·취소 및 새로고침, 결근 직원 코스 잔존 시 확정 차단, 인계 후 새 직원 조회 및 이전 직원의 조회 문서 정리. 다른 날짜·시간대는 유지되어야 한다. 인계 완료 문구의 알려진 한계는 별도로 확인한다.
- 동시 편집: 두 관리자 세션에서 일정·결근 버전이 바뀌면 오래된 확정이 거절되고, 새 데이터를 확인한 뒤 다시 처리되는지 확인한다. 통신 실패 재시도에서 중복 확정되지 않아야 한다.
- 직원: 본인 확정 일정·주소·시각만 조회, 다른 직원 일정/사진과 관리자 전용 전체 데이터 접근 거부. 로그아웃 후 접근 거부. 기존 사용자 계정·문서가 보존되어야 한다.
- AI·사진: 이번 UI·일정 전용 운영 배포에서는 사용할 수 없는 것이 예상 결과다. Emulator에서 성공한 기능을 실제 Firebase에서도 가능하다고 시연하지 않는다.
- 오류: `permission-denied`는 role/active/staffId와 Rules 경로·게시본을 점검한다. 결근 조회 실패의 확정 차단을 없애지 않는다. 함수 로그는 안전한 오류 유형·단계만 확인하며 키·사진·일정 원문을 공유하지 않는다.
- UI 오류이면 Console Hosting release history에서 이전 호환 UI로 되돌리는 방안을 우선 검토한다. 출처 필드가 저장된 뒤 B-1 이전 서버로 되돌리거나 A-1 이전 Rules로 되돌리지 않는다. 데이터 삭제·초기화로 복구하지 않는다.

## 이번 로컬 검증

- 실제 Firebase용 Flutter Web release 빌드 성공.
- Hosting 산출물 안전 검사 통과: release / 프로젝트 일치 / 38개 파일 / Emulator·debug 번들 및 비밀정보 패턴 혼입 검사 통과. fingerprint `cdb198d95fe539e40a8a8c57daf60e1d4eb8584fece534778bdc821223216ed9`.
- Hosting 빌드 안전 검사 테스트 **5개 통과**.
- `flutter analyze`: 문제 없음.
- Flutter 전체 테스트 **229개 통과**.
- Auth/Firestore/Functions Emulator 회귀 **110개 통과**는 직전 코스 상세 개선의 기록이다. 이번 읽기 전용 점검에서는 Emulator 회귀를 재실행하지 않았다. 운영 진입점을 수정하면 다시 실행해야 한다.
- 실제 서비스 로그인·함수 호출·AI API 호출·사진 등록 및 쓰기 테스트는 수행하지 않았다. 정적 검사·단위 테스트 성공을 실제 서비스 통합 검증 완료로 간주하지 않는다.

이번에 추가한 추적 파일은 이 보고서뿐이다. 기존 미커밋 UI·테스트·문서는 보존했다. 로컬 점검 스크립트와 메타데이터는 `.local-tools`에, release 산출물은 `build/web`에만 있다. Firebase 설정·Functions·Rules·제품 소스는 수정하지 않았다.
