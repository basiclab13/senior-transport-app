# 업무 시작·종료 사진의 실제 Firebase 연동 계획

후속 로컬 구현은 [구현·설정·검증 안내](work-photo-local-implementation.md)를 참고한다. 아래 내용은 구현 전 설계 기록이다.

2026-11-14. 이번에는 분석·설계와 기존 Emulator 회귀 검사만 진행한다. 제품 코드/Rules/설정 변경, 실제 Firebase 조회·Storage 생성·결제 변경·배포·운영 데이터 변경은 하지 않았다. 아래 함수·필드·명령은 **제안이며 아직 구현되지 않았다.**

## 현재 구현에서 확인한 사실

| 영역 | 현재 동작 |
| --- | --- |
| 직원 UI | staff_schedule_view.dart가 AttendanceScreen을 첫 화면에 포함. 시작 후 종료 버튼 강조, 확인 후 등록. 관리자 직원 상세에서 조회 |
| 선택/축소 | demo_photo_picker_web.dart: file input, JPEG/PNG 선택 힌트, capture=environment; 원본 10MiB 제한; canvas JPEG 0.7, 긴 변 800/600/400px 시도 |
| 저장 | FirebaseAttendanceRepository가 Firestore 트랜잭션으로 사진 Blob과 서버 시각을 같은 문서에 저장. 최대 180KiB(184320바이트) |
| 경로 | attendance/{staffId}/records/{date}_{period}_{routeId}_{start 또는 end} |
| 필드 | staffId, uid, date, period, routeId, kind: 문자열; registeredAt: timestamp; photo: bytes; contentType: image/jpeg |
| 중복 | 결정적인 문서 ID. 첫 저장 유지, 응답 유실 시 서버 문서 재조회. 모든 클라이언트 수정/삭제 금지 |
| 서버 규칙 | 로컬 Rules가 활성 직원 본인·확정된 단일 코스·catalog 직원 활성·결근 여부·종료 전 시작 기록 존재·서버 시각·크기를 검사 |
| 운영 차단 | repository.enabled는 USE_FIREBASE_EMULATORS=true와 demo-senior-transport를 모두 요구. Rules의 create도 token.aud가 demo-*일 때만 허용 |
| 미사용 서비스 | firebase_storage 의존성, Storage Rules 파일, firebase.json storage 설정/Storage Emulator, 사진 Callable이 모두 없음 |

firebase_options.dart에 senior-transport-app.firebasestorage.app 문자열은 있지만 실제 버킷 존재/위치/IAM/결제를 확인한 증거는 아니다. 과거 배포 검토 문서의 원격 Rules 결과도 현재 상태로 단정하지 않는다.

현재 Rules는 contentType 문자열/bytes 크기만 검사하므로 **실제 JPEG 내용 검증은 하지 않는다.** 선택 날짜가 과거/미래라도 확정 배정 조건을 만족하면 Rules가 생성할 수 있다. 현재 registeredAt은 등록 시각이며 촬영 시각/위치/실제 근무 인증이 아니다. 이 두 점을 운영 전환 시 명확히 처리해야 한다.

## 권장하는 최소 구조

기존 사진 선택·확인 UI와 AttendanceRepository 인터페이스를 유지하고, 운영 전용 repository만 추가한다. 기존 Emulator Blob 저장소도 유지한다. 180KiB JPEG를 그대로 유지하므로 대용량 업로드 기능은 필요 없다.

1. registerWorkPhoto Callable: 압축 JPEG를 base64로 전송. 서버가 검증 후 Admin SDK로 비공개 Storage에 저장하고 Firestore에 메타데이터를 남김.
2. getWorkPhotos Callable: 관리자 또는 본인에게만 선택 날짜/시간대의 메타데이터를 제공. recordId를 지정한 요청은 해당 기록의 작은 이미지 바이트를 제공. 클라이언트가 전달한 임의 Storage 경로는 받지 않음.
3. cleanupWorkPhotos: 보존 기간/실패 파일을 처리하는 제한된 서버 작업. 처음에는 운영자용 dry-run 도구로 검증하고, 자동 삭제는 별도 승인 후 예약 실행.

Flutter의 기존 cloud_functions와 서버의 firebase-admin/storage를 사용하면 **firebase_storage/image_picker 패키지를 추가하지 않아도 된다.** 180KiB base64는 약 240KiB이며 업로드/응답 크기를 서버에서도 제한한다. 큰 원본/영상/진행률·이어올리기까지 필요해질 때만 직접 Storage SDK 방식을 검토한다.

사진 조회도 Callable을 사용하면 운영 Firestore Rules의 attendance 경로를 열 필요가 없다. Admin SDK는 Rules를 우회하므로 모든 검증을 함수에 구현해야 한다. 현재 watch 인터페이스는 최초 조회·등록 후 갱신·관리자 명시적 새로고침으로 제공하며, **관리자 실시간 push는 이 최소안에 포함하지 않는다.** 실시간이 꼭 필요하면 attendance 메타데이터에 한정한 읽기 Rules 추가를 별도 선택한다. 일정을 위한 기존 실시간 구독은 바꾸지 않는다.

## 서버 권한과 불변 조건

- Auth UID로 users/{uid}를 직접 읽는다. active=true, role=staff, 유효한 staffId를 검증한다. 직원/UID는 요청을 신뢰하지 않고 profile에서 결정한다. 관리자는 조회만 가능하고 대신 사진을 등록하지 못한다.
- 날짜/period/route/kind/requestId 형식을 검사한다. staffSchedules/{staffId}/days/{date}_{period}가 confirmed인 단일 코스이고 요청 routeId와 같아야 한다.
- schedules/{date}_{period} 원본과 직원 projection의 version/catalogVersion/담당 배정이 일치하는지 확인한다. catalog.ready와 해당 직원.active도 검사한다. 사용자 계정 staffId가 잘못됐으면 명확히 거절한다.
- 실제 staffAvailability/{date}/staff/{staffId}를 읽고 해당 오전/오후 결근이면 거절한다. 결근 문서 없음은 버전 0/결근 없음으로 처리하되 조회 실패·잘못된 구조는 거절한다. 원본과 projection 불일치도 실패로 처리한다.
- 종료는 같은 UID·직원·날짜·period·코스의 완료된 시작 기록이 있어야 한다. 결근/인계 후 이전 직원은 추가 등록 불가. 이미 저장한 사진은 역사 기록으로 보존한다.
- 등록 전후 일정/결근 버전을 비교한다. 사진 업로드 도중 일정 변경/계정 비활성화/결근 등록/인계가 발생하면 완료 처리하지 않는다.
- 정책 제안: 신규 등록은 한국 시간의 당일 일정만 허용하고 과거 기록은 조회만 허용한다. 과거 보정이 필요하면 별도 관리자 절차를 추후 설계한다. 이 정책은 현재 코드에는 없으며 구현 전에 확정할 항목이다.
- 조회는 활성 관리자 또는 기록 uid와 staffId가 모두 일치하는 활성 직원만 허용한다. 현재 배정에서 빠졌어도 본인의 과거 기록은 조회 가능. 다른 직원·익명·비활성 계정은 거절한다.
- 가상 catalog/개인정보 없는 사진만 사용하는 제한적 테스트 모드로 먼저 시작한다. AI 미리보기는 확정 일정이 없고 AttendanceProvider도 제공하지 않으므로 사진 등록 대상이 아니다.

## 파일 제한과 접근 제어

기존과 같이 저장 형식 JPEG, 1~184320바이트를 유지한다. 파일명 확장자/MIME/매직 바이트만 믿지 않고 서버 이미지 디코더로 실제 디코딩과 재인코딩을 수행한다. 입력 픽셀 상한(예: 400만), 잘못된/잘린 이미지·다중 프레임·크기 초과를 거절하고 메타데이터를 제거한다. 서버 디코더(예: sharp)는 이 검증에 필요한 새 의존성으로만 도입하고 버전을 고정한다. 현재 구현에는 이 검증이 없다.

Storage 파일 경로 제안: workPhotos/v1/{staffId}/{date}/{period}/{routeId}/{kind}/{operationId}.jpg. 사용자 원본 파일명/이름/주소는 경로에 넣지 않는다. 조회 함수는 검증된 메타데이터의 경로와 generation만 사용한다.

- Storage Rules: 사진 prefix의 모든 클라이언트 read/write/list/update/delete 거절. 서버 서비스 계정만 IAM으로 접근. 기존 다른 prefix의 규칙은 사전 확인 없이 덮어쓰지 않음.
- 공개 다운로드 token, getDownloadURL, 공개 ACL, 장기 signed URL을 사용하지 않음. 인증된 함수로 바이트를 반환하고 브라우저 메모리에서 표시. 따라서 다른 직원이 경로를 알아도 파일에 직접 접근 불가.
- 등록/조회 서비스 계정에는 대상 버킷의 필요한 생성·조회 권한만 부여하고, 삭제 작업은 별도 권한으로 분리. 기존 AI/일정 함수의 서비스 계정/IAM을 바꾸지 않음.
- 사진/URL/base64/UID/원본 예외를 로그에 남기지 않고 단계·안전 오류 코드·소요 시간·진단 ID만 기록. 로그아웃 시 이미지 메모리를 폐기하고 사진을 PWA 오프라인 캐시에 저장하지 않음.
- App Check는 기존 앱 토큰 발급을 검증한 뒤 단계적으로 적용. Auth 검사는 항상 수행. 파일 크기·인당 코스별 시작/종료 1건·처리 중 잠금·함수 인스턴스 제한도 서버에서 강제.

## 정합성: 두 서비스의 트랜잭션을 가장하지 않기

Firestore와 Storage를 한 원자적 트랜잭션으로 저장할 수 없으므로 완료된 기록만 사용자에게 노출한다.

1. 사진을 먼저 서버에서 검증. Firestore 트랜잭션에서 profile/원본 일정/projection/catalog/결근/기존 기록/시작 기록/처리 기록을 **모두 읽은 뒤** 내부 _workPhotoOperations의 pending 예약을 생성. 저장할 날짜·코스·버전·해시·요청 ID·만료·고유 경로를 고정한다.
2. 트랜잭션 밖에서 Storage에 생성 전용 업로드(ifGenerationMatch=0). 기존 객체를 덮어쓰지 않는다. 재실행 시 서버 해시·크기·generation을 비교해 같은 파일인지 검증한다.
3. 다시 Firestore 트랜잭션에서 동일 권한·일정·결근·예약·시작 기록·완료 기록을 먼저 읽고 재검증. 파일의 path/generation/hash/size/type을 기록하고 서버 시각으로 완료 문서와 operation 완료 상태를 함께 저장한다.
4. 같은 요청 ID/같은 사진은 최초 결과를 반환한다. 다른 사진으로 같은 ID를 재사용하면 거절. 다른 요청 ID로 동일 업무 슬롯을 동시에 등록해도 완료 문서 create로 첫 기록만 남긴다. 응답 유실 시 완료 조회 후 같은 요청 ID로만 재확인하고 임의 새 요청으로 중복 등록하지 않는다.
5. 업로드 전 실패는 사진 없음, 업로드 후 실패는 **고아 객체가 일시적으로 남을 수 있으나 완료 기록은 없음**. 만료된 pending을 취소 상태로 고정한 다음 완료 기록이 참조하지 않는 객체만 generation 조건부 삭제한다. 삭제/정리 실패는 재실행 가능하도록 남긴다. pending을 정상 등록으로 보여주지 않는다.

Storage generation은 문자열로 보존해 큰 정수의 정밀도 손실을 피한다. Functions 재시도 가능한 트랜잭션 콜백 안에서는 Storage 업로드/삭제를 수행하지 않는다.

완료 문서는 기존 attendance 경로에 새 schemaVersion=2로 추가할 수 있다. 필드 제안: 기존 staffId/uid/date/period/routeId/kind/registeredAt에 catalogVersion, scheduleVersion, availabilityVersion, photo {bucket,path,generation,sha256,size,contentType}, expiresAt을 추가. 기존 schemaVersion 없는 photo:bytes 문서는 읽기 호환만 유지하고 일괄 변환/삭제하지 않는다. 새 repository는 스키마에 따라 바이트를 불러와 기존 UI에 전달한다. 내부 operation은 기존 Firestore 기본 거부 규칙 아래 서버만 접근한다.

## 스마트폰 Web/PWA

현재 capture=environment는 일부 기기에서 카메라를 우선 열어 사진첩 선택이 어려울 수 있다. 작은 선택 메뉴의 **카메라로 촬영**(capture 있음) / **사진 선택**(capture 없음) 두 경로로 기존 picker를 재사용한다. 새 네이티브 앱/카메라 플러그인/getUserMedia 기반 화면은 필요 없다.

capture는 브라우저별 지원이 다르므로 카메라가 항상 열린다고 보장하지 않는다. HTTPS Hosting에서 Android Chrome/iOS Safari 및 홈 화면 설치 모드를 각각 실기기로 확인한다. 권한 거절, 촬영 취소, 사진첩 취소, 카메라 앱 복귀, 화면 회전, HEIC/큰 사진 디코딩 실패를 확인한다. HEIC 지원을 가정하지 않고 JPEG/PNG 재선택을 안내한다. 구형 브라우저의 cancel 이벤트 미지원 시 busy가 계속 남지 않도록 복귀 처리를 보완한다.

기존 사진 확인 → 등록 버튼은 유지한다. 네트워크 실패/불명확한 응답에서는 먼저 저장 여부를 확인하고, 명시적인 재시도만 제공한다. 촬영 시각과 등록 시각을 혼동하지 않는 문구를 유지한다.

## 보존·삭제 제안

- 시연 사진: 등록 후 30일, 미완료/고아 사진: 24시간 이내 정리. 법정 보존 기간이라고 주장하지 않는 프로젝트 정책 제안이다.
- metadata의 expiresAt으로 만료 즉시 조회 함수가 이미지 반환을 거절한다. 예약 정리 작업은 삭제 중 상태 → generation 조건부 파일 삭제 → 사진 참조 제거/삭제 완료 처리 순으로 재실행 가능하게 구현한다. 삭제된 사진을 정상으로 보여주지 않는다.
- Firestore TTL만으로 객체가 지워지지 않으므로 TTL을 먼저 설정하지 않는다. 파일 정리 확인 후 메타데이터를 정리한다. 유효한 오늘 기록의 중복 방지 정보는 조기 삭제하지 않는다.
- Bucket lifecycle은 workPhotos/v1 prefix에만 제한한 보조 장치로 사용. 적용 지연과 기본 soft delete 7일을 고려한다. 30일 뒤 영구 삭제를 보장한다고 표시하지 않는다. 버킷 전체 대상 삭제 정책·retention lock은 시연에 도입하지 않는다.

## Firebase 설정·비용

운영자가 추후 확인할 항목: 프로젝트 senior-transport-app, Blaze와 결제 계정 상태, 실제 버킷 유무/이름/위치, Cloud Storage API, 사진 전용 IAM/Rules, 예산 알림. 기존 Functions 배포 성공만으로 Storage 준비 완료라고 판단하지 않는다.

버킷이 없을 때만 승인 후 Console에서 생성한다. Functions와 가까운 asia-northeast3 Standard를 우선 검토하되 기존 버킷의 위치를 임의로 바꾸지 않는다. 생성 시 공개 테스트 모드를 사용하지 않는다. 권장 Callable 방식은 브라우저가 Storage로 직접 요청하지 않으므로 Storage CORS를 추가로 열 필요가 없다. 원래 FlutterFire bucket 문자열과 실제 대상 bucket을 명시적으로 일치시킨다.

공식 안내상 현재 Cloud Storage for Firebase는 Blaze 요금제가 필요하다. 저장 용량·객체 작업·네트워크, Callable 실행/통신, Firestore 읽기/쓰기, 삭제 예약 작업의 Scheduler, 배포 Build/Artifact 저장이 비용 지점이다. Gemini 호출/Secret은 사진 기능에 필요 없다.

담당 직원 20명 × 오전/오후 × 시작/종료 = 하루 80장. 장당 상한 180KiB일 때 하루 약 14.06MiB, 30일분 약 421.88MiB(0.412GiB), 월 2400개 객체다. 각 사진을 한 번 조회하면 추가로 같은 수준의 사진 전송량이 발생하고 반복 조회·base64 약 4/3 부피·soft delete·고아 파일·처리 기록도 더해진다. 신규 등록 없는 정적인 저장 용량만으로 총요금을 예측하지 않는다. 버킷 위치별 단가와 무료 할당량을 적용해 계산하며 서울 버킷을 미국 일부 리전의 무료 대상이라고 가정하지 않는다.

## 구현·배포 순서 제안

1. 사진 운영 backend/스키마/재시도·만료·조건부 삭제/권한 테스트를 로컬 구현. Storage Emulator를 별도 loopback 포트에 추가하고 demo 프로젝트 강제. 기존 Blob fixture와 테스트는 유지.
2. 함수 manifest 검사의 새 함수 목록과 Secret 연결 0을 검증. 기존 세 함수 코드/정책/Rules에 변화가 없는지 비교. 카메라/파일 picker와 운영 repository를 비활성 플래그 뒤에 구현.
3. Storage 포함 신규 통합 검증: 실제 JPEG 검증/잘못된 MIME/크기/종료 선행/타 직원/익명/비활성/등록 도중 결근·인계·버전 변경/응답 유실/중복/중단·정리 실패/만료 조회를 검증. 이후 기존 전체 회귀.
4. 별도 승인 후에만 운영자가 Blaze·버킷·IAM·비공개 Storage Rules 설정. 실제 현재 Storage Rules를 먼저 백업/비교. Firestore Rules는 변경하지 않음.
5. 사진 함수만 선택 배포하고 기본 비활성 상태로 가상 catalog/승인 계정 테스트. 기존 일정·결근·AI 함수는 함께 배포하지 않음.
6. 사진 플래그를 켠 Flutter Web을 별도 승인 후 배포. 실제 가상 직원의 기존 확정 일정으로 시작/종료/관리자 조회/타 직원 거절/중복 방지 확인. AI 미리보기 화면은 사진 테스트로 사용하지 않음.
7. 삭제 dry-run 대상 확인 후 정리 작업 활성화. 장애 시 사진 기능 플래그를 끄고 기존 기록은 보존. 기존 일정 서비스를 롤백하지 않음.

구현 후 사용할 선택 배포 명령의 **예시**(지금 실행하거나 현재 코드에서 동작하는 명령이 아님):

```powershell
node tools/verify-functions-build.cjs
firebase.cmd deploy --only storage --project senior-transport-app
firebase.cmd deploy --only "functions:registerWorkPhoto,functions:getWorkPhotos" --project senior-transport-app
# 정리 함수가 구현·검증되고 삭제 정책을 별도 승인한 뒤에만:
firebase.cmd deploy --only functions:cleanupWorkPhotos --project senior-transport-app
# 운영 사진 기능 빌드 옵션이 구현된 후에만 해당 release를 준비하고:
node tools/verify-hosting-build.cjs
firebase.cmd deploy --only hosting --project senior-transport-app
```

현재 firebase.json에는 storage 설정이 없고 새 함수/빌드 플래그도 없으므로 먼저 로컬 구현이 필요하다. 현재 상태에서 Emulator guard나 demo-aud 조건만 제거해 운영에 여는 방식은 권장하지 않는다.

## 기존 회귀 검증의 범위

Auth/Firestore/Functions의 **기존 전체 회귀 164개 통과**, 실패/취소 0. 사진 통합 검사는 본인 확정 배정·서버 시각·시작/종료 순서·타 직원 조회 차단·중복 덮어쓰기/삭제 거절·결근/인계 시 등록 차단을 포함한다. 파일 단위 직렬 실행으로 개별 동시 요청 테스트도 유지했다. 기존 snapshot을 import/삭제하지 않고 별도 demo namespace 및 loopback 포트 9198/8190/5102에서 실행 후 종료했다. 임시 Emulator 설정 파일은 제거했다.

현재 Storage 구현이 없으므로 이 결과는 새 Storage 경로의 권한·원자성·삭제 정책이나 실기기 카메라 지원을 검증한 결과가 아니다. 신규 구현 후 Storage 포함 테스트가 추가로 필요하다. 제품 코드 변경이 없어 Flutter 분석/테스트는 이번에 재실행하지 않았다. 로그: .local-tools/photo-production-review-emulator.log.

## 공식 참고 자료

- [Storage Blaze 및 버킷 요건](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024)
- [Cloud Storage 요금](https://cloud.google.com/storage/pricing)
- [Callable 인증 정보 처리](https://firebase.google.com/docs/functions/callable)
- [Admin SDK는 Firestore Rules를 우회](https://firebase.google.com/docs/firestore/security/rules-conditions)
- [객체 generation 전제 조건](https://cloud.google.com/storage/docs/request-preconditions)
- [Lifecycle과 soft delete](https://cloud.google.com/storage/docs/lifecycle)
- [브라우저 capture 지원 범위](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Attributes/capture)
