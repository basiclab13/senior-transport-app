# A-1/A-2 실제 배포 전 최종 점검과 수동 절차

점검일: 2026-11-13 (한국 시간). 실제 `senior-transport-app`의 **게시된 Rules와 Functions 메타데이터만 읽기 전용으로 조회**했다. Firestore 문서·Authentication 계정의 내용은 원격 조회·변경하지 않았고 함수 호출, 배포, API 활성화, 요금제 변경도 하지 않았다. 아래 deploy 명령은 **향후 사용자가 배포를 승인한 뒤 직접 실행할 절차**이며 이번 점검에서 실행한 명령이 아니다.

## 1. 실제 배포본과 로컬의 확인된 차이

게시된 기본 Firestore release는 `projects/senior-transport-app/rulesets/ef65785a-8734-4c9e-86db-f6f640526585`이며 게시 시각은 `2026-11-12T11:35:51.282715Z` (한국 시간 20:35:51)이다. 읽어 보관한 원문과 로컬 `firestore.rules`를 비교했다.

| 항목 | 실제 배포본 | 로컬 |
|---|---|---|
| 기존 users/settings/catalogs/schedules/staffSchedules 권한 | 기존 규칙 | 동일 |
| `staffAvailability/{date}/staff/{staffId}` | 허용 규칙 없음 → 기본 거부 | 관리자 get/list, 직원 본인 get, 직접 write 금지 |
| 위 결근 문서의 `commits/{requestId}` | 기본 거부 | 관리자 get만, list/write 금지 |
| 그 외 경로 | 기본 거부 | 동일 |

차이는 위 A-1 블록 9줄뿐이다. 실제 연결에서 결근 조회가 `permission-denied`가 되는 배포본 불일치가 확인되었다. 빈 컬렉션이어도 이전 Rules에서는 조회를 허용하지 않는다. 새 권한은 기존 로그인 규칙을 변경하지 않으며 관리자의 직접 Firestore 쓰기도 허용하지 않는다.

현재 원문 SHA-256:

```text
게시본: F3A0579E3E9F90488C61B5F24E9FD0B8CDB306D808385D648C6E73D4D788DD49
로컬:   0C9089B1F4371ADD96C5A8B5268F1C727BA3F66E6BAB916BDB09FECF29F92286
```

원문·비밀이 없는 메타데이터 사본은 Git 제외 `.local-tools/deployment-review/`의 `published.firestore.rules`, `rules-summary.json`, `confirmSchedule-metadata.json`, `read-only-summary.json`에 있다. 사본을 안전한 운영 보관 위치에도 보관한다. 배포 직전 Console의 게시 시각·내용이 이 사본 이후 바뀌었으면 다시 비교해야 한다. Rules 배포는 전체 원문을 교체하므로 Console에서 추가한 다른 규칙이 있다면 통합 검토 없이 덮어쓰지 않는다.

실제 함수 목록에는 `confirmSchedule` 하나만 있고 `setStaffAbsence`는 없다. 기존 함수 메타데이터:

| 항목 | 실제 confirmSchedule | 로컬 두 함수 |
|---|---|---|
| 리전 | `asia-northeast3` | 동일 |
| 세대/트리거 | `GEN_2`, Callable 라벨 true, ACTIVE | `firebase-functions/v2/https.onCall` |
| 런타임/진입점 | `nodejs22` / `confirmSchedule` | Node 22 / 각각의 함수명 |
| 최대 인스턴스 | 2 | 명시적으로 2 |
| 메모리/CPU/동시 요청/시간 제한 | 256Mi / 1 / 80 / 60초 | 코드에서 별도 지정하지 않음; CLI 적용 설정을 배포 시 비교 |
| ingress | ALLOW_ALL | 별도 지정하지 않음; 정상 Callable 호출 설정 검토 |
| 최소 인스턴스 | API 응답에 값 없음 | 별도 지정하지 않음 |
| 수정 시각 | `2026-11-12T11:40:35.409489264Z` | 아직 미배포 |

동명·동리전·동세대여서 기존 `confirmSchedule` 갱신이 가능하며 함수 삭제·이름 변경·1→2세대 이전은 필요하지 않다. 실제 함수 소스/배포 커밋과 IAM 전체를 내려받아 검증한 것은 아니다. 배포 시 서비스 계정, IAM, 런타임 설정의 예상 밖 변경이 있으면 중단해 비교한다. Node 22 지원과 선택적 배포 절차는 [Firebase 함수 관리 문서](https://firebase.google.com/docs/functions/manage-functions), 세대 변경 제약은 [공식 이전 문서](https://firebase.google.com/docs/functions/2nd-gen-upgrade)를 따른다.

## 2. 데이터 계약·권한·기존 일정 호환성

추가되는 경로는 다음 두 가지다. 부모 날짜 문서나 빈 결근 문서를 미리 생성할 필요는 없다.

```text
staffAvailability/{YYYY-MM-DD}/staff/{staffId}
  schemaVersion: 1
  date: "YYYY-MM-DD"
  staffId: 카탈로그 직원 ID
  unavailablePeriods: ["morning"], ["afternoon"], 두 항목 또는 []
  version: 양의 정수
  updatedBy: 관리자 Authentication UID
  updatedAt: 서버 Timestamp
  commits/{requestId}: uid, hash, result, requestId, createdAt
```

- 없으면 서버 조회 성공 후 결근 없음/버전 0. 취소는 삭제 대신 `[]`와 증가한 버전을 기록한다.
- `setStaffAbsence`가 트랜잭션 내에서 로그인 UID의 `users/{uid}.active == true`, `role == admin`, 직원 참조·날짜·카탈로그·기대 버전을 검증한다. 종일은 한 문서에서 원자적으로 처리하고 요청 ID/해시로 중복을 막는다.
- A-2는 별도 컬렉션/Function 없이 해당 날짜·시간대 `routes[].staffId`만 변경한 초안을 기존 `confirmSchedule`로 확정한다. 원래 차량·이용자·순서·수동 시각은 유지한다.
- 확정 함수는 기존 직원·차량 중복, 정원, 이용자·시간 검증에 A-1 결근과 검토 버전 검증을 더한다. 모든 읽기를 먼저 수행하고 기존 직원 문서 삭제와 신규 직원 문서 저장을 같은 트랜잭션에서 처리한다.
- `expectedVersion`, `expectedAvailabilityVersions`와 영수증을 유지한다. 구버전 클라이언트가 결근 버전 필드를 생략해도 실제 서버 결근 검증은 수행한다. 기존 ID의 영수증 재조회는 과거 성공 확인일 뿐 새 확정이 아니다.
- 정상 schemaVersion 1 확정본은 그대로 읽고 수정할 수 있다. 기존 catalogVersion을 유지하며 활성 포인터를 자동 전환하지 않는다. users·Auth 계정·기본 휴무·마스터에 마이그레이션은 필요 없다.
- 결근 등록은 과거 확정본을 다시 쓰지 않는다. **`status == confirmed`만으로 운행 가능하다고 판단하지 않고 날짜별 결근을 함께 확인**한다. 새 앱은 기존 확정 이력을 재배정 필요로 표시한다. 구버전 앱/이미 열린 탭은 이 표시를 보장하지 못하므로 첫 실제 결근 등록 전 전원 갱신이 필요하다.

### 이번 점검에서 수정한 배포 전 문제

기존 서버가 기존 문서의 `version || 0`을 사용해 구형·잘못된 문서를 신규 일정처럼 덮어쓸 수 있었다. `functions/existing-schedule.js`를 추가하고 확정 트랜잭션에서 기존 문서의 스키마·날짜/시간대·정수 버전·확정 시각·참조 형식·지원 필드를 검사하도록 수정했다.

기존 문서나 코스에 수동 추가한 미지원 필드도 조용히 없애지 않고 `failed-precondition`, `details.reason=existing-schedule-incompatible`로 거부한다. 문서·직원별 일정·영수증을 바꾸지 않는다. 별도 보존·변환은 자동 수행하지 않는다. Flutter도 이 오류를 결근/카탈로그 오류와 구별해 서버 원본과 초안이 유지됨을 안내한다.

추가/수정 파일은 `functions/existing-schedule.js`, `functions/schedule-service.js`, `functions/test/staff-absence.test.cjs`, `lib/services/schedule_controller.dart`, `test/remote_schedule_test.dart`다. 정상 확정본 갱신과 오류 시 데이터 보존을 Emulator에서 확인했다.

## 3. 사용자·개인정보와 운영자가 확인할 미확인 항목

| 대상 | 허용 | 거부 |
|---|---|---|
| 관리자 | 전체 일정·카탈로그·결근 목록 조회, 서버를 통한 결근 등록·확정 | 앱에서 사용자 권한/계정 생성, Firestore 직접 쓰기 |
| 직원 | 본인 users, 본인 직원 마스터/확정 일정/결근 단건 | 다른 users·직원 일정·결근 목록, 전체 일정, 타 이용자 마스터, 결근/일정 쓰기 |
| 미인증·비활성 | 없음 | 보호 데이터/Callable 변경 |

직원용 일정에는 본인 코스의 이용자와 차량 데이터만 포함하고 관리자 confirmedBy는 제외한다. 본인 결근 문서에는 변경자 UID/시각이 포함되고 영수증은 관리자만 읽는다. UID는 권한을 부여하는 비밀키가 아니다. 역할은 클라이언트 표시가 아닌 Rules와 Functions에서 각각 확인한다. 개발 비밀번호·서비스 계정 비밀키는 배포 소스에 없다. 확인한 Functions 배포 소스는 JS 및 package 파일이며 테스트/node_modules/로그는 배포 제외다. 진단 로그는 debug 모드 전용이고 문서 전체·토큰·비밀번호를 출력하지 않는다.

이번에 실제 문서나 Auth 계정 목록을 읽지 않았으므로 다음은 Console에서 사용자가 배포 전에 확인한다. 값을 변경하라는 지시가 아니다.

- 기존 관리자 UID의 `active: true`(boolean), `role: "admin"`과 직원의 `role: "staff"`, `staffId` 연결. 동일 이름/이메일 때문에 계정을 다시 만들지 않는다.
- 현재 `settings/schedules.catalogVersion` (settings/catalogVersion 문서가 아님), 해당 부모의 `ready: true`, `fictional: true`, `schemaVersion: 1` 및 직원 참조. A-1/A-2 때문에 v1→v2 포인터를 강제로 바꾸거나 baseline을 다시 등록하지 않는다.
- 기존 schedule의 지원 스키마·버전과 사용자 추가 필드, 직원별 생성 문서에 수동 저장한 데이터. 확정 시 직원별 생성 문서는 교체되므로 수동 데이터는 먼저 별도 보존해야 한다.
- 기본 `(default)` DB 위치·모드, 배포 서비스 계정/IAM, Blaze·예산과 비용 승인, 기존 Web 배포 위치와 도메인. 실제 요금제·청구 상태·Auth 공급자·도메인·App Check 강제 상태는 조회하지 않았다.

권한 보호의 배포 후 실제 계정 검증이 끝나기 전에는 운영 적용 완료로 판단하지 않는다. App Check는 현재 클라이언트에 연결되지 않았으므로 Console에서 무작정 강제 활성화하지 않는다. HTTP IAM/ingress 오류를 앱 role 변경이나 Rules 전면 허용으로 해결하지 않는다.

## 4. 사용자가 직접 수행할 배포 순서

### 4-1. 변경 동결과 사본 보관

관리자에게 일정 변경·결근 등록을 잠시 중단하도록 안내한다. users.active를 내려 동결하지 않는다. 현재 Rules, 기존 함수의 검증된 배포 소스·설정, 테스트할 날짜의 확정본/직원 문서, settings와 카탈로그 정보를 안전하게 보관한다. Auth 비밀번호/토큰을 내보내거나 Git에 저장하지 않는다. 유료 백업/export 서비스는 이 절차가 자동 활성화하지 않는다.

Cloud Functions 배포는 빌드·실행 관련 API와 저장소 준비를 수행할 수 있고 비용이 발생한다. 기존 Blaze/결제 설정과 사용자 비용 승인을 Console에서 먼저 확인한다. maxInstances=2는 월 비용 한도가 아니다. [공식 배포 안내](https://firebase.google.com/docs/functions/get-started), [요금·예산 안내](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans)를 확인한다.

### 4-2. 터미널·로컬 검증

프로젝트 루트의 새 PowerShell에서 Node 22·Java 21·Firebase CLI와 기존 운영자 로그인을 사용한다. 이 작업 공간 portable Node는 `.local-tools/node/node-v22.23.5-win-x64`에 있다. 다른 PC는 설치 위치를 사용한다. Emulator 환경 변수를 제거하는 명령은 **현재 터미널의 환경만** 바꾸며 원격 데이터는 바꾸지 않는다.

```powershell
# 이 작업 공간의 portable Node를 사용할 때
$nodeTools = Join-Path (Get-Location) '.local-tools/node/node-v22.23.5-win-x64'
$env:PATH = "$nodeTools;$env:PATH"
node --version
firebase.cmd --version
Remove-Item Env:FIRESTORE_EMULATOR_HOST -ErrorAction SilentlyContinue
Remove-Item Env:FIREBASE_AUTH_EMULATOR_HOST -ErrorAction SilentlyContinue
Remove-Item Env:FIREBASE_EMULATOR_HUB -ErrorAction SilentlyContinue
Remove-Item Env:GCLOUD_PROJECT -ErrorAction SilentlyContinue
Remove-Item Env:GOOGLE_CLOUD_PROJECT -ErrorAction SilentlyContinue
firebase.cmd login:list
firebase.cmd functions:list --project senior-transport-app
npm.cmd --prefix functions ci
flutter analyze
flutter test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/test-emulators.ps1
```

`login:list`에서 의도한 운영자 계정을 확인하고 필요할 때만 사용자가 직접 `firebase.cmd login`한다. 배포를 위해 서비스 계정 비밀키를 새로 만들 필요는 없다. 기존 도구의 관리자/Emulator 가드는 제거하지 않는다. 명시적인 `--project`가 배포 대상을 결정하며 현재 `.firebaserc`는 없다.

### 4-3. Functions → Rules → 클라이언트

다음은 실제 배포 명령이다. **사용자가 최종 승인한 뒤에만 실행한다.** 각 단계의 성공을 확인한 뒤 다음으로 넘어간다. 기존 함수 삭제·세대/리전 변경이나 예상 밖 IAM/런타임 변경 제안이 나오면 중단한다. `--force`, 전체 `firebase deploy`, `firebase init`은 사용하지 않는다.

```powershell
# 1. 결근을 검사하는 확정 서버부터 갱신
firebase.cmd deploy --only functions:confirmSchedule --project senior-transport-app
firebase.cmd functions:list --project senior-transport-app

# 2. 새 관리자 결근 API 등록
firebase.cmd deploy --only functions:setStaffAbsence --project senior-transport-app
firebase.cmd functions:list --project senior-transport-app

# 3. 두 서버가 정상 반영된 다음 결근 조회 Rules 게시
firebase.cmd deploy --only firestore:rules --project senior-transport-app

# 4. 실제 Firebase용 Web 빌드·파일 검증 (업로드하지 않음)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build-hosting.ps1

# 5. 기본 Hosting 사이트 확인 후 정적 파일만 배포
firebase.cmd hosting:sites:list --project senior-transport-app
firebase.cmd deploy --only hosting --project senior-transport-app
```

서버를 먼저 갱신해 새 결근 기록을 생성하기 전에 확정 검증이 준비되게 한다. 두 함수 배포는 원자적 묶음 배포가 아니므로 중간에 실패하면 유지보수 상태로 멈추고 나머지 단계를 진행하지 않는다. Rules만 배포하거나 클라이언트의 새 버전 필드를 제거해 구버전 함수에 맞추는 방법으로 해결하지 않는다.

후속 작업에서 Firebase Hosting 정적 설정과 사전 검증을 추가했다. 현재 기본 사이트는 `https://senior-transport-app.web.app`으로 읽기 전용 확인했다. [Hosting 준비 문서](firebase-hosting.md)의 SPA·캐시·파일 검사·빌드 절차를 함께 따른다. 실제 Hosting 배포는 아직 수행하지 않았다. HTTPS 도메인, Firebase Auth 이메일/비밀번호 공급자와 도메인 설정을 확인한다. 기본 `firebase_options.dart`는 senior-transport-app이며 Functions 리전은 asia-northeast3다. 일반 `flutter run -d chrome`도 실제 Firebase에 연결한다.

Artifact Registry 정리 정책 설정/이미지 삭제 제안이 나오면 기존 복구용 아티팩트 보존을 먼저 확인한다. 정책을 별도 검토 없이 자동 승인하지 않는다. 배포가 오류로 끝나도 일부 함수가 이미 갱신됐을 수 있으므로 Functions 목록과 수정 시각을 확인한 뒤 대응한다. CLI의 초기 준비 실패를 해결하려고 데이터나 기존 함수를 삭제하지 않는다.

이제 **관리자와 직원 모두 기존 탭/PWA를 종료하고 새 산출물로 재접속**한다. 캐시된 구버전 앱이 없는지 확인한다. 구버전 클라이언트는 결근으로 무효화된 과거 확정본을 정상 일정처럼 표시할 수 있다. 모든 클라이언트 갱신 전에는 첫 실제 결근을 등록하지 않는다. release 로그는 debug 진단 로그를 출력하지 않으므로 필요할 때만 로컬 debug 실행으로 코드를 확인한다.

Functions/Rules 배포는 Authentication 계정·users·카탈로그·일정 문서를 자동 재생성/수정/삭제하지 않는다. 계정/데이터를 바꾸는 별도 seed/import/register 명령은 이 절차에 없다.

## 5. 배포 후 가상 데이터 테스트

운영자가 승인한 **기존 업무 일정과 겹치지 않는 테스트 날짜**를 선택한다. s3는 기본 금요일 휴무이므로 예비 인계 직원의 실제 근무 가능 요일을 확인한다. 테스트에서 생성한 기록은 버전/영수증 때문에 자동 삭제하지 않는다. 이번 점검에서는 이 실제 테스트도 실행하지 않았다.

1. 관리자 기존 계정으로 로그인·로그아웃·복원. 결근 기록 없는 날짜를 조회해 오류 없이 빈 결과로 확인되는지 확인.
2. 직원 기존 계정의 기존 확정본·본인 차량/이용자 조회. 타 직원·전체 일정·users 쓰기/역할 변경은 Rules Playground 또는 별도 검증 클라이언트에서 거부되는지 확인.
3. 오전 결근 등록 → 오전 재배정 필요, 오후/다른 날짜 유지. 오후·종일·부분 취소도 확인하고 새로고침 후 상태 유지 확인.
4. 결근 직원의 코스가 남으면 확정 차단, 기존 확정본도 정상 운행 가능으로 표시되지 않는지 확인.
5. A-2에서 근무 가능·코스 없는 직원에게 인계. 코스 있는 직원/결근 직원은 선택 불가. 초안 단계 서버 무변경, 확정 요약의 이전→새 담당자 확인.
6. 전체 확정 후 원래 차량·이용자·순서·시각 보존, 이전 직원 문서 제거와 신규 직원 조회 반영, 다른 시간대/날짜 보존 확인.
7. 다른 관리자 브라우저에서 같은 일정/결근을 변경해 `aborted` 및 최신본 재검토를 확인. 네트워크 응답 유실 시 같은 요청 ID 재시도가 한 번만 저장되는지 확인.
8. 직원·미인증 사용자의 Callable 변경, 관리자 포함 직접 Firestore 쓰기를 거부하는지 확인. 관리자/직원 화면과 Console을 함께 확인하고 변경 동결을 해제한다.

## 6. 오류 대응과 복구

| 오류 | 대응 |
|---|---|
| 결근 permission-denied | 연결 프로젝트/(default)/게시 Rules/active·role 확인. 문서를 임의 생성하거나 read=true로 완화하지 않음 |
| Function not-found/404 | setStaffAbsence 배포 성공, asia-northeast3, 클라이언트 프로젝트 확인 |
| invalid-argument | 구버전 확정 함수의 새 필드 거부와 실제 일정 검증 실패 구분. 두 함수의 배포 시각/리전·검증 메시지 확인 |
| failed-precondition + existing-schedule-incompatible | 기존 문서/추가 필드 사본을 보존. 자동 재저장·삭제 대신 승인된 변환 검토. 원본·초안 유지 |
| 다른 failed-precondition | 결근 직원 잔여 코스·카탈로그 준비/참조 확인 |
| aborted | 편집 내용을 보존하고 최신 일정/결근 상태를 다시 읽어 검토. CAS/버전 비교 제거 금지 |
| unavailable/시간 초과/결과 불명 | 확정 차단 유지. 접속 복구 후 영수증/최신본 확인, 같은 요청 ID로 재시도. 임의 새 요청으로 중복 확정하지 않음 |
| HTTP 403/CORS/권한 오류 | Cloud Run IAM/ingress와 Callable 인증 오류 구별. users.role·Rules를 우회하지 않음 |

필요할 때 운영자가 로그를 조회한다. 로그에는 진단 중 계정·이용자 정보를 복사해 게시하지 않는다.

```powershell
firebase.cmd functions:log --only confirmSchedule --project senior-transport-app
firebase.cmd functions:log --only setStaffAbsence --project senior-transport-app
```

실패하면 관리자 작업을 중단하고 기존 계정·문서를 유지한다. 한 함수만 성공했으면 현재 상태를 기록하고 성공한 함수를 삭제하지 않는다. 새 결근이 생성된 뒤 **결근을 모르는 구버전 confirmSchedule/앱으로 단순 롤백하면 보호가 깨진다.** 우선 결근 검증을 유지한 수정 버전으로 복구한다. 필요 시 운영자 검토하에 결근 변경 API에만 임시 거부를 넣어 재배포하고 수정한다. 계정 active를 일괄 변경하지 않는다.

과거 Rules로 복구하면 새 앱의 결근 조회는 차단되므로 쓰기도 중단한 상태여야 한다. Rules/소스 복원은 별도 승인된 재배포이고, 이미 변경한 문서가 자동 복구되지는 않는다. 일정 복구는 스냅샷을 임의 덮어쓰지 말고 현 결근/버전 검증을 통과하는 새 확정으로 처리한다. 취소된 결근 문서·요청 영수증도 단순 삭제하지 않는다.

## 7. 로컬 검증 결과와 판정

Emulator 테스트는 실제 계정이 아닌 demo 네임스페이스에서만 재실행했다. 기존 일정 보존 검사와 A-1/A-2, 20명/80명 및 기존 40명/79명 권한·동시성·원자성·중복 요청 검증을 포함한다.

| 검증 | 최종 결과 |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | 122개 통과 |
| Auth·Firestore·Functions Emulator | 50개 통과, 실패/건너뜀 0 |
| `flutter build web --release --dart-define=USE_FIREBASE_EMULATORS=false` | 로컬 빌드 성공, 앱 실행·업로드 안 함 |
| JavaScript 문법·`git diff --check` | 통과 |

검증에 사용한 Firebase CLI는 15.36.0이다. 로그는 Git 제외 `.local-tools/deployment-review/flutter-tests.log`, `emulator-tests.log`에 있다. Emulator는 테스트 종료 후 자동 종료했다. 이번에 만든 `build/web`은 실제 Firebase용 산출물이다. 이후 Emulator 브라우저 검증에는 반드시 `--debug --dart-define=USE_FIREBASE_EMULATORS=true`로 다시 빌드해야 한다.

현재 실제 배포본은 아직 A-1/A-2 운영 준비가 완료되지 않았다. 로컬 검증은 성공했고 실제 읽기 전용 비교에서 배포본과의 차이를 확인했다. Hosting 설정과 로컬 정적 파일 검증은 후속 문서에 준비했다. 남은 배포 전 조건은 운영자가 확인할 기존 데이터/카탈로그/계정 연결, 비용 승인, 보관 사본 및 전원 클라이언트 갱신 계획이다. 게시된 Rules/Functions·Hosting 갱신과 실제 계정 사후 검증까지 완료해야 권한 보호 적용 완료로 판단한다.
