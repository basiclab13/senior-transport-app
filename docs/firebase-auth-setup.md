# Firebase 로그인 설정 및 검증

> Firestore 일정 연동 이후 직원의 staffId는 고정 s1/s2/s3 목록 대신 실제 활성 직원 문서로 검증한다. 이 문서의 초기 규칙·고정 ID·메모리 저장 설명은 인증 단계 기록이다. 최신 구조와 로컬 실행은 [firestore-schedules.md](firestore-schedules.md)를 참고한다.

## 구현 범위와 현재 상태

- `lib/firebase_options.dart`, `firebase.json`, `android/app/google-services.json`의 존재를 확인했다. Web용 FirebaseOptions도 존재한다. 설정 파일의 존재는 Console 설정이나 실제 접속 성공을 보장하지 않는다.
- `ios/Runner/GoogleService-Info.plist`, `macos/Runner/GoogleService-Info.plist`는 없다. 이번 Flutter Web 검증에는 사용하지 않으며, 해당 네이티브 플랫폼을 지원할 때 별도로 설정을 확인해야 한다.
- 시작 시 `Firebase.initializeApp`을 호출하고 Web은 `Persistence.LOCAL`로 세션을 유지한다. 새로고침 시 인증 이벤트를 기다린 뒤 Firestore에서 권한을 다시 확인한다.
- 이메일·비밀번호 로그인만 제공한다. 회원가입, 관리자 생성, 권한 변경 UI/API는 앱에 없다.
- `/users/{Firebase Auth UID}` 문서를 실시간 구독한다. 서버 확인 전 캐시·로컬 쓰기만으로 화면을 열지 않는다. 누락, 비활성화, 잘못된 역할·직원 매핑, 조회 실패 시 접근을 차단한다.
- 계정·역할 변경 및 로그아웃 시 기존 일정 화면과 열린 대화상자를 제거한다. Firestore 문서 변경으로 권한을 회수할 수 있다. Auth Console에서만 계정을 비활성화하면 SDK의 토큰 갱신 전까지 즉시 반영되지 않을 수 있으므로 긴급 회수 시 문서의 `active`도 `false`로 설정한다.
- 기존 기본 코스, 결석 처리, 직원·차량 배정, 방문 순서, 정원·근무 가능 여부·중복 배정 검증과 관리자 확인 후 확정 기능을 유지했다.
- **일정 데이터는 기존과 같이 메모리에만 저장된다. 새로고침·로그아웃·권한 화면 재생성 시 초기화되며 서로 다른 계정/기기 간 공유되지 않는다.** 직원 화면은 자신의 확정 일정만 표시하는 구조이나 서버에서 확정 일정을 불러오는 기능이 없어 현재는 빈 일정이 표시된다. 영구 저장과 공유는 별도 구현 과제다.
- 현재 번들에 포함된 코스·직원·이용자는 가상 데이터다. UI 접근 제어는 번들 내용의 기밀성을 보장하지 않는다. 실제 개인정보를 번들에 넣으면 안 된다.
- **보안 규칙은 작성만 되었으며 실제 Firebase에 배포하지 않았다. 운영 권한 보호가 완료된 상태가 아니다.**

## Firebase Console에서 직접 수행할 작업

1. 연결된 프로젝트의 Authentication → Sign-in method에서 Email/Password를 활성화한다.
2. Authentication → Settings → Authorized domains에 실제 사용할 Web 도메인을 등록한다. 로컬 실행 시 `localhost`도 확인한다.
3. Cloud Firestore 기본 데이터베이스를 생성한다. 테스트 모드의 전체 허용 규칙을 유지하지 않는다.
4. Authentication → Users → Add user에서 관리자와 직원용 가상 계정을 각각 생성한다. 비밀번호는 안전한 별도 방법으로 관리하고 코드·문서·Git에 기록하지 않는다.
5. 생성한 사용자의 **UID를 그대로 문서 ID**로 사용해 `users` 컬렉션에 아래 문서를 Console에서 직접 만든다. 이메일을 문서 ID로 사용하지 않는다.

관리자 문서 `/users/<관리자 UID>`:

```json
{
  "role": "admin",
  "active": true
}
```

직원 문서 `/users/<직원 UID>`:

```json
{
  "role": "staff",
  "active": true,
  "staffId": "s1"
}
```

`active`는 문자열이 아닌 boolean이다. 현재 가상 직원 ID는 `s1`, `s2`, `s3`이다. 각 Auth 계정에 올바른 직원을 매핑하고, 별개의 직원 계정에 같은 `staffId`를 잘못 지정하지 않도록 관리한다. 앱에서는 변경할 수 없다. 나중에 실제 직원 저장소를 도입하면 이 매핑 검증도 서버로 옮겨야 한다.

## 로그인은 되지만 사용 권한이 없다고 나오는 경우

`email`, `name`, `role: "admin"`만 등록한 문서는 필수 필드 `active`가 없어서 거부된다. `AppUser.fromDocument`는 `active`를 검사한 다음 `role`을 검사한다. 누락을 자동 승인하거나 앱에서 문서를 생성·보정하지 않는다. Console에서 **해당 Auth 사용자의 UID와 동일한 ID의 문서**에 `active` 필드를 **boolean true**로 추가한다. 기존 email과 name은 유지할 수 있으며 관리자에게 staffId는 필요하지 않다.

```json
{
  "email": "admin@example.com",
  "name": "관리자",
  "role": "admin",
  "active": true
}
```

| 필드 | 타입과 조건 | 필수 여부 |
|---|---|---|
| 문서 ID | 로그인한 Firebase Auth 사용자의 UID | 필수; 이메일이나 자동 생성 ID를 사용하지 않음 |
| active | boolean `true`여야 접근 허용; `false`이면 중지 | 모든 역할에 필수; 문자열 `"true"`는 거부 |
| role | 문자열 `"admin"` 또는 `"staff"`; 대소문자·공백도 일치해야 함 | 모든 역할에 필수 |
| staffId | 문자열 `"s1"`, `"s2"`, `"s3"` 중 본인 직원 ID | staff만 필수 |
| email, name | 권한 판정에서 사용하지 않는 선택 메타데이터 | 선택 |

앱의 조회 경로는 `FirebaseAuth.idTokenChanges()`에서 받은 `user.uid` → `collection('users').doc(uid)`이다. 이메일로 문서를 검색하지 않는다. Firestore의 email 필드를 Auth 이메일과 대조하여 권한을 부여하지도 않는다.

문서 미등록, active 누락, active 타입 오류, 비활성화, 잘못된 role, 직원 매핑 오류는 각각 별도의 안내를 표시한다. Firestore `permission-denied`는 보안 규칙에 의한 조회 거부로, `unavailable` 등은 네트워크 오류로 안내하며 문서 미등록으로 취급하지 않는다. 서버에서 확인하지 못한 캐시만으로는 승인하지 않는다. Console에서 수정한 뒤 화면의 **다시 확인**을 누를 수 있으며, 문서 구독이 유지 중이면 서버 변경이 자동 반영된다.

## 직원 계정이 인증 후 차단되는 경우와 진단 로그

관리자·직원 모두 동일한 이메일/비밀번호 Authentication 로그인을 사용한다. 로그인 진입점과 `AuthGate`에는 관리자만 허용하는 조건이 없다. 관리자 제한은 일정 수정·확정 기능에만 적용된다. 저장소의 Security Rules는 역할과 관계없이 자신의 `users/{uid}` 문서 조회를 허용한다. 실제 배포 규칙이 다르면 별도 확인이 필요하다.

`active: true`, `email`, `name`, `role: "staff"`만 등록하면 본인 일정의 직원 ID를 연결할 수 없어 `invalidStaffMapping`으로 거부된다. Console에서 해당 Auth UID 문서에 본인에 맞는 문자열 `staffId`를 추가해야 한다. 예를 들어 가상 직원 `s1`에 연결할 계정의 문서는 다음과 같다. 모든 직원에게 일괄적으로 s1을 지정하지 않는다.

```json
{
  "active": true,
  "email": "staff01@example.com",
  "name": "직원1",
  "role": "staff",
  "staffId": "s1"
}
```

앱이 자동으로 staffId를 추정하거나 문서를 수정하지 않는다. `s1`, `s2`, `s3` 중 실제로 연결할 가상 직원 ID를 운영자가 지정한다. 필드 추가 후 **다시 확인**을 누르거나 로그아웃 후 다시 로그인한다.

`flutter run -d chrome`의 터미널 또는 브라우저 개발자 도구 Console에서 `[auth]`를 검색한다. 기본 진단 로그는 debug 빌드에서만 출력하며, 이메일·이름·UID·비밀번호·토큰·문서 전체·원본 예외 메시지는 출력하지 않는다.

| 로그 예시 | 의미 |
|---|---|
| `[auth] authentication failed code=invalid-credential` | Authentication 로그인 실패; 아직 역할 문서 검증 단계가 아님 |
| `[auth] authentication succeeded` | Authentication 로그인 요청 성공 |
| `[auth] session authenticated` | 인증된 세션 이벤트 수신; 저장된 세션 복원 시에도 발생 |
| `[auth] profile started` | 로그인한 사용자의 UID로 역할 문서 확인 시작 |
| `[auth] profile failed code=invalidStaffMapping` | 문서 검증 단계에서 직원 ID 누락·잘못된 값 확인 |
| `[auth] profile failed code=permission-denied` | Firestore 조회 권한 거부; 배포된 규칙 확인 필요 |
| `[auth] profile failed code=unavailable` | 서버에서 역할을 확인하지 못함; 네트워크 또는 캐시 상태 확인 필요 |
| `[auth] profile succeeded role=staff` | 직원 역할 및 연결 정보 검증 완료 |
| `[auth] profile succeeded role=admin` | 관리자 역할 검증 완료 |

인증 이벤트와 로그인 요청 Future는 비동기이므로 로그 순서는 달라질 수 있다. 캐시 이벤트에서 일시적인 profile 오류가 나온 뒤 서버 이벤트에서 성공할 수도 있다. 마지막 profile 결과를 함께 확인한다. 로그에 Authentication 성공이 있어도 profile 성공 전에는 일정 화면을 열지 않는다.

## Firestore Security Rules 배포

프로젝트 루트에서 본인이 선택한 프로젝트 ID를 명시하여 실행한다.

```powershell
firebase deploy --only firestore:rules --project <프로젝트-ID>
```

또는 Console의 Firestore → Rules에 `firestore.rules`를 붙여 넣고 Publish한다. 이 작업은 기존 데이터베이스의 규칙 전체를 교체하므로 연결된 프로젝트와 기존 사용 컬렉션을 먼저 확인한다. `firebase.json`에 규칙 파일 경로를 추가했으며 기존 FlutterFire 설정은 유지했다.

규칙의 현재 정책:

| 요청 | 결과 |
|---|---|
| 비로그인 상태의 모든 문서 접근 | 거부 |
| 로그인한 사용자의 본인 `users/{uid}` 문서 get | 허용 |
| 다른 사용자의 역할 문서 조회 / users 목록 조회 | 거부 |
| 본인 또는 타인의 역할 문서 생성·수정·삭제 | 관리자 포함 모든 클라이언트에서 거부 |
| 일정 및 다른 모든 컬렉션 읽기·쓰기 | 거부 |

관리자 계정도 역할 문서를 편집할 수 없다. 신뢰할 수 있는 Console 운영자 또는 Admin SDK 서버만 계정을 프로비저닝한다. Admin SDK는 Security Rules를 우회하므로 운영자 IAM 및 서버 권한을 제한해야 한다.

클라이언트의 `role` 표시나 `ScheduleController` 검사는 서버 권한의 근거가 아니다. 현재 일정 서버 접근은 전부 차단했다. 향후 일정 저장 구현 시 신뢰할 수 있는 서버가 Auth UID로 사용자 문서의 `active`와 `role == admin`을 조회하고 직원 근무 가능 여부, 차량 정원, 중복 배정, 사람이 검토한 확정을 검증해야 한다. 직원에게는 본인이 담당하는 확정 일정만 서버에서 제공하고, 다른 직원의 데이터나 전체 초안이 포함된 문서를 내려주지 않아야 한다. AI가 자동으로 확정·게시하는 경로를 만들지 않는다.

회원가입 화면이 없다는 사실만으로 Firebase Auth의 외부 계정 생성 API까지 차단되지는 않는다. 외부에서 Auth 계정이 생성되더라도 신뢰 운영자가 등록한 사용자 문서 없이는 앱 접근이 거부된다. Auth 계정 생성 자체까지 제한할 필요가 있다면 Identity Platform의 지원 기능과 서버 정책을 별도로 설계해야 한다.

## 배포 후 직접 검증

1. 관리자 계정 로그인 → 관리자 화면·편집 기능 확인.
2. 직원 계정 로그인 → 직원 화면 확인, 역할 전환·타 직원 선택·편집 기능이 없는지 확인.
3. 페이지 새로고침 → 인증 복원 및 서버 권한 재확인. 로그아웃 후 새로고침·브라우저 뒤로 가기로 보호 화면에 돌아갈 수 없는지 확인.
4. 잘못된 비밀번호와 오프라인 상태에서 한국어 오류 안내 확인. 로그인 중 버튼이 비활성화되는지 확인.
5. Auth 계정만 있고 사용자 문서가 없는 경우, 잘못된 role/staffId, `active: false`에서 접근 거부 확인.
6. 열린 관리자 화면에서 Console로 역할을 `staff`로 바꾸거나 `active`를 false로 변경/문서를 삭제해 화면·확정 대화상자가 닫히는지 확인.
7. Firestore Rules Playground 또는 Emulator Suite에서 위 표의 각 요청을 직접 실행해 허용·거부 결과를 확인. 특히 직원 UID로 본인 `role: admin` 수정, 관리자 UID로 사용자 생성, 타인 문서 get, users list, 일정 read/write가 거부되는지 확인한다.

`flutter test`는 가짜 인증 저장소로 앱 흐름을 검사한다. 실제 Firebase 로그인, 브라우저 저장소의 세션 유지, 배포된 Security Rules 검증을 대신하지 않는다. 이번 환경에서는 Java 실행 환경이 확인되지 않아 Firestore Emulator의 규칙 실행 검증은 수행하지 않았다. 규칙 배포 및 위 검증까지 끝나기 전에는 권한 보호를 완료로 취급하지 않는다.

## 인증 단계 로컬 실행 결과

아래는 인증 기능 구현 단계의 기록이다. 이후 직원 중심 화면 변경과 전체 테스트 결과는 [staff-centered-schedules.md](staff-centered-schedules.md)를 참고한다.

- `flutter analyze`: No issues found.
- `flutter test`: 23개 테스트 모두 통과. 로그인 검증·로딩·중복 제출 차단·실패 안내, 인증 복원 이벤트, UID 전달, 관리자 문서의 active 누락 재현·보정, 직원 문서의 staffId 누락 재현·보정, Authentication 실패와 Firestore 권한 실패의 로그 구분 및 로그의 개인정보 미포함, 관리자/직원 분기, 로그아웃, 권한 변경 시 대화상자 폐기, 기존 일정 검증·편집 및 모바일 화면을 검사했다.
- `flutter build web`: 성공 (`build/web`).
- 실제 프로젝트에 대한 계정 로그인, 규칙 배포, Rules Playground/Emulator 검증은 미수행.

## 설정 및 비밀정보 관리

기존 FlutterFire 생성 파일의 값을 복사하거나 새 비밀번호·서비스 계정 키를 추가하지 않았다. Firebase 클라이언트 구성은 Web 번들에 포함되므로 서버 비밀키처럼 취급하여 보안을 의존할 수 없다. 실제 접근 권한은 배포된 Rules와 신뢰 서버가 보장해야 한다. 서비스 계정 JSON, Admin SDK 개인키, 개발 계정 비밀번호, 외부 API 비밀키는 앱에 포함하지 않는다.

공식 참고: [이메일 로그인](https://firebase.google.com/docs/auth/flutter/password-auth), [인증 상태와 세션 유지](https://firebase.google.com/docs/auth/flutter/start), [Firestore 보안 규칙](https://firebase.google.com/docs/firestore/security/rules-conditions), [규칙 테스트](https://firebase.google.com/docs/rules/unit-tests).
