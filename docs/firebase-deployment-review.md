# 실제 Firebase 배포 전 검토 및 수동 실행 절차

검토 기준: 2026-11-12, 현재 작업 공간의 코드와 Firebase 공식 문서.

이번 검토에서는 실제 프로젝트의 데이터·계정·배포 상태·요금제를 원격 조회하거나 변경하지 않았다. Functions/Rules 배포, 요금제 전환, 유료 서비스 활성화도 수행하지 않았다. 아래 실제 서비스 명령은 사용자가 직접 검토한 후 실행하는 절차다. 검토 문서만 추가하며 앱·서버·규칙 코드는 수정하지 않는다.

## 1. 설정 점검 결과와 진행 조건

| 항목 | 로컬 확인 결과 | 사용자 확인 사항 |
|---|---|---|
| 프로젝트 ID | FlutterFire 설정·Web/Android 설정 모두 `senior-transport-app` | Console의 프로젝트 ID와 정확히 일치하는지 확인 |
| `.firebaserc` | 파일 없음 | 모든 실제 CLI 명령에 `--project senior-transport-app` 명시 |
| `firebase.json` | functions source=functions, runtime=nodejs22, firestore.rules=firestore.rules | Functions/Rules만 선택적으로 배포 |
| Functions | 2세대 HTTPS Callable `confirmSchedule`, Node 22 | 같은 이름의 기존 함수·세대·리전이 있는지 확인 |
| 리전 | 서버와 Flutter 모두 `asia-northeast3` | 실제 Firestore 위치 확인. 기존 DB를 임의로 삭제·재생성하지 않음 |
| 실행 옵션 | maxInstances=2. 메모리·minInstances·timeout·동시성·App Check는 코드에서 미명시 | 배포 후 실제 적용 옵션 확인. 인스턴스 수 제한은 월 청구 한도가 아님 |
| Firestore DB | 서버·클라이언트 모두 기본 DB 사용 | `(default)` Standard/Native 모드의 DB에 등록. 다른 named DB에 넣으면 현재 앱에서 조회하지 않음 |
| Hosting | firebase.json에 설정 없음 | 이번 절차는 웹 호스팅 배포를 포함하지 않음 |
| Emulator | demo-senior-transport, loopback, Auth 9099/Firestore 8080/Functions 5001 | 실제 앱 빌드에 USE_FIREBASE_EMULATORS=true를 사용하지 않음 |

FlutterFire의 `flutter.platforms...projectId`는 Firebase CLI 배포 대상의 대체 설정이 아니다. `.firebaserc` 없이도 `--project`를 지정하면 배포할 수 있다. 별칭이 필요하면 사용자가 프로젝트 확인 후 다음 내용을 `.firebaserc`로 만들 수 있지만, 아래 명령은 계속 프로젝트 ID를 명시한다.

```json
{
  "projects": {
    "default": "senior-transport-app"
  }
}
```

Node 22는 현재 공식 지원 런타임이고 firebase.json과 package.json의 설정이 일치한다. 서울은 지원되는 Functions 리전이며 Tier 2 가격 지역이다. [런타임](https://firebase.google.com/docs/functions/manage-functions), [리전](https://firebase.google.com/docs/functions/locations)

## 2. 비용·서비스 검토 — 배포 명령 전에 수행

Cloud Functions 실제 배포에는 Blaze와 연결된 Cloud Billing 계정이 필요하다. 로컬 Emulator 테스트에는 이 전환이 필요하지 않다. [공식 안내](https://firebase.google.com/docs/functions/get-started)

Firebase Console → 프로젝트 설정/사용량 및 결제에서 현재 요금제와 결제 계정을 확인한다. 사용자가 비용을 승인한 경우에만 Blaze 전환을 진행한다. 기존 결제 계정을 연결하는 작업도 요금제에 영향을 줄 수 있으므로 검토 없이 연결하지 않는다.

이 앱이 사용하는 서비스:

- Firebase Authentication: 기존 이메일/비밀번호 로그인.
- Cloud Firestore: users, 기본 데이터, 전체/직원별 일정, 요청 영수증.
- Cloud Functions 2세대: confirmSchedule.
- 배포·실행 기반 서비스: Cloud Functions API, Cloud Run, Cloud Build, Artifact Registry, Cloud Logging 및 배포용 Cloud Storage.
- 현재 설치된 Firebase CLI 15.36.0의 2세대 준비 로직은 Cloud Run뿐 아니라 Eventarc·Pub/Sub·Storage API와 서비스 ID도 준비한다. Callable에 별도 이벤트 트리거가 없어도 CLI가 이를 활성화할 수 있으므로 **deploy를 단순 확인 명령처럼 실행하지 않는다**.

사진 인증은 아직 미구현이므로 앱용 Firebase Storage 버킷이나 Storage Rules를 별도로 설정할 필요는 없다. Functions 배포가 사용하는 저장소는 사진 기능과 별개다. Scheduler, 외부 AI API, 별도 Secret Manager 비밀키도 현재 앱에서 사용하지 않는다.

비용 확인 항목:

| 항목 | 비용이 생길 수 있는 지점 |
|---|---|
| Functions/Cloud Run | 호출·CPU·메모리·네트워크. 거부된 요청 처리도 완전한 무비용으로 가정하지 않음 |
| Cloud Build | 배포 빌드 |
| Artifact Registry | 빌드 이미지 보관. 함수 호출이 없어도 보관 비용 가능 |
| Firestore | 읽기·쓰기·삭제·저장·네트워크. 실시간 갱신과 Rules의 get/exists 평가 읽기도 고려 |
| Cloud Logging/배포 저장소 | 로그와 아티팩트의 사용량·보관 |
| 리전 간 통신 | Firestore 위치와 서울 Functions 위치가 다를 때 지연·전송 비용 검토 |

무료 할당량은 있으나 이 앱의 비용이 반드시 0원이라는 뜻은 아니다. 현재 코드는 한 번 확정할 때 전체 마스터를 읽고 모든 담당 직원의 문서를 갱신한다. 대규모 fixture는 직원 40 + 차량 40 + 이용자 79 + 기본 코스 78 = **기본 데이터 문서 237개**다. 시간대별 담당자 39명이면 신규 확정 시 전체 일정 1 + 직원 문서 39 + 영수증 1 = **41개 문서 쓰기**가 발생한다. 여기에 권한·버전 확인 읽기, 재시도, 재배정 삭제, 관리자 재조회와 직원 리스너 갱신이 추가된다. 이는 코드상 작업량 예시이며 청구액 견적은 아니다.

처음 실제 서비스에서는 기준 데이터 3명/5명으로 시작해 확인 후 40명 규모로 확장하는 방식을 권장한다. 비용 자체를 낮추려면 추후 불변 catalog 캐싱과 변경 직원만 갱신하는 최적화를 별도로 검토할 수 있다.

예산 알림을 설정하되, 알림은 사용·요금을 차단하지 않는다. Console에 제공되는 Functions용 서비스별 spend cap도 검토할 수 있다. 현재 Preview이며 집행 지연이 있어 절대적인 hard cap이 아니고, Firestore·빌드·이미지 보관 등 전체 프로젝트 비용을 모두 막는 것으로 해석하면 안 된다. [요금제·예산](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans), [spend caps](https://firebase.google.com/docs/projects/billing/spend-caps)

Artifact Registry 이미지 정리 정책은 기존 이미지 사용 여부를 확인한 뒤 사용자가 설정한다. 이번 절차에서 자동 삭제 정책을 실행하지 않는다. [이미지 보관 비용과 정리](https://firebase.google.com/docs/functions/manage-functions#clean_up_deployment_artifacts)

실제 금액은 서울 리전·실제 사용량·결제 통화에 따라 공식 가격표/계산기로 확인한다. [가격표](https://firebase.google.com/pricing), [Firestore 과금](https://firebase.google.com/docs/firestore/pricing)

## 3. 기존 데이터·권한 보존 확인

사용자가 Firebase Console에서 다음을 먼저 확인하고 기존 값·규칙의 사본을 안전한 곳에 보관한다. 관리형 백업/Export 같은 추가 유료 기능은 이 절차가 자동으로 활성화하지 않는다.

1. 현재 Firestore Rules 원문과 배포 시각.
2. 기존 users 문서의 UID, role, active, staffId. 비밀번호·토큰·해시를 문서나 Git에 복사하지 않는다.
3. settings/schedules의 기존 값과 catalog 목록.
4. schedules 및 staffSchedules의 기존 문서, 특히 테스트하려는 날짜·시간대 문서.
5. Functions에 confirmSchedule이 이미 있는지, 어느 리전/세대인지.

위험과 보호 범위:

- Functions/Rules 배포가 Auth 사용자를 재생성하거나 users 문서를 삭제·수정하지는 않는다.
- **Rules 배포는 규칙 전체를 교체한다.** 현재 저장소의 규칙은 이 앱 경로 외에는 모두 거부한다. 다른 앱/컬렉션이 같은 DB를 쓰고 있으면 배포 전에 통합 검토가 필요하다. 물리적 문서는 남아도 접근이 막힐 수 있다.
- 확정 API는 해당 schedules 문서와 직원별 조회 문서를 `set`으로 교체한다. 이 경로에 수동으로 추가한 미지원 필드는 유지되지 않는다. 이전 담당자 문서는 해당 scheduleId에 한해서 삭제된다. 다른 날짜·오전/오후 문서는 변경하지 않는다.
- 정상 schema의 일정은 expectedVersion 비교로 동시 덮어쓰기를 막는다. **구형/수동 작성 schedules 문서에 대한 자동 마이그레이션은 없다.** 서버는 `old.version || 0`을 사용하며 기존 문서의 schemaVersion/status/version을 일괄 검사하는 명시적 방어는 없다. 같은 ID의 구형 문서가 있다면 단순히 비어 있는 것으로 간주하지 말고 중단한다. 보존·변환 또는 서버의 기존 문서 형식 검증 보강 후 진행한다. Flutter가 구형 문서 읽기를 거부한다는 사실만으로 서버 보호가 완결되지는 않는다.
- catalog 버전은 새 ID를 사용한다. 기존 버전 문서나 자식 문서를 덮어쓰거나 삭제하지 않는다. settings의 포인터 변경은 직원의 로그인·조회 권한에도 영향을 주므로, 기존 활성 사용자들의 staffId가 새 버전에도 존재하는지 먼저 확인한다.
- Emulator 데이터 전체를 실제 DB에 import하지 않는다. 테스트의 임의 UID·역할 문서가 실제 users와 섞일 수 있다.
- tools/seed_emulator.cjs와 create_emulator_user.cjs는 실제 프로젝트를 거부하도록 되어 있다. 보호 조건을 제거하거나 실제 프로젝트에 맞춰 우회 실행하지 않는다.

기존 함수 삭제 제안이 나오면 중단하고 비교한다. 명령에 --force를 붙이지 않는다. 모든 설정을 재생성하는 firebase init, 실제 사용자 전체를 내보내는 auth:export도 이 절차에는 필요 없다.

## 4. 사용자·기본 데이터의 정확한 구조

기존 Auth 계정과 UID는 그대로 사용한다. users 문서는 필요한 필드만 추가/수정하고 기존 email/name 등은 유지한다.

```text
users/<관리자 Auth UID>
  role: "admin"       (string)
  active: true        (boolean)

users/<직원 Auth UID>
  role: "staff"       (string)
  active: true        (boolean)
  staffId: "s1"       (string; 실제 직원 문서 ID)
```

email/name은 선택 메타데이터이며 권한 판정에 사용하지 않는다. 같은 이름/이메일이라고 새 UID를 만들어 기존 계정을 바꾸지 않는다. 직원 staffId는 1~80자의 영문·숫자·밑줄·하이픈 형식이며, 실제 활성 직원 문서와 연결되어야 한다.

**정확한 설정 위치는 `settings/schedules` 문서의 `catalogVersion` 필드다. `settings/catalogVersion` 문서를 만드는 구조가 아니다.**

```text
catalogs/deploy-test-v1
  ready: false          (모든 자식 문서 등록·검증 후 true)
  fictional: true       (boolean)
  schemaVersion: 1      (integer)

settings/schedules
  catalogVersion: "deploy-test-v1"   (string; 준비 완료 후 마지막에 지정)
```

deploy-test-v1은 예시다. 같은 버전이 이미 존재하면 새 이름을 선택한다. 자식 컬렉션은 다음과 같다.

| 경로: catalogs/deploy-test-v1 아래 | 필드와 타입 |
|---|---|
| staff/s1 | name string, active boolean, unavailableWeekdays integer array |
| vehicles/v1 | name string, passengerCapacity integer |
| passengers/p1 | name/address/note 각각 string, 모두 가상 정보 |
| baseRoutes/morning-a | name string, period="morning", staffId/vehicleId string, passengerIds string array |

기준 fixture를 그대로 등록할 경우 직원 문서는 s1/s2/s3, 차량 v1/v2/v3, 이용자 p1~p5, 기본 코스 morning-a/morning-b/afternoon-a/afternoon-b가 필요하다. 최소 15개의 자식 문서다. 부모 catalog와 settings까지 합하면 17개 문서다.

기준 직원:

| 문서 ID | name | active | unavailableWeekdays |
|---|---|---|---|
| s1 | 김다정 | true | [] |
| s2 | 이온유 | true | [] |
| s3 | 박여유 | true | [5] |

요일은 월=1 … 금=5 … 일=7이다. 차량은 v1=햇살 1호/정원3, v2=나무 2호/정원3, v3=예비 3호/정원2다. 코스는 다음과 같다.

| 문서 ID | name | period | staffId | vehicleId | passengerIds (순서 유지) |
|---|---|---|---|---|---|
| morning-a | 햇살 A코스 | morning | s1 | v1 | ["p1","p2","p3"] |
| morning-b | 나무 B코스 | morning | s2 | v2 | ["p4","p5"] |
| afternoon-a | 햇살 A코스 | afternoon | s1 | v1 | ["p3","p1","p2"] |
| afternoon-b | 나무 B코스 | afternoon | s2 | v2 | ["p5","p4"] |

이용자의 가상 이름·주소·주의사항은 tools/fictional_catalog.cjs의 값을 사용한다. 필드는 생략하지 않는다. Console에서 숫자는 정수, active/ready/fictional은 boolean, ID와 period는 string, 순서는 array로 등록한다.

참조용 JSON을 로컬 파일로 확인하려면 다음 명령을 사용할 수 있다. 이 명령은 Firebase에 접속하지 않는다.

```powershell
node -e "require('node:fs').writeFileSync('fictional-catalog-review.json', JSON.stringify(require('./tools/fictional_catalog.cjs').fictionalCatalog(false), null, 2))"
```

40명/79명 참조 파일이 필요하면 false를 true로 바꾼다. JSON의 id는 **문서 ID**로 사용한다. 이 파일은 Console 직접 등록용 참조 목록이며 Firebase CLI의 DB import 형식이 아니다. 실제 등록은 Console 운영자가 수행한다. 직원 40명 규모를 선택해도 Auth 계정을 40개 만들 필요는 없으며, 테스트할 직원의 계정만 기존 UID와 연결하면 된다.

등록 순서는 새 catalog(ready=false) → 자식 문서 전체 → ID/참조/타입 검증 → ready=true → settings/schedules의 catalogVersion 변경이다. 기존 활성 계정의 staffId 누락이 있으면 포인터를 변경하지 않는다.

## 5. 로컬 사전 검증 명령

프로젝트 루트에서 실행한다. 실제 대상 설정을 임의로 바꾸지 않고, Emulator 테스트는 항상 demo 프로젝트를 사용한다.

```powershell
# 현재 작업 공간의 portable 런타임 사용 (해당 폴더가 있는 경우)
$deploymentNode = Get-ChildItem '.local-tools/node' -Directory -Filter 'node-v22*' -ErrorAction SilentlyContinue | Select-Object -First 1
$deploymentJava = Get-ChildItem '.local-tools/java' -Directory -Filter '*21*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($deploymentNode -and $deploymentJava) {
    $env:Path = "$($deploymentNode.FullName);$($deploymentJava.FullName)\bin;$env:Path"
}
node --version
java -version
firebase.cmd --version
npm.cmd --prefix functions ci
flutter pub get
flutter analyze
flutter test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/test-emulators.ps1
```

Node는 22.x, Java는 21 환경을 사용한다. 현재 작업 공간의 portable 도구가 PATH에 없다면 .local-tools/node/<폴더>, .local-tools/java/<폴더>/bin을 해당 터미널 PATH 앞에 추가한다. 테스트 스크립트는 이 portable 도구가 있으면 사용한다. Node 26 등 다른 버전으로 설치·배포 검증하지 않는다.

현재 작업 공간에 주요 신규 파일이 다수 untracked 상태다. 배포 전에 비밀정보를 제외하고 배포 기준 소스·의존성 잠금 파일·복구용 규칙 사본을 보관한다. 검토 없이 git add .를 수행할 필요는 없다.

이번 배포 검토에서는 테스트를 다시 실행하지 않았다. 이전 구현 단계 결과는 Flutter 48개, Emulator 11개 통과이며, 실제 배포 직전에 위 명령을 다시 실행한다.

## 6. 사용자 직접 수행 순서

### A. 변경 전 확인

1. Firebase Console에서 프로젝트 **ID** senior-transport-app을 확인한다. 표시 이름만 비교하지 않는다.
2. Authentication의 기존 Users, 이메일/비밀번호 제공자, Authorized domains를 확인한다. 개발 브라우저와 추후 사용할 도메인을 확인한다. 기존 계정/UID를 재생성하지 않는다.
3. Firestore `(default)`의 위치·기존 규칙·기존 데이터 및 Functions 동명 리소스를 확인한다. 위 3절의 중단 조건이 있으면 배포 명령으로 넘어가지 않는다.
4. 비용과 Blaze 전환·필요 API 활성화를 사용자 본인이 결정한다. 예산 알림, 제공되는 서비스별 spend cap, 이미지 보관 정책을 검토한다.
5. 5절의 로컬 검증을 실행한다.

### B. 기본 데이터 준비

6. Console에서 4절의 가상 catalog와 users 연결을 준비한다. ready와 settings 포인터는 마지막에 변경한다. schedules/staffSchedules/commits 문서를 임의로 미리 만들지 않는다. 최초 확정 API가 생성한다.
7. 배포 담당 Google 계정의 IAM과 Function 실행 서비스계정을 확인한다. 앱의 role=admin은 Google Cloud 배포 권한과 별개다. 실행 서비스계정은 Firestore 읽기/쓰기 권한이 필요하며 Rules 대신 서버 검증이 적용된다. 개인키 파일을 Flutter에 넣지 않는다.

### C. 비용·실제 변경을 승인한 뒤에만 실행

아래 명령은 안내일 뿐 이번 작업에서 실행하지 않았다. Firebase deploy는 필요한 API 활성화·빌드·실행 리소스 생성을 수행할 수 있다.

먼저 CLI 로그인 계정과 프로젝트 목록을 확인한다. 인증·목록 명령은 Functions 배포 명령이 아니다.

```powershell
firebase.cmd login
firebase.cmd projects:list
firebase.cmd functions:list --project senior-transport-app
```

그 다음 프로젝트 루트에서 범위를 제한하여 배포한다.

```powershell
firebase.cmd deploy --only firestore:rules --project senior-transport-app --config firebase.json
firebase.cmd deploy --only functions:confirmSchedule --project senior-transport-app --config firebase.json
```

첫 명령은 DB의 기존 규칙 전체를 교체하고, 두 번째는 confirmSchedule 배포를 대상으로 한다. 삭제·교체·API 활성화 경고가 예상과 다르면 중단한다. --force 또는 전체 firebase deploy를 사용하지 않는다. Function 준비가 끝나기 전에는 실제 앱에서 확정 작업을 시도하지 않는다.

배포 후 Console에서 Node 22, 2세대, asia-northeast3, maxInstances=2 및 실제 메모리·최소 인스턴스·타임아웃·동시성·실행 서비스계정을 확인한다. 조직 정책이나 IAM 때문에 Callable 진입점이 막히면 이를 users 역할 변경이나 Rules 전체 허용으로 해결하지 않는다.

실제 Firebase용 앱을 새로 빌드한다.

```powershell
flutter build web --dart-define=USE_FIREBASE_EMULATORS=false
```

현재 build/web은 이전 검증에서 Emulator=true로 만든 결과일 수 있으므로 그대로 실제 환경에 사용하지 않는다. 실제 백엔드 대상으로 로컬 브라우저에서 확인하려면 다음과 같이 실행한다.

```powershell
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=false
```

Hosting 설정이 없으므로 이 절차는 웹사이트를 자동 게시하지 않는다. Web 호스팅 공개는 별도 설정과 검토가 필요하다.

## 7. 배포 전후 계정 테스트

배포 전에는 아래 시나리오를 Emulator에서 실행하고, 배포 후에는 가상 테스트 날짜와 실제 관리자·직원 계정으로 반복한다. 다른 브라우저 프로필/시크릿 창을 사용해 계정을 분리한다.

| 시나리오 | 확인할 결과 |
|---|---|
| 기존 관리자 로그인 | role=admin, active=true로 관리자 화면 진입. 사용자 문서 값 유지 |
| 기존 직원 로그인 | staffId에 연결된 활성 직원 이름 표시. 직원 화면만 접근 |
| 잘못된 staffId/active=false | 권한 오류. 일정을 표시하지 않음. 테스트 후 원래 값 복원 |
| 초기 일정 없음 | 로그인 실패와 구분하여 일정 없음 표시 |
| 관리자 오전 확정 → 직원 로그인 | 본인 코스·차량·순서·예상 시각만 조회 |
| 예상 시각/순서 변경 후 재확정 | 직원 화면에 최신 version 반영 |
| 담당자 s1→s3 인계 | 같은 날짜·오전의 s1 문서 제거, s3 문서 생성. 다른 날짜·오후 유지 |
| 중복 직원/차량·정원 초과·시각 역전 | 확정 거부, 기존 확정본 유지 |
| 두 관리자 창 동시 편집 | 오래된 expectedVersion 저장 거부, 로컬 편집 유지 |
| 저장 중 네트워크 단절·재시도 | 일부 저장 없음, 같은 요청의 중복 확정 없음, 새로고침 후 서버 결과 확인 |
| 직원의 타인 일정/전체 일정 조회·직접 쓰기 | Rules에서 거부. 단순히 버튼이 없는 것만 확인하지 않음 |
| 비로그인/직원 역할의 확정 API 호출 | 서버에서 거부. 실제 토큰·비밀번호는 로그에 출력하지 않음 |
| 로그아웃·새로고침·뒤로 가기 | 보호 화면 폐기, 로그인 상태 유지/해제 동작 확인 |

기준 데이터 s3는 금요일 근무 불가다. s3로 정상 인계 테스트를 할 때는 금요일 이외의 테스트 날짜를 선택한다. 예: 2026-11-14. 오전과 오후는 별도로 확정하며 자동 복사되지 않는다. 기본 코스 문서가 바뀌지 않았는지도 확인한다.

Rules Playground에서 직원 UID로 본인 users/get은 허용, 다른 사용자 문서·다른 직원 일정·전체 일정/get은 거부인지 검사한다. 일정과 users 쓰기는 관리자 클라이언트에서도 거부되어야 한다. Function의 Admin SDK 저장은 이 클라이언트 쓰기 금지와 별개이며 서버에서 관리자 권한을 검사한다.

배포 후 실패하면 Functions 로그와 브라우저의 단계별 오류를 확인한다. 동명 함수 삭제나 DB 초기화로 해결하지 않는다. 규칙 복구는 보관한 원문을 검토 후 재배포하고, Function 복구는 이전 검증 소스를 재배포한다. Rules를 이전 버전으로 되돌린다고 이미 확정한 문서가 자동 복원되지는 않는다.

## 검토 결론

로컬 런타임·리전·클라이언트 연결·규칙의 역할 분리는 서로 일치한다. 실제 배포 진행 조건은 **명시적 프로젝트 선택, 기존 데이터/규칙 충돌 확인, 활성 직원 매핑을 포함한 catalog 준비, 사용자의 비용 승인**이다. 구형 schedules 문서가 발견되면 기존 문서 형식 검증/마이그레이션을 먼저 진행한다. 실제 프로젝트 상태와 배포 후 권한 보호는 Console 및 실제 계정 테스트가 완료되기 전까지 확인된 것으로 취급하지 않는다.
