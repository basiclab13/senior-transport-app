# 사진 기반 업무 시작·종료 기록 MVP

## 범위와 저장 방식

직원 일정 화면의 기존 사진 안내 버튼을 실제 등록 화면으로 교체했다. 관리자는 직원 상세의 **업무 시작·종료 기록 보기**에서 선택한 날짜·오전/오후의 사진과 등록 시각을 조회한다. 직원은 본인의 확정 코스에만 등록하며 다른 직원의 사진을 조회할 수 없다.

이번 프로토타입은 기존 Firestore만 사용한다. 브라우저에서 사진을 JPEG로 다시 만들고 최대 180KiB로 줄인 뒤 사진 바이트와 메타데이터를 한 문서에 원자적으로 저장한다. 별도 Storage 서비스, Storage Emulator, Functions, 사진 선택 플러그인을 추가하지 않았다. 기존 잠금 파일에 있던 `web` 패키지를 브라우저 API 사용을 위한 직접 의존성으로 선언했다. 이미지 원본 이름·주소·EXIF/GPS 메타데이터는 저장하지 않는다.

일반 사진 저장 서비스로 확장하는 설계는 아니다. Firestore 문서 크기 제한을 고려한 작은 시연용 사진만 지원하며, 실제 운영에서는 Storage와 보존·삭제 정책을 별도 검토해야 한다. 위치·얼굴·도착 여부를 판별하지 않는다.

## 문서 구조와 권한

경로: `attendance/{staffId}/records/{date}_{period}_{routeId}_{kind}`

| 필드 | 타입 | 값 |
|---|---|---|
| staffId | string | 로그인 사용자의 `users/{uid}.staffId` |
| uid | string | 실제 로그인 UID |
| date | string | 선택한 확정 일정의 `YYYY-MM-DD` |
| period | string | `morning` 또는 `afternoon` |
| routeId | string | 확정 코스의 `baseRouteId` |
| kind | string | `start` 또는 `end` |
| registeredAt | timestamp | `FieldValue.serverTimestamp()` |
| photo | bytes | JPEG, 1~184320바이트 |
| contentType | string | `image/jpeg` |

`date`는 일정의 날짜이고 `registeredAt`은 실제 서버 등록 시각이다. 과거·미래 일정 사진을 오늘의 근무로 인증하지 않는다. 화면은 등록 시각을 한국 시간으로 표시하며 촬영 시각이라고 표시하지 않는다.

로컬 Security Rules에서 다음을 검사한다.

- 활성 직원 본인의 `staffId`·UID만 생성 가능. 관리자도 사진을 대신 등록할 수 없다.
- `staffSchedules/{staffId}/days/{date}_{period}`의 확정된 단일 코스와 일치해야 한다. 활성 직원과 준비 완료 catalog를 확인한다.
- 해당 시간대의 결근 기록이 있으면 기존 확정 코스가 남아 있어도 생성 차단. 인계 완료 후 이전 직원의 projection이 제거되면 등록 차단.
- 종료 사진은 같은 직원·날짜·시간대·코스의 시작 사진 이후에만 등록 가능.
- 시각은 서버 시각이어야 하며 추가 필드, 빈 사진, 용량 초과, 잘못된 경로를 거부한다.
- 관리자와 본인만 조회 가능. 모든 클라이언트의 수정·삭제는 차단한다.
- 생성 토큰의 프로젝트 audience가 `demo-`로 시작해야 한다. 클라이언트도 `USE_FIREBASE_EMULATORS=true`와 `demo-senior-transport` 프로젝트를 모두 요구한다.

사진과 시각은 같은 트랜잭션으로 저장한다. 결정적인 문서 ID를 사용하고, 재시도 시 이미 저장된 첫 기록을 반환한다. 화면에서도 기존 등록 버튼을 비활성화한다. 사진 선택·확인 취소는 쓰기를 발생시키지 않는다. 조회 실패·캐시만 있는 상태에서는 업로드하지 않고, 사진 확인 중 일정이나 결근 정보가 바뀌어도 등록을 차단한다. 등록 순간의 최종 권한은 Rules가 다시 확인한다. 사진 삭제·교체 UI는 이번 범위에 없다.

기존 일정·users·catalog 데이터와 AI/B-1/B-2, 확정 Functions를 변경하지 않는다. 결근·인계 이후에도 이미 작성된 사진 기록은 이력으로 남아 관리자와 본인이 조회할 수 있다.

## 로컬 시연

기존 Emulator를 사용한다면 데이터를 삭제하거나 다시 초기화할 필요가 없다. 단, 실행 중인 Firestore Emulator가 최신 로컬 Rules를 사용하는지 확인한다. 실제 Firebase의 Rules/Functions/Hosting에는 배포하지 않는다.

새 로컬 시연 환경을 준비할 때는 기존 절차를 재사용한다.

```powershell
# 터미널 1: Auth 9099, Firestore 8080, Functions 5001
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/start_operations_emulators.ps1

# 터미널 2: 기존 계정과 20명/80명 가상 데이터가 이미 있으면 등록 도구는 생략
$env:GCLOUD_PROJECT = 'demo-senior-transport'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
# EMULATOR_USER_PASSWORD는 기존 로컬 계정 비밀번호를 안전하게 설정하고 출력하지 않는다.
node tools/prepare_operations_emulator.cjs

flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=true
```

기존 도구는 충돌 문서나 계정 비밀번호를 덮어쓰지 않는다. 준비 실패 시 [기존 환경 안내](operations-scale-validation.md)와 안전한 진단 메시지를 확인한다. 기존 Emulator가 사용 중인 포트에서 새 인스턴스를 시작하지 않는다.

1. 직원 계정으로 로그인하고 본인에게 **확정된 일정**의 날짜·시간대를 선택한다. 기본 코스만 있고 아직 확정하지 않았다면 관리자가 기존 절차로 확정한다.
2. 직원 첫 화면의 **업무 시작 사진 등록**에서 개인정보가 없는 빈 종이·소품 등의 시연용 사진을 고른다. PC는 파일 선택, 지원하는 모바일 브라우저는 카메라 선택 기능을 사용한다. [직원 화면 개선](staff-ux.md) 이후 별도 사진 페이지 이동 없이 등록하며 시작 등록 후에는 종료 버튼이 표시된다.
3. 사진을 확인하고 **시연용 사진으로 등록**을 누른다. 등록 시각과 사진을 확인한 뒤 종료 사진도 등록한다.
4. 새로고침 후 같은 날짜·시간대를 열어 두 기록이 남아 있는지 확인한다.
5. 관리자 계정으로 로그인하고 같은 날짜·시간대의 해당 직원을 선택한다. **업무 시작·종료 기록 보기**에서 두 사진·코스·등록 시각을 확인한다.
6. 다른 직원에게는 해당 사진이 공개되지 않는다. 결근 직원, 코스가 없는 직원, 인계 전 담당자는 새 사진을 등록할 수 없다.

현재 시간 정책에 따라 초기 날짜·시간대가 달라질 수 있으므로 시연 시 관리자·직원의 선택값을 일치시킨다. 시연 사진과 기록도 Emulator 메모리에 저장된다. Emulator 종료 후에도 필요하다면 기존 snapshot export/import 절차를 사용한다. 실제 Firebase에 옮기지 않는다.

## 검증 결과

- `flutter analyze`: 문제 없음.
- `flutter test`: 191개 통과. 신규 8개: 시작·종료, 재조회, 취소, 등록 실패·재시도, 오래된 화면 차단, 미배정, 관리자 조회, 작은 화면, Emulator 제한을 검증한다(일부는 한 테스트에 함께 포함).
- Auth/Firestore/Functions Emulator 전체 테스트: 110개 통과. 신규 사진 권한 시나리오 8개와 상위 통합 테스트를 포함한다. 실제 20명/80명 fixture를 확정한 뒤 서버 시각·종료 선행 조건·잘못된 배정·결근·인계·역할·타 직원 접근·중복 덮어쓰기·삭제·용량 제한을 검사했다.
- `flutter build web --debug --dart-define=USE_FIREBASE_EMULATORS=true --no-pub`: 성공. 브라우저 사진 선택·JPEG 변환 코드와 Wasm 사전 컴파일 검사도 통과했다.
- Emulator 회귀 테스트는 기존 실행 중인 환경을 건드리지 않도록 별도 포트(9198/8190/5102)와 별도 demo namespace에서 실행했다. 운영 프로젝트 접근·배포·기존 데이터 삭제는 수행하지 않았다.
- 실제 기기 카메라 촬영은 수동 시연 확인 항목이다. 자동 Flutter 테스트는 고정된 가상 사진 선택기를 사용하고, Firestore Rules는 실제 Emulator에서 검증한다. Gemini 외부 API는 호출하지 않았다.

로컬 검증 로그: `.local-tools/attendance-all-flutter-tests.log`, `.local-tools/attendance-emulator-tests.log`, `.local-tools/attendance-web-build.log`.

## 이번 작업의 변경 파일

| 파일 | 변경 내용 |
|---|---|
| `lib/models/attendance_record.dart` | 시작·종료 기록, 문서 ID, 용량 상한, 한국 시간 표시 |
| `lib/services/attendance_repository.dart` | Emulator 제한, 실시간 조회, 서버 시각·사진의 원자적 등록, 재시도 처리 |
| `lib/services/demo_photo_picker{,_web,_stub}.dart` | Web 사진 선택과 JPEG 축소, 비 Web 환경 안내 |
| `lib/screens/attendance_screen.dart` | 기존 안내 화면을 사진 확인·등록·기록 조회 화면으로 교체 |
| `lib/screens/staff_schedule_view.dart`, `lib/screens/admin_schedule_view.dart` | 직원 등록 진입점과 관리자 조회 진입점 |
| `lib/services/schedule_repository.dart`, `lib/services/schedule_controller.dart` | 기존 repository에서 사진 repository를 제공하는 연결만 추가 |
| `firestore.rules` | 사진 경로의 본인 생성·관리자 조회·변경 금지 규칙 |
| `pubspec.yaml`, `pubspec.lock` | 기존 `web` 버전을 직접 의존성으로 선언 |
| `test/attendance_test.dart`, `functions/test/attendance.test.cjs` | 새 Flutter 흐름과 Emulator 권한 통합 테스트 |
| `test/staff_schedule_test.dart`, `test/auth_test.dart` | 미연결 환경 안내와 로그아웃 화면 제거 회귀 검증 유지 |
| `docs/attendance-photo-mvp.md` | 구조·제한·시연 절차·검증 결과 |

위 목록은 이번 사진 기록 작업의 범위다. 작업 전에 있던 AI·방문 시각 기능의 미커밋 변경사항은 보존했다. `firebase.json`, 기존 fixture 등록 도구, Functions 구현은 이번 작업에서 수정하지 않았다.
