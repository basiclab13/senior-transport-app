# Firestore 송영 일정 연동과 로컬 검증

날짜별 직원 결근의 스키마·트랜잭션·기존 확정본의 운행 가능 여부 판단은 [staff-absence-a1.md](staff-absence-a1.md)를 함께 확인한다. 확정 상태만으로 정상 운행 가능하다고 판단하지 않고 현재 날짜별 결근을 함께 조회한다.

## 구현 범위

Firebase Authentication의 이메일 로그인과 `users/{uid}` 역할 검증을 유지한다. 일반 앱은 Firestore를 조회하고, 관리자가 검토한 확정 요청만 `asia-northeast3`의 Callable Function `confirmSchedule`로 보낸다. 확정본은 Firestore에 영구 저장하며 직원별 문서의 실시간 변경을 구독한다. 미확정 편집 초안은 로컬에 유지하므로 새로고침 시 사라진다.

실제 프로젝트의 Functions·Rules 배포, Blaze 전환, 유료 서비스 활성화는 수행하지 않았다. 검증은 `demo-senior-transport` 로컬 Emulator에서만 수행한다. 실제 프로젝트에서는 별도 배포와 기본 데이터 등록이 완료되어야 동작한다.

## 저장 구조

실제 Firebase 초기 등록 기준은 직원 3명·차량 3대·이용자 5명·기본 코스 4개다. 40명·79명 fixture는 Emulator 부하 검증용이다. 필드 값과 등록 방법의 구분은 [initial-catalog-data.md](initial-catalog-data.md)를 참고한다.

실제 초기 등록용 운영자 CLI의 dry-run·ADC·명시적 적용·충돌 처리는 [initial-catalog-cli.md](initial-catalog-cli.md)에 정리한다. 기존 Emulator 전용 등록 CLI와 분리되어 있으며 실제 데이터 변경은 수행하지 않았다.

| 경로 | 내용 |
|---|---|
| `users/{uid}` | 기존 role/admin 또는 staff, active boolean, 직원 계정의 staffId |
| `settings/schedules` | `{catalogVersion: "demo-v1"}` |
| `catalogs/{version}` | `{ready: true, fictional: true, schemaVersion: 1}` |
| `catalogs/{version}/staff/{staffId}` | name, active, unavailableWeekdays (월=1 … 일=7) |
| `catalogs/{version}/vehicles/{vehicleId}` | name, passengerCapacity |
| `catalogs/{version}/passengers/{passengerId}` | 가상 name, address, note |
| `catalogs/{version}/baseRoutes/{routeId}` | name, period, staffId, vehicleId, passengerIds |
| `schedules/{YYYY-MM-DD_period}` | 관리자용 전체 확정본 |
| `schedules/{scheduleId}/commits/{requestId}` | 요청 UID·내용 해시·확정 버전·서버 시각 |
| `staffSchedules/{staffId}/days/{scheduleId}` | 본인의 확정 일정과 본인 일정에 필요한 표시용 기본 데이터만 포함 |

period는 `morning`/`afternoon`이다. 예상 시각은 기존 모델처럼 해당 날짜 자정부터 분 단위 정수다. 예상 출발/종료 시각은 함께 입력하거나 모두 null이며, 방문 시각 미입력은 맵의 항목 부재로 표현한다.

전체 확정본에는 `schemaVersion`, `catalogVersion`, `date`, `period`, `timezone: "Asia/Seoul"`, `status: "confirmed"`, `version`, `confirmedAt`(서버 Timestamp), `confirmedBy`, `lastRequestId`, `routes`, `absentIds`, `excludedIds`를 저장한다. RouteAssignment 필드명과 방문 순서를 유지한다. 직원별 문서에는 다른 직원의 코스·이용자나 전체 결석/제외 명단을 넣지 않는다.

기본 코스는 버전별로 보존한다. 날짜별 편집은 기본 코스를 수정하지 않는다. 기존 확정본은 해당 catalogVersion을 계속 참조한다. 기본 데이터 수정이 필요한 경우 새 버전을 등록하고 준비 완료 후 settings를 바꾼다. 기존 버전을 덮어쓰지 않는다.

## 계정과 직원 ID 연결

- 사용자는 Auth UID로 `users/{uid}`를 조회한다. email/name을 권한 근거로 사용하지 않는다.
- role은 정확히 admin/staff, active는 boolean true여야 한다. 직원 staffId는 직원 문서의 **문서 ID와 동일한 문자열**이어야 한다.
- 과거의 s1/s2/s3 고정 허용 목록을 제거했다. 직원 로그인 시 settings가 가리키는 catalog의 해당 staff 문서가 존재하고 active true인지 서버 조회로 확인한다.
- 잘못된 staffId 형식, 문서 누락, 비활성 직원 연결은 직원 연결 오류로 안내한다. Firestore 권한 거부·네트워크 오류와 구분한다.
- 직원 본인 문서에 대한 Rules에서도 users의 staffId와 경로를 비교하고 실제 활성 직원 데이터를 확인한다. 담당자를 변경한다고 users.staffId를 바꾸지 않는다. 계정과 직원의 연결은 유지하고 일정의 staffId를 변경한다.
- 비활성 직원도 관리자 목록의 이름 조회에서 제거하지 않는다. 기존 배정을 확인·인계할 수 있도록 근무 불가로 표시하고 확정 검증에서 차단한다.

## 확정 트랜잭션

1. Callable의 인증된 UID를 사용한다. payload의 역할이나 UID로 권한을 부여하지 않는다.
2. 트랜잭션에서 사용자 역할·활성 상태, 기존 일정, 요청 영수증, settings, 기본 데이터 버전·각 마스터를 **모두 읽는다**.
3. 동일 requestId는 동일 호출자·동일 내용 해시에 한해서 기존 결과를 반환한다. 다른 내용으로 재사용하면 거부한다.
4. 기존 version과 expectedVersion을 비교한다. 다른 관리자가 변경했다면 aborted로 거부하고 자동 덮어쓰지 않는다.
5. 직원 근무 여부, 코스·직원·차량·이용자 참조, 중복 배정, 차량 정원, 결석/제외, 방문 시각·순서·운행 범위를 서버에서도 검사한다. 같은 시간대 코스는 겹친다는 기존 검증 기준을 유지한다.
6. 검증 후에만 쓰기를 시작한다. 전체 확정본, 새 담당 직원 문서, 요청 영수증을 저장하고 더 이상 담당하지 않는 이전 직원 문서를 삭제한다. 대상은 선택한 scheduleId뿐이다. 다른 날짜·시간대는 변경하지 않는다.
7. 모두 같은 트랜잭션에서 커밋한다. 실패하면 기존 확정본을 유지한다. 입력 크기와 코스 수를 제한하며 큰 요청을 일부씩 확정하지 않는다.

서버 응답 후 앱은 최신본을 서버에서 다시 읽고 확정 상태로 전환한다. 저장 중 편집·날짜 전환·중복 제출을 막는다. 네트워크 오류 시 편집 내용과 requestId를 유지하며 재시도한다. 커밋 후 응답만 끊겼을 수 있으므로 서버 영수증을 확인하여 중복 저장을 방지한다. 자신이 확정한 실시간 이벤트는 다른 관리자 충돌로 표시하지 않는다.

다른 관리자 변경이 편집 중 수신되면 로컬 초안을 보존하고 확정을 차단한다. `편집 내용 폐기 후 최신본 불러오기`는 확인 대화상자를 거쳐 선택한 날짜·시간대 초안만 폐기한다. 계정 변경·로그아웃·화면 폐기 시 구독을 취소한다.

## 보안 경계

Rules는 관리자에게 전체 일정·기본 데이터 읽기를 허용하고 직원에게 본인 문서 get만 허용한다. 직원의 전체 목록 조회·타 직원 문서·전체 확정본 접근을 거부한다. users 역할과 기본 데이터 및 일정의 클라이언트 직접 쓰기는 관리자 포함 모두 차단한다. 관리자는 Function을 통해서만 확정한다.

Admin SDK는 Rules를 우회하므로 Function이 사용자의 role/active와 업무 조건을 별도로 재검증한다. 클라이언트 검증만 신뢰하지 않는다. 개발 도구는 HTTP Function으로 내보내지 않으며 Flutter 앱에도 포함하지 않는다. 서비스 계정 키나 계정 비밀번호를 앱/코드에 넣지 않는다.

`lib/data/demo_data.dart`는 기존 테스트 fixture에서만 참조한다. 앱의 관리자 목록·검증·직원 타임라인은 저장소에서 받은 데이터만 사용한다. Firestore 기본 데이터가 없거나 조회 실패 시 로컬 가상 데이터로 대체하지 않고 오류·재시도를 표시한다.

## 로컬 실행

Node 22, Java 21, Firebase CLI와 Flutter를 사용한다. 현재 작업 공간에는 공식 배포 파일의 체크섬을 확인한 portable Node/Java를 `.local-tools/`에 준비했다. 이 디렉터리와 node_modules·로그·Emulator 데이터는 Git에서 제외된다. 다른 컴퓨터에서는 해당 도구를 별도로 준비한다.

프로젝트 루트에서 의존성과 통합 테스트를 실행한다.

```powershell
npm.cmd --prefix functions ci
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/test-emulators.ps1
flutter analyze
flutter test
```

테스트 스크립트는 demo 프로젝트만 지정하며 Auth 9099, Firestore 8080, Functions 5001을 loopback에서 사용한다. PowerShell Bypass는 해당 실행 프로세스에만 적용하며 시스템 실행 정책을 변경하지 않는다. 테스트 계정의 비밀번호는 실행 때 임의 생성하고 출력하지 않는다.

앱에서 직접 확인할 때는 별도 터미널에서 다음 Emulator를 실행한다. portable 도구를 쓰는 경우 `.local-tools/node/<폴더>`와 `.local-tools/java/<폴더>/bin`을 해당 터미널 PATH 앞에 추가한다.

```powershell
firebase.cmd emulators:start --only auth,firestore,functions --project demo-senior-transport
```

다른 터미널에서 가상 기본 데이터를 등록한다.

```powershell
$env:GCLOUD_PROJECT = 'demo-senior-transport'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
node tools/seed_emulator.cjs --version=demo-v1 --scale
```

기존 버전은 덮어쓸 수 없다. `--scale`을 빼면 기존 코스·직원 3명·이용자 5명의 기준 데이터를 등록한다. `--scale`은 기존 기준 코스를 유지하면서 직원 40명·이용자 79명·시간대별 39개 코스로 확장한다. 두 개발 CLI는 loopback Emulator와 demo-* 프로젝트 이외의 환경에서는 초기화 전에 거부한다.

로컬 계정을 만들려면 직접 입력한 자격 증명을 환경변수로 전달한다. 관리자와 직원 계정에 대해 각각 실행한다.

```powershell
$env:EMULATOR_USER_EMAIL = Read-Host '가상 계정 이메일'
$localAccountPassword = Read-Host '로컬 테스트 비밀번호' -AsSecureString
$env:EMULATOR_USER_PASSWORD = [System.Net.NetworkCredential]::new('', $localAccountPassword).Password
node tools/create_emulator_user.cjs admin
# 직원 계정 생성 시 위 입력을 다시 하고 다음처럼 실행:
# node tools/create_emulator_user.cjs staff s40
Remove-Item Env:EMULATOR_USER_PASSWORD
```

계정 생성 도구는 실제 직원 ID 존재·활성을 확인하고 로컬 Auth 계정과 users 문서를 연결한다. 이메일·비밀번호·토큰은 출력하지 않는다. 잘못된 직원 ID는 계정 생성 전에 거부한다.

```powershell
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=true
```

이 플래그는 Firebase 프로젝트 ID까지 demo-senior-transport로 바꾼다. Emulator 전용 Web 빌드는 다음과 같다.

```powershell
flutter build web --dart-define=USE_FIREBASE_EMULATORS=true
```

기본 실행은 기존 FlutterFire 설정의 실제 프로젝트를 사용하므로, 이번 로컬 검증은 반드시 Emulator 플래그로 실행한다. Emulator는 기본적으로 종료 시 초기화된다. 로컬 세션을 유지하려면 `emulators:start`에 `--export-on-exit=.emulator-data`를 추가하고, 다음 실행부터 `--import=.emulator-data`를 함께 사용한다.

## Firebase Console에서 사용자가 확인할 작업

이번 작업에서는 아래 실제 서비스 작업을 수행하지 않았다.

1. 기존 Authentication Email/Password 활성화와 Authorized domains를 유지·확인한다.
2. 실제 Cloud Firestore 기본 데이터베이스와 배포할 Rules를 검토한다. 로컬 테스트 통과가 실제 Rules 배포를 의미하지 않는다.
3. 실제 환경에서도 **가상 데이터만** 등록한다. Console 운영자 또는 별도 승인된 IAM 개발 도구로 catalog의 자식 문서를 모두 등록한 뒤 ready를 true로 바꾸고 settings.catalogVersion을 지정한다. 이 작업의 Emulator 전용 CLI는 실제 프로젝트에서 실행되지 않는다.
4. users 문서 ID가 Auth UID인지 확인하고, 직원 계정의 staffId를 해당 catalog 직원 문서 ID와 정확히 연결한다. 본인 role·active·staffId를 일반 앱에서 변경할 수 없게 유지한다.
5. Cloud Functions 배포를 위한 Blaze 요금제·서비스 활성화·IAM·리전·운영 비용을 직접 검토한다. **별도 승인 후에만** Functions 및 Rules 배포를 진행한다. API 키·Admin SDK 개인키를 Flutter에 추가하지 않는다.
6. 실제 배포 후 관리자/직원 계정으로 로그인, 확정, 재로그인 후 복원, 실시간 갱신, 다른 직원 접근 거부를 다시 검증한다.

사진 인증은 기존처럼 준비 중 안내만 제공한다. 미확정 초안의 서버 저장·자동 병합·실제 서비스 배포는 이번 범위에 포함하지 않는다.

## 변경 파일과 테스트

- `functions/`: Callable 진입점, 서버 검증·트랜잭션, Emulator 통합 테스트, 의존성 잠금 파일.
- `lib/models/schedule_catalog.dart`, `schedule_codec.dart`: Firestore 기본 데이터와 일정 직렬화. `transport.dart`에 직원 활성 상태 추가.
- `lib/services/schedule_repository.dart`, `schedule_controller.dart`: 실제 조회·구독·확정·충돌·오류 복구. auth_service/app_user의 직원 연결 확인은 실제 직원 데이터 기반으로 변경.
- `main.dart`, `auth_gate.dart`, 일정 화면: 저장소 주입, Emulator 연결, 로딩·저장 중·오류·재조회 UI. 기존 직원 중심 레이아웃을 유지.
- `firestore.rules`, `firebase.json`: 권한 경계와 로컬 Emulator/Functions 구성.
- `tools/`: 기본 데이터 생성·Emulator 전용 등록·계정 생성·테스트 실행. 앱 사용자 실행 API 없음.
- `test/`: 기존 테스트의 저장소 주입, 저장 실패/재시도/동시 수정/응답 유실 테스트, 직렬화 테스트, 40명 규모 UI 조회·수정·재배정·확정 테스트.

Emulator 테스트는 실제 Auth 로그인, Callable 호출, Rules 거부, 실시간 구독, 원자적 재배정 및 날짜·시간대 격리, 동시 확정, 요청 중복, 검증 실패 시 미저장, 읽기 후 쓰기 순서, 개발 CLI의 실제 프로젝트 거부와 로컬 등록을 검증한다.

최종 실행 결과:

- `flutter analyze`: No issues found.
- `flutter test`: 기존 37개를 포함한 **48개 모두 통과**.
- Auth·Firestore·Functions Emulator: **11개 테스트 통과**, 실패 0개. 직원 40명·이용자 79명 데이터 사용.
- `flutter build web --dart-define=USE_FIREBASE_EMULATORS=true`: 성공 (`build/web`).
- 실제 Firebase 프로젝트의 배포·운영 계정 검증·Blaze 전환·유료 서비스 활성화는 미수행.
