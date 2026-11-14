# 운영 사진 기능 로컬 구현 및 배포 준비

2026-11-14. [설계안](work-photo-production-plan.md)을 구현했다. 실제 Firebase 접속/Storage 생성/IAM·Secret·Firestore 운영 설정 변경/사진 업로드/배포는 수행하지 않았다. 자동 삭제 함수는 export하지 않았다.

## 구현된 경로

- 기본 Emulator 빌드: 기존 FirebaseAttendanceRepository와 Firestore Blob 저장 유지.
- ENABLE_STORAGE_WORK_PHOTOS=true 빌드: WorkPhotoRepository가 registerWorkPhoto/getWorkPhotos Callable만 사용. 클라이언트 Storage SDK/Firestore 직접 사진 쓰기/공개 URL은 없음.
- 관리자 AI 미리보기는 AttendanceProvider가 없어 계속 사진 등록 불가. 운영 사진은 서버에 이미 확정된 가상 일정으로만 테스트한다.
- 기존 일정/결근/AI 함수 구현과 firestore.rules는 이번 작업에서 변경하지 않았다. Functions 진입점에는 사진 두 함수만 추가했다. Gemini Secret은 여전히 suggestSchedule에만 연결한다.

## 서버 계약

registerWorkPhoto 입력:

```json
{
  "date": "YYYY-MM-DD",
  "period": "morning",
  "routeId": "실제 확정 코스 ID",
  "kind": "start",
  "requestId": "클라이언트 생성 요청 ID",
  "photoBase64": "JPEG 바이트의 base64",
  "expectedVersion": 1,
  "expectedAvailabilityVersion": 0
}
```

period는 morning/afternoon, kind는 start/end. 직원 ID·UID·등록 시각·파일 경로는 입력받지 않는다. 서버가 Auth UID → 활성 users.staffId로 결정한다. 한국 시간 당일만 등록, 활성 직원·확정 원본/projection·단일 코스·버전/내용 일치·준비된 가상 catalog/활성 직원·실제 결근 버전을 검사한다. 종료는 같은 소유자의 시작 기록이 먼저 있어야 한다.

JPEG 상한 184320바이트, 입력 400만 픽셀, 실제 디코딩/재인코딩과 EXIF 제거를 수행한다. PNG/MIME 위장/잘린 이미지/초과 바이트·픽셀을 거절한다. sharp는 보안 수정 버전 0.35.5로 고정했다.

getWorkPhotos는 staffId/date/period로 메타데이터를 20건씩 조회한다. nextCursor가 있으면 cursor로 다음 페이지를 요청한다. recordId를 추가하면 그 기록의 이미지 base64를 반환한다. 전체 collection 스캔 대신 문서 ID의 날짜·시간대 prefix 범위를 사용한다. 본인 UID와 staffId가 모두 일치하는 활성 직원, 또는 활성 관리자만 조회한다. 임의 Storage 경로를 받지 않으며 generation/해시/크기를 검증한다. 만료 사진은 반환하지 않는다.

새 사진 완료 문서는 별도 **workPhotoRecords/{staffId}/records/{date}_{period}_{routeId}_{kind}**에 schemaVersion=2로 추가한다. photo는 Blob 대신 bucket/path/generation/sha256/size/contentType 맵이다. registeredAt은 서버 timestamp, expiresAt은 서버 계산 30일이다. catalogVersion/scheduleVersion/availabilityVersion/operationId/uid도 보존한다. 기존 Emulator Blob의 attendance 경로는 그대로 두어 같은 날짜·직원·코스여도 섞이지 않는다. 새 collection은 기존 Firestore 기본 거부 규칙에 따라 클라이언트 직접 접근이 차단되고 Callable만 사용한다.

## 실패·중복·복구

_workPhotoOperations는 UID+requestId 해시로 식별하고 사진/입력 fingerprint를 묶는다. _workPhotoSlots는 직원·날짜·시간대·코스·시작/종료별 120초 처리 잠금을 제공한다. 모든 Firestore 읽기는 해당 트랜잭션의 쓰기보다 먼저 수행한다.

예약 → 트랜잭션 밖 생성 전용 Storage 업로드 → 계정/일정/결근/설정/잠금 재검증 → 완료 문서와 operation 완료 상태를 원자적으로 저장한다. Storage 업로드는 ifGenerationMatch=0을 사용한다. 파일만 저장된 실패는 정상 기록으로 표시하지 않는다.

동일 요청/동일 사진은 최초 결과를 반환한다. 같은 ID/다른 내용은 거절한다. 처리 중에는 중복 실행하지 않고, lease 만료 후 같은 요청으로 재확인/복구할 수 있다. 잠금을 넘겨받은 새 요청이 있으면 이전 실행은 완료 기록을 만들 수 없다. 응답이 불확실하면 먼저 사진 기록을 새로고침한다. Flutter는 같은 사진의 실패한 요청 ID를 메모리에 보존하며 자동 재시도하지 않는다. 브라우저 재시작 시 이 임시 ID는 사라지지만 서버의 슬롯/최초 완료 문서 보호는 유지된다.

운영 조회는 최초 조회·등록 후 갱신·명시적 사진 기록 새로고침 방식이다. 관리자 실시간 사진 push는 추가하지 않았다. 사진 저장소 오류는 기존 일정 구독/확정을 변경하지 않는다.

## 로컬 실행

```powershell
powershell.exe -ExecutionPolicy Bypass -File tools/start_operations_emulators.ps1 -StoragePhotos
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=ENABLE_STORAGE_WORK_PHOTOS=true
```

기본 포트는 **Auth9099, Firestore8080, Functions5001, Storage9199**다. 기존 Emulator 계정/가상 catalog/확정 일정을 재사용하고 충돌 데이터를 삭제하지 않는다. 이번 자동 검사는 별도 9198/8190/5102/9298 포트와 demo namespace를 사용했다.

Storage 방식에서는 Emulator UI/안전한 Admin SDK로 **로컬** _workPhotoControl/config에 아래 구조를 준비해야 한다. 실제 catalogVersion을 배열에 넣고 처음에는 enabled=false로 둔 뒤 로컬 테스트할 때만 true로 바꾼다. 기존 Blob 방식에는 이 문서가 필요 없다.

```json
{
  "enabled": false,
  "allowedCatalogVersions": ["확정 일정에 사용된 가상 catalogVersion"],
  "requireAppCheck": false
}
```

운영에서도 동일 필드/타입을 사용한다. 설정이 없거나 enabled가 정확히 true가 아니면 등록을 거절한다. false는 **신규 등록 중지**이며 기존 본인/관리자 기록 조회는 유지한다. requireAppCheck=true는 등록·조회 모두 토큰을 요구한다. 토큰 발급 확인 전 강제하지 않는다. App Check와 별개로 Auth 검증은 항상 수행한다. 배포 자체가 기존 enabled 값을 초기화하지 않는다.

## 보존 및 수동 정리

완료 사진은 30일 후 서버 조회 차단. 만료 완료 기록과 24시간 이상 남은 미완료/고아 객체를 수동 정리 도구가 처리한다. 자동 실행하지 않으므로 미완료 파일의 24시간 내 실제 삭제는 아직 보장하지 않는다. 테스트 종료 후 운영자가 dry-run을 확인해 수동 실행하고, 정기 삭제 활성화는 별도 승인 대상으로 남긴다.

cleanup-work-photos.cjs는 기본 읽기 전용이다. 명시적 프로젝트/버킷과 ADC를 사용하고 키 파일을 저장하지 않는다. 정리 대상 operation 경로·파일 해시·generation을 검사하며 다른 prefix/새 완료 기록을 삭제하지 않는다. 삭제 중 중단돼도 다음 실행에서 재개할 수 있다. Firestore TTL이나 버킷 전체 lifecycle을 자동 설정하지 않는다.

```powershell
# 미래 운영자용 읽기 전용 dry-run 예시. 이번에는 실행하지 않음.
node tools/cleanup-work-photos.cjs --project senior-transport-app --bucket ACTUAL_PHOTO_BUCKET
# 삭제 대상 확인·별도 승인 후에만 사용할 명시적 실행 옵션:
node tools/cleanup-work-photos.cjs --project senior-transport-app --bucket ACTUAL_PHOTO_BUCKET --apply --confirm-project senior-transport-app --approve-delete-work-photos
```

Emulator에서는 --project demo-senior-transport와 해당 demo 버킷을 지정하고 loopback FIRESTORE_EMULATOR_HOST/FIREBASE_STORAGE_EMULATOR_HOST가 모두 있어야 한다. 실제 프로젝트 경로는 Emulator 환경 변수를 거절한다. 실제 운영 삭제는 이번에 활성화/실행하지 않았다.

## 실제 Firebase에서 필요한 설정 — 아직 수행하지 않음

1. Blaze/결제 계정, Storage API, 실제 버킷 존재·이름·위치를 확인한다. firebase_options.dart의 문자열만으로 생성 완료로 판단하지 않는다. 새 버킷이 필요하면 별도 승인 후에만 만든다.
2. WORK_PHOTO_BUCKET 문자열 파라미터를 실제 사진 버킷 이름으로 설정한다. 운영자가 기존 functions/.env.senior-transport-app 내용을 보존하면서 WORK_PHOTO_BUCKET 항목만 추가/수정할 수 있다. 버킷 이름은 키가 아니며 사진 함수에 새로운 Secret은 필요 없다. 기본값은 빈 문자열이라 미설정 시 연결을 거절한다. firebase.json의 Storage Rules 배포 대상과 같은 버킷인지 확인한다. 별도 버킷을 쓰면 Firebase Storage target 설정도 먼저 명시적으로 구성한다.
3. 사진 전용 런타임 서비스 계정 **work-photos@senior-transport-app.iam.gserviceaccount.com**을 준비한다. 새 두 함수만 이 계정을 사용하도록 로컬 manifest에 지정했다. 아직 계정/IAM은 생성하지 않았다. Firestore용 roles/datastore.user, 지정 사진 버킷의 roles/storage.objectCreator와 roles/storage.objectViewer를 검토한다. 기존 일정·AI 계정에 새 권한을 주지 않는다. 이 계정에 Gemini Secret 권한이나 사진 삭제 권한은 필요 없다. 배포 운영자는 이 계정으로 배포할 수 있는 actAs 권한도 확인한다.
4. 버킷은 공개 IAM/ACL 금지, uniform bucket-level access/public access prevention을 확인한다. Storage Rules가 거절해도 별도 공개 IAM 경로가 열려 있으면 비공개라고 판단하지 않는다.
5. **현재 storage.rules는 버킷 전체 클라이언트 접근을 거절한다.** 다른 앱/파일이 이미 사용하는 버킷이면 그대로 배포하면 안 된다. 사진 전용 버킷인지 확인하거나 기존 규칙을 보존한 사진 prefix 전용 거절 정책으로 별도 검토해야 한다. 원격 Rules는 이번에 읽거나 변경하지 않았다.
6. _workPhotoControl/config를 enabled=false로 준비하고 허용 가상 catalog를 검토한다. 실제 직원 계정의 staffId 연결과 당일 확정 일정이 있어야 한다. AI 미리보기에는 확정 기록이 없어 등록할 수 없다.

Storage CORS/공개 URL/새 Secret은 이 Callable 방식에서 필요 없다. Functions의 사진 전용 계정이 객체를 생성·읽고, 수동 정리는 별도 운영자 ADC로만 삭제한다.

## 안전한 배포 순서와 명령 — 향후 별도 승인 후

1. 코드 리비전·원격 Rules·기존 함수 상태 백업/비교, 위 버킷/IAM/비활성 설정 확인.
2. 로컬 manifest와 테스트 확인, 사진 버킷 Rules만 배포.
3. 사진 함수 두 개만 선택 배포. 기존 세 함수/Firestore Rules는 배포하지 않음.
4. 서버 enabled=false 상태에서 Web release 빌드·정적 파일 검사·Hosting 배포. 기존 AI 플래그를 유지할 경우 아래처럼 두 옵션을 함께 전달.
5. 별도 승인 후 가상 catalog에서 enabled=true로 시작/종료/관리자 조회/타 직원 거절/중복 테스트. 종료 후 enabled=false. 삭제 자동화는 계속 비활성.

```powershell
node tools/verify-functions-build.cjs
firebase.cmd deploy --only storage --project senior-transport-app
firebase.cmd deploy --only "functions:registerWorkPhoto,functions:getWorkPhotos" --project senior-transport-app
powershell.exe -ExecutionPolicy Bypass -File tools/build-hosting.ps1 -EnableProductionAi -EnableStorageWorkPhotos
node tools/verify-hosting-build.cjs
firebase.cmd deploy --only hosting --project senior-transport-app
```

위 명령은 안내이며 이번에 배포하지 않았다. Emulator 사진용 debug 빌드와 실제 Firebase 연결용 release 빌드를 모두 로컬 검증했다. 현재 build/web은 **사진·기존 AI 옵션을 켠 release 빌드**이며 fingerprint는 `5087694aec5d5687f058be937b8179a564bd51f712e5abae37715d148cd1f293`다. 먼저 서버/IAM/비활성 설정을 준비한 후에만 Hosting에 반영한다. 기존 AI 테스트 미리보기 빌드 옵션은 이 일반 운영 빌드에 자동 포함되지 않는다.

장애 시 enabled=false로 신규 등록을 멈추고 사진 플래그를 끈 Web으로 되돌린다. 기존 사진/operations/slots를 즉시 지우지 않는다. 먼저 메타데이터 조회 → 같은 요청/사진으로 재확인(처리 중이면 lease 만료 후) → 정리 dry-run 순서로 확인한다. 실제 사진 보관 문제를 해결하려고 기존 일정·AI 함수나 사용자 계정을 롤백하지 않는다. 필요하면 이전 사진 함수 소스만 선택 재배포한다.

## 비용·남은 확인

20명 × 하루 오전/오후 × 시작/종료 = 최대 하루 80장. 180KiB 상한 기준 30일 약 422MiB. 이미지 조회/base64 약 4/3 전송량, Storage 작업/전송/soft delete, Callable 실행/통신, Firestore 메타데이터·operations·slots 읽기/쓰기, Build/Artifact가 비용 지점이다. 자동 Scheduler는 도입하지 않아 해당 예약 실행 비용은 현재 없다. 버킷별 무료 대상/리전 단가를 확인하고 예산 알림을 설정한다. 실제 과금·IAM·Storage soft delete·기기 카메라/HEIC 호환성은 로컬 테스트로 완료했다고 판단하지 않는다.

Android Chrome/iOS Safari/홈 화면 PWA에서 촬영·선택·취소·권한 거절·카메라 복귀·네트워크 중단을 수동 확인해야 한다. picker는 capture 없는 사진 선택과 capture=environment 촬영을 구분하며, cancel 이벤트가 오지 않는 브라우저에는 3분 뒤 안전하게 오류를 표시해 무한 대기를 막는다. 사진은 등록 시각이며 위치/얼굴/급여용 근무 인증이 아니다.

운영 의존성 audit에서 sharp의 high 항목은 수정 버전으로 해결했다. 기존 Firebase Admin 하위 의존성의 moderate 8개는 남아 있다. 개발 의존성을 포함한 audit에는 추가 high 항목이 있어, 배포 전 별도 의존성 업데이트 검토가 필요하다. 기존 일정·AI 의존성을 강제 major 업데이트하지 않았다.

## 변경 파일 및 검증

- functions/work-photo-service.js, work-photos.js, index.js: 새 사진 서비스/Callable/전용 런타임 계정.
- functions/package.json/package-lock.json: sharp 고정 및 플랫폼별 바이너리 잠금.
- storage.rules, firebase.json: 클라이언트 거절 및 Storage Emulator 설정.
- lib/services/work_photo_repository.dart, attendance_repository.dart, schedule_repository.dart: 분리된 서버 저장소·버전 전달·선택 플래그.
- lib/services/demo_photo_picker_web.dart/_stub.dart, lib/screens/attendance_screen.dart: 카메라/선택 분리, 오류·명시적 새로고침.
- tools/cleanup-work-photos.cjs, start_operations_emulators.ps1, test-emulators.ps1, build-hosting.ps1, verify-functions-build.cjs: 수동 정리·실행 옵션·manifest 검사.
- functions/test/work-photos.test.cjs, function-entry.test.cjs, test/work_photo_repository_test.dart, attendance_test.dart: 새 통합/권한/복구/UI 회귀.

검증: flutter analyze 문제 없음, Flutter 전체 246개 통과, Auth/Firestore/Storage/Functions Emulator 전체 175개 통과(실패·취소 0), Emulator 사진 옵션 Web debug 빌드 및 실제 Firebase용 Web release/Hosting 정적 안전 검사 통과, 운영 함수 manifest 5개 export 검증 통과(사진 Secret 연결 0). 실제 Callable HTTP 등록·조회, 서버 JPEG/EXIF·크기/픽셀 제한, 권한·직접 접근 차단, 결근/인계/계정 비활성화 중단, 요청 중복/네트워크 실패/lease 복구/정리 dry-run·재실행, 기존 Blob 보존을 포함한다. 기존 일정·AI 회귀도 전체 실행했다. git diff --check도 통과했다.

로그: .local-tools/work-photo-{analyze-final,flutter-final,web-build,production-release,storage-emulator-complete}.log. Storage 검증용 사진은 코드로 만든 합성 JPEG만 사용했다. 실제 이용자 사진·외부 Gemini는 사용하지 않았다. 테스트 환경에서 발생한 HTTP 경로/fixture 충돌은 수정했고, 최종 실행은 공개된 npm test 스크립트의 파일별 직렬 실행으로 수행한다. 개별 동시 요청 검사는 그대로 포함한다.
