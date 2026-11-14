# 사진 기능 운영 배포 전 실제 환경 읽기 전용 점검

점검: 2026-11-14 13:49 KST, senior-transport-app. Firebase CLI의 기존 인증으로 Google Cloud/Firebase API를 읽었다. gcloud는 활성 계정이 없어 실패했으며 새 로그인/계정 전환은 하지 않았다. Secret 값/키 파일/사진 내용/사용자 프로필은 조회하지 않았다. 버킷·계정 생성, IAM·Firestore 변경, API 활성화, 배포, 사진 업로드는 하지 않았다. 앱 코드/설정도 변경하지 않았다.

## 실제 확인 결과

| 항목 | 결과 |
| --- | --- |
| 앱용 기본 Storage 버킷 | **없음**. senior-transport-app.firebasestorage.app, senior-transport-app.appspot.com 모두 목록에 없음 |
| 실제 GCS 버킷 | 아래 Cloud Functions 인프라용 2개만 존재 |
| 사진 서비스 계정 | work-photos@senior-transport-app.iam.gserviceaccount.com 없음 |
| 배포 함수 | confirmSchedule, setStaffAbsence, suggestSchedule 3개 ACTIVE; 사진 함수는 미배포 |
| 리전/런타임 | asia-northeast3 / nodejs22 |
| 기존 런타임·빌드 계정 | 387017587964-compute@developer.gserviceaccount.com |
| 기존 계정 프로젝트 역할 | roles/editor 포함; 사진 계정에 이 넓은 역할을 복제하지 않음 |
| Cloud Billing | billingEnabled=true. 연결된 결제 계정 ID는 출력/보관하지 않음. Firebase Console의 Blaze 표시도 운영자가 재확인 |
| API | storage.googleapis.com, Cloud Functions, Run, Firestore, Build, Artifact Registry 활성. firebasestorage.googleapis.com은 활성 목록에 없음 |
| 배포 Storage Rules | firebase.storage release 없음 |
| 사진 제어 문서 | _workPhotoControl/config 없음 → 등록 기본 비활성 |
| WORK_PHOTO_BUCKET | .env.local에는 빈 값, .env.senior-transport-app에는 항목 없음. 다른 환경변수 값은 읽어 출력하지 않음 |
| 활성 catalog 포인터 | deploy-test-v2 |
| 가상 catalog | deploy-test-v2 ready/fictional=true; ai-test-25x80-v1 ready/fictional/testData=true |
| 당일 확정 일정 | 2026-11-14 오전·오후 모두 deploy-test-v2, confirmed, version=1, 각각 2코스 |
| 로컬 manifest 검사 | 새 사진 함수 포함 5개 export VERIFIED. 이 결과를 실제 5개 배포 완료로 해석하지 않음 |

현재 버킷과 파일(파일 내용은 읽지 않고, 개별 파일명은 출력하지 않으며 객체 목록 메타데이터만 집계):

| 버킷 | 리전 | 현재 live 객체 | 용도/보존 설정 |
| --- | --- | ---: | --- |
| gcf-v2-sources-387017587964-asia-northeast3 | ASIA-NORTHEAST3 / STANDARD | 3개, 190472 bytes | Functions 소스. 버전 관리 사용, 이전 버전 3개 초과 정리 정책 |
| gcf-v2-uploads-387017587964.asia-northeast3.cloudfunctions.appspot.com | ASIA-NORTHEAST3 / STANDARD | 5개, 287618 bytes | Functions 업로드. age=1일 삭제 정책 |

두 버킷 모두 workPhotos/ 객체와 image/* 객체는 0개였다. live 객체 집계이며 noncurrent/soft-deleted 세대까지 포함한 총사용량은 아니다. 두 버킷 모두 UBLA=true, publicAccessPrevention=inherited, soft delete 7일이다. 조회한 프로젝트·버킷 정책에 allUsers/allAuthenticatedUsers 객체 접근 바인딩은 없었다. 프로젝트 권한 상속이 있으므로 필터링된 직접 bucket SA 바인딩이 없다고 접근 권한이 없다고 판단하지 않는다.

**이 두 버킷을 사진용 WORK_PHOTO_BUCKET으로 지정하지 않는다.** 특히 업로드 버킷은 사진이 하루 뒤 삭제될 수 있다. 빌드용 버킷의 IAM/lifecycle/Rules를 변경하지 않는다.

기존 세 함수의 Cloud Run 진입점은 roles/run.invoker에 allUsers가 있다. 이는 Firebase Callable을 브라우저에서 호출하는 HTTP 진입 권한이며 서버 Auth/role 검증을 없애는 설정이 아니다. 이번에는 이 정책을 변경하지 않았다. 새 사진 함수도 일반 직원에게 Google Cloud IAM을 부여하는 방식이 아니라 Callable 내부의 Firebase Auth/프로필 검사로 보호한다.

## 이후 운영자가 직접 진행할 준비 절차 — 이번에는 실행하지 않음

### 1. CLI 작업자 인증 확인

현재 gcloud에는 활성 계정이 없다. 명령을 실행할 운영자가 직접 로그인한 뒤 아래 읽기 명령으로 계정/대상을 확인한다. 서비스 계정 JSON 키를 만들거나 Git에 저장하지 않는다. 이번 API 읽기에 사용된 Firebase CLI 작업자는 프로젝트 owner 역할이었지만 다른 gcloud 계정의 권한까지 보장하지 않는다.

```powershell
gcloud auth login
gcloud auth list
gcloud billing projects describe senior-transport-app --format="value(billingEnabled)"
gcloud storage buckets list --project senior-transport-app
firebase.cmd functions:list --project senior-transport-app
```

.firebaserc는 현재 없으므로 모든 Firebase 명령에 --project senior-transport-app을 명시한다.

### 2. 사진용 기본 버킷 준비

Firebase Console → senior-transport-app → Storage → 시작하기. Blaze/결제 상태를 확인하고 비공개/운영 모드로 기본 버킷을 만든다. 위치는 함수와 같은 asia-northeast3(Seoul), Standard를 우선한다. 생성은 실제 리소스 변경이므로 별도 실행 단계다. 현재 Spark라고 단정하거나 재전환을 자동 수행하지 않는다.

새 기본 버킷은 일반적으로 senior-transport-app.firebasestorage.app이지만 생성 완료 화면과 다음 조회에서 실제 이름을 확인한 다음 사용한다. 기존 gcf-* 버킷을 재활용하지 않는다. Firebase Console이 요구하는 Storage API 활성화를 확인한다. 수동 API 활성화가 필요한 경우의 명령은 아래와 같지만 이번에는 실행하지 않았다.

```powershell
gcloud services enable firebasestorage.googleapis.com --project senior-transport-app
```

생성 후 확인/보호 설정 명령(실제 이름이 위와 같을 때):

```powershell
$photoBucket = 'senior-transport-app.firebasestorage.app'
gcloud storage buckets describe "gs://$photoBucket" --project senior-transport-app
gcloud storage buckets get-iam-policy "gs://$photoBucket" --project senior-transport-app
# 신규 사진 버킷에만 적용하는 변경 명령. 기존 gcf-* 버킷에는 실행하지 않음.
gcloud storage buckets update "gs://$photoBucket" --uniform-bucket-level-access --public-access-prevention --project senior-transport-app
```

현재 storage.rules는 버킷 전체 클라이언트 read/write를 거절한다. 새 사진 전용 기본 버킷에 배포하면 기존 Functions 인프라 버킷/일정/AI에는 적용되지 않는다. 생성 사이 다른 앱이 쓰기 시작했다면 다시 확인한다. Rules는 IAM을 통한 Admin SDK 접근을 차단하지 않으므로 공개 IAM/ACL도 함께 막아야 한다. 브라우저는 Callable만 사용하므로 Storage CORS나 공개 URL은 필요 없다.

기본 버킷을 선택하면 현재 firebase.json의 storage.rules 설정을 사용할 수 있다. 다른 이름의 추가 버킷을 선택한다면 먼저 Firebase에 연결하고 deploy target을 구성해야 한다. 그 경우의 로컬 변경 예시:

```powershell
firebase.cmd target:apply storage workPhotos ACTUAL_BUCKET_NAME --project senior-transport-app
```

firebase.json의 storage를 [{"target":"workPhotos","rules":"storage.rules"}]로 바꾸고 --only storage:workPhotos로 선택 배포한다. 이 대안은 이번에 적용하지 않았다. 기본 버킷 방식과 섞어서 실행하지 않는다.

### 3. 사진 전용 서비스 계정과 최소 사전 정의 역할

코드에 지정된 정확한 계정 이름은 work-photos@senior-transport-app.iam.gserviceaccount.com이다. 등록/조회 두 함수가 공유한다. 조합은 프로젝트 Firestore 읽기/쓰기용 datastore.user + 사진 버킷 한정 objectCreator/objectViewer다. Firestore 역할은 collection 단위 제한이 아니므로 함수의 본인 권한 검증은 계속 필수다. Storage 생성 권한은 덮어쓰기·삭제 권한을 주지 않는다.

다음은 **생성·권한 변경 명령이며 이번에 실행하지 않았다.** DEPLOYER_EMAIL은 실제 배포 작업자의 이메일로 대체한다.

```powershell
$photoSa = 'work-photos@senior-transport-app.iam.gserviceaccount.com'
$photoBucket = 'senior-transport-app.firebasestorage.app' # 생성 후 확인한 실제 이름

gcloud iam service-accounts create work-photos --display-name="송영도우미 사진 런타임" --project senior-transport-app
gcloud projects add-iam-policy-binding senior-transport-app --member="serviceAccount:$photoSa" --role=roles/datastore.user --condition=None
gcloud storage buckets add-iam-policy-binding "gs://$photoBucket" --member="serviceAccount:$photoSa" --role=roles/storage.objectCreator --project senior-transport-app
gcloud storage buckets add-iam-policy-binding "gs://$photoBucket" --member="serviceAccount:$photoSa" --role=roles/storage.objectViewer --project senior-transport-app
gcloud iam service-accounts add-iam-policy-binding $photoSa --member="user:DEPLOYER_EMAIL" --role=roles/iam.serviceAccountUser --project senior-transport-app
```

roles/editor, storage.admin/objectAdmin, Firebase Auth 관리자, Gemini Secret 접근 권한은 사진 런타임에 주지 않는다. 새 서비스 계정의 JSON 키도 생성하지 않는다. 삭제 도구는 별도 운영자 권한으로만 실행한다. 기존 런타임/빌드 계정의 권한은 이 작업으로 변경하지 않는다. 같은 프로젝트의 기존 Cloud Functions/Run 서비스 에이전트를 유지하고, 오류가 나도 Token Creator/Editor를 일괄 추가하지 않는다.

읽기 확인 명령:

```powershell
gcloud iam service-accounts describe $photoSa --project senior-transport-app
gcloud iam service-accounts get-iam-policy $photoSa --project senior-transport-app
gcloud projects get-iam-policy senior-transport-app --flatten="bindings[].members" --filter="bindings.members:work-photos@senior-transport-app.iam.gserviceaccount.com" --format="table(bindings.role,bindings.members)"
gcloud storage buckets get-iam-policy "gs://$photoBucket" --project senior-transport-app
```

### 4. WORK_PHOTO_BUCKET과 등록 제어

IDE에서 연 .env.local은 Emulator용 override다. 현재 빈 값이지만 사진 Emulator는 코드에서 demo 버킷을 선택하므로 운영 버킷 이름을 이 파일에 채워 배포 설정으로 삼으면 안 된다. 기존 모델/Secret 설정은 보존한다.

functions/.env.senior-transport-app에 다음 **한 항목만** 기존 내용을 보존해 추가한다. 버킷은 생성 후 확인한 bare name이며 gs:// 접두사는 쓰지 않는다. 전체 파일을 화면/로그에 출력하지 않는다.

```dotenv
WORK_PHOTO_BUCKET=senior-transport-app.firebasestorage.app
```

이 값은 API 키가 아니며 새 Secret은 필요 없다. 파라미터 기본값은 빈 문자열이므로 미설정 시 사진 연결을 거절한다. Flutter 클라이언트에는 이 값을 dart-define으로 전달하지 않는다. 배포 후에는 사진 두 함수의 런타임 환경변수 이름/이 값만 확인하고 기존 Gemini 환경변수·Secret 값을 출력하지 않는다.

운영자가 Console에서 _workPhotoControl/config를 다음 형태로 등록한다. **이번에는 문서를 생성하지 않았다.**

```json
{
  "enabled": false,
  "allowedCatalogVersions": ["deploy-test-v2"],
  "requireAppCheck": false
}
```

enabled/requireAppCheck는 boolean, allowedCatalogVersions는 문자열 배열이다. 현재 실제 당일 확정 일정이 deploy-test-v2이므로 최소 허용 목록은 위와 같다. ai-test-25x80-v1도 가상 catalog이지만 미리보기 화면은 확정 일정이 아니어서 사진을 등록할 수 없다. 향후 그 catalog로 별도 승인된 확정 일정이 있을 때만 배열에 추가한다. settings/schedules 포인터를 바꿀 필요가 없다.

requireAppCheck=false는 토큰 없음만으로 거절하지 않는 설정이다. 토큰 발급이 검증돼 이미 true를 사용하기로 했다면 그 정책을 유지한다. enabled=false는 신규 등록 중지이며 기존 본인/관리자 조회는 유지된다. 배포가 enabled 값을 자동 초기화하지 않는다. _aiControl/config와는 별개이며 변경하지 않는다.

### 5. 배포 순서

버킷/IAM/환경변수/제어 문서를 준비한 다음에만 아래 단계를 실행한다. 모두 **이번에 실행하지 않은 배포 명령**이다.

```powershell
node tools/verify-functions-build.cjs
firebase.cmd deploy --only storage --project senior-transport-app
firebase.cmd deploy --only "functions:registerWorkPhoto,functions:getWorkPhotos" --project senior-transport-app
firebase.cmd functions:list --project senior-transport-app
```

사진 함수 두 개가 ACTIVE, asia-northeast3, 전용 계정 사용, Secret 연결 0인지 확인한다. 기존 세 함수와 Firestore Rules는 선택 배포하지 않는다. 원격 제어 문서는 enabled=false로 유지한다.

먼저 Hosting 변경 없이 로컬 Flutter로 실제 서버 연결을 확인할 수 있다. 사진 API를 누르면 실제 호출이 되므로 아래는 배포 후 별도 테스트 단계다.

```powershell
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=false --dart-define=ENABLE_STORAGE_WORK_PHOTOS=true --dart-define=ENABLE_PRODUCTION_AI=true
```

검토 후 Hosting에 반영할 때만:

```powershell
powershell.exe -ExecutionPolicy Bypass -File tools/build-hosting.ps1 -EnableProductionAi -EnableStorageWorkPhotos
node tools/verify-hosting-build.cjs
firebase.cmd deploy --only hosting --project senior-transport-app
```

기존 AI 옵션은 유지하지만 AI를 호출하지 않는다. 사진 권한 테스트를 위해 전체 Functions/Rules를 다시 배포하지 않는다.

### 6. 배포 후 실제 가상 사진 테스트

1. 별도 승인 후 enabled=true로 변경한다. 아직 enable하지 않은 상태에서 모든 등록이 동작한다고 판단하지 않는다.
2. Auth 사용자와 users/{uid}의 active=true(boolean), role=staff, 실제 staffId 연결을 Console에서 확인한다. 해당 ID는 허용 catalog의 활성 직원이며 선택한 **한국 시간 당일 확정 일정의 담당자**여야 한다.
3. 점검 당시 오늘 오전/오후에 deploy-test-v2 확정 일정이 이미 있다. 그 일정을 이용하고 덮어쓰지 않는다. 테스트 날짜가 바뀌면 당시 당일 확정 일정 존재 여부를 다시 확인한다. 사진 테스트를 위해 일정 포인터나 결근 상태를 임의 변경하지 않는다.
4. 개인정보 없는 소품/빈 종이 사진을 카메라 또는 사진 선택으로 등록한다. 시작 성공 후 종료를 등록하고 서버 등록 시각·새로고침 후 유지·관리자 조회를 확인한다. 촬영 시각/도착/실제 근무 인증으로 해석하지 않는다.
5. 실제 파일은 workPhotos/v1/..., 기록은 workPhotoRecords/{staffId}/records/...에 생성돼야 한다. 기존 attendance Blob 기록/확정 일정/version/사용자/_aiControl은 변하지 않아야 한다. 파일에는 공개 다운로드 token/URL을 만들지 않는다.
6. 다른 직원으로 조회가 거절되는지, 동일 슬롯 재등록이 덮어쓰지 않는지 확인한다. 권한 테스트를 위해 users.role/staffId를 수정하지 않는다. 실제 IAM을 약화해 직접 URL을 시험하지 않는다.
7. 실패하면 재전송 전 기록을 새로고침한다. 같은 사진/요청 ID는 복구 가능하며 처리 중이면 120초 lease를 확인한다. 브라우저를 닫으면 클라이언트 임시 ID는 사라지지만 서버 최초 기록 보호는 유지된다. 실패를 이유로 Storage 객체/operations/slots를 임의 삭제하지 않는다.
8. 테스트 종료 후 enabled=false로 되돌린다. 사진의 서버 조회는 30일 만료 정책을 따르며 물리적 정리는 수동이다. 자동 삭제는 활성화하지 않는다.

로그 조회:

```powershell
firebase.cmd functions:log --only registerWorkPhoto --project senior-transport-app
firebase.cmd functions:log --only getWorkPhotos --project senior-transport-app
```

현재 사진 함수의 실패 로그는 component/event/code 중심이다. AI의 stage/diagnosticId와 같은 필드가 항상 있다고 가정하지 않는다. 키·사진 base64·전체 요청·실제 개인정보를 로그로 수집하지 않는다.

## 비용과 확인 범위

Cloud Billing은 활성 상태지만 Storage 사용이 무료라는 뜻은 아니다. Storage 보관 용량·생성/목록/읽기·전송·soft delete/noncurrent 세대, 사진 Callable 실행/메모리/CPU/네트워크, Firestore 기록/operations/slots 읽기·쓰기, Build/Artifact, Hosting 전송이 비용 지점이다. 예약 삭제 함수를 배포하지 않으므로 새 Cloud Scheduler 비용은 현재 없다. 새 사진 기능은 Gemini를 호출하지 않는다.

직원 20명 × 오전/오후 × 시작/종료 = 하루 80장. 180KiB 상한이면 하루 약14.06MiB, 30일 약421.88MiB(0.412GiB). 각 사진 1회 조회 시 비슷한 이미지 양을 전송하며 base64는 약4/3 부피다. 서버 경유 호출/반복 조회/실패 파일/보존 데이터 비용을 합산해야 한다. 30일 보존과 수동 정리는 총비용의 절대 상한이 아니다. 서울 리전의 실제 단가와 무료 할당 조건을 확인하고 예산 알림을 설정한다.

기존 Functions 인프라 버킷도 이미 비용 대상이며 위 live 수치만으로 모든 세대/Artifact Registry 비용을 추정하지 않는다. 사진 테스트 이후 비용은 Billing/Storage 사용량에서 확인한다.

현재 단계에서 새로 필요한 리소스는 사진용 기본 버킷과 전용 서비스 계정/권한 및 제어 문서다. 실제 버킷/IAM/사진 end-to-end는 아직 수행되지 않았다. 로컬 manifest만 재검증했으며 앱 코드 변경이 없어 Flutter/Emulator 전체 테스트는 이번 읽기 전용 점검에서 재실행하지 않았다. 직전 구현 검증은 Flutter246/Emulator175 통과였다.

근거 스냅샷: .local-tools/work-photo-live-review-summary.json. 인증 자료/Secret/사진 내용은 포함하지 않는다. 앱 소스·Firebase 설정·운영 데이터는 변경하지 않았다.

공식 근거:
- [Storage Blaze 및 기본 버킷 요건](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024)
- [프로젝트 환경변수와 Emulator override](https://firebase.google.com/docs/functions/config-env)
- [서비스 계정 생성·attach 권한](https://cloud.google.com/iam/docs/service-accounts-create)
- [Storage 버킷 IAM](https://cloud.google.com/storage/docs/access-control/using-iam-permissions)
- [Firebase deploy target](https://firebase.google.com/docs/cli/targets)
- [Storage 요금](https://cloud.google.com/storage/pricing)
