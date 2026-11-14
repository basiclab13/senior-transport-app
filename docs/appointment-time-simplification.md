# 선택적 오전 약속 시간·오후 방문 순서

2026-11-14 로컬 구현. 기존 B-1/B-2 정책을 대체한다. 이 문서의 명령은 향후 운영자 실행 안내이며 실제 Firebase 변경·배포·외부 Gemini 호출은 수행하지 않았다.

## 최종 동작

- 오전 타임라인에는 `estimatedVisitSources[id] == manual`이고 값이 있는 경우만 `약속 시간 HH:mm`을 표시한다. 입력은 선택 사항이다. 동일/역순 시각이나 기존 운행 구간과 맞지 않는 시각은 확정을 막지 않는다.
- 오후에는 관리자·직원·AI 검토·확정 상세 모두 방문 시각을 표시/입력하지 않는다. 방문 순서·배정·사진 기능은 유지한다.
- 기존 fixedInterval 및 출처 없는 값은 숨긴 채 보존한다. 오전 입력창에서만 이전 기록과 약속 시간이 아님을 구분한다. 입력창은 이 값을 약속 시간으로 미리 채우지 않는다. 빈 상태로 저장/취소하면 이전 값은 유지된다. 실제 HH:mm을 직접 입력해 저장한 경우에만 해당 이용자의 값과 출처 manual을 설정한다. 기존 manual 값을 비우고 저장하는 것은 사용자가 명시적으로 약속 시간을 지우는 동작이다.
- B-1 첫 시각/간격/계산/미리보기/일괄 적용과 B-2 pending/keep/apply 상태·승인·확정 차단을 제거했다. 직원/차량 변경, 결석·제외·복귀, 코스 인계, AI 승인 후 추가 시간 승인 단계는 없다.
- AI가 오전 이용자의 코스/순서를 변경하면 `약속 시간 조정이 필요할 수 있으니 확인해 주세요.`라는 비차단 안내만 표시한다. 지연·도착 시간을 계산하지 않는다. 오후에는 이 안내도 표시하지 않는다.
- 약속 시간 미입력 주의 목록/문제 수 집계를 제거했다. 정원·직원/차량/이용자 중복·결근·미배정 등 실제 업무 오류는 그대로 표시하고 차단한다.
- 운행 시작/종료 UI와 직원의 운행 참고 구간, 재계산 안내를 제거했다. controller의 기존 setOperatingWindow는 과거 데이터/테스트 호환용으로 남지만 화면에서 호출하지 않는다.

## 저장·서버 경계

Firestore schemaVersion 1과 기존 필드 `estimatedVisitMinutes`, `estimatedVisitSources`, `startMinute`, `endMinute`를 유지한다. codec/저장소의 직렬화 계약, confirmSchedule의 전체 확정본 및 본인별 projection 저장을 바꾸지 않는다. 읽기나 배포만으로 기존 문서를 수정하는 migration은 없다.

- 저장 시각은 오전/오후 모두 0~1439 정수여야 한다. 맵/이용자 참조, manual/fixedInterval 출처 형식, 출처에 대응하는 값 존재 여부를 계속 검사한다.
- startMinute/endMinute는 각각 null 또는 유효한 분 값인지 확인한다. 구간의 전후 관계·짝 존재 여부·방문 시각과의 관계는 업무 제약으로 사용하지 않는다. 과거 값은 보존하며 새로운 화면에서 수정하지 않는다.
- 저장된 값 자체가 잘못된 형식/범위인 경우는 여전히 차단한다. 숨겨진 과거 값이 손상됐다면 자동 삭제/정정하지 않고 별도 점검한다.
- 시간 순서 검사 제거는 직원/차량의 시간대 중복 배정 허용이 아니다. 동일 날짜·오전/오후에 직원당 코스1개·차량 중복 금지·정원·결근 검증은 유지한다.
- confirmSchedule의 관리자/활성 검사·expectedVersion·결근 버전·requestId/hash·전원자 트랜잭션은 그대로다.
- suggestSchedule은 서버에서 이용자별 원래 시간/출처를 복원하고 새 정책으로 다시 검증한다. AI 응답에는 staffId/passengerIds/baseRouteId만 허용한다. 시간/출처/차량 변경 응답은 거절한다. Gemini 입력에는 약속 시간/출처/운행 구간을 보내지 않는다. 관리자 승인·오래된 결과 차단·quota/중복 요청·비식별화도 유지한다.
- Flutter의 AI 적용과 수동 코스 이동도 이용자별 시간/출처를 그대로 이동한다. 결근 코스 전체 인계에서는 담당자만 바꾸며 값은 유지한다. 기존 결석/제외의 명시적 편집 및 그 초안에서의 복귀 보존 동작도 유지한다.
- Auth, Firestore/Storage Rules, 사진 함수/기록, 기본 catalog, AI·사진 제어 설정은 수정하지 않는다.

## 주요 파일

수정: `lib/services/schedule_controller.dart`, `lib/models/transport.dart`, `ai_schedule_suggestion.dart`, `schedule_changes.dart`; 관리자/직원/schedule 화면; route_timeline·estimated_time_dialog·AI/코스/확정 비교·전체 현황 위젯; 시간 표시/오류 문구 도구; `functions/validation.js`, `suggestion-service.js`.

삭제: `lib/services/visit_time_calculator.dart`, `lib/models/visit_time_review.dart`, `lib/widgets/bulk_visit_time_dialog.dart`, `visit_time_adjustment_dialog.dart`. 해당 기능의 전용 테스트4개를 삭제하고 정책·기존 기록 보존·화면 회귀로 교체했다. 다른 기능 테스트의 B-2 승인 도우미 호출과 예전 시간 차단 기대값도 수정했다.

신규: `test/appointment_time_policy_test.dart`(8개), `functions/test/appointment-time-policy.test.cjs`(12개). 기존 시간 표시/AI·운영 규모·서버·사진·계정 회귀도 실행한다.

## 배포 전후 호환성

| 서버 | Web | 동작/제약 |
|---|---|---|
| 구버전 | 구버전 | 기존 B-1/B-2와 순서·운행 구간 제약 유지 |
| 구버전 | 새 버전 | 요청 필드 형식은 같지만, 새 화면에서 허용한 역순/동일/구간 밖 시간이 서버에서 거절될 수 있음. **이 순서로 배포하지 않음** |
| 새 버전 | 구버전 | 기존 요청 필드/출처·정상 시간·receipt 계약을 계속 수용. 구버전 Web 자체의 B-2/시간 충돌 차단·계산 UI는 남음. 옛 클라이언트가 명시적 계산 적용으로 fixedInterval 값을 저장하는 것도 호환상 허용됨 |
| 새 버전 | 새 버전 | 새 시간 정책으로 동작. 이전 시간/출처는 보존됨 |

서버를 바꿔도 구버전 Web의 로컬 승인 절차가 사라지는 것은 아니다. 이미 열린 관리자 탭/설치된 PWA 캐시는 새로고침 및 업데이트가 필요하다. 실제 배포된 구버전 브라우저 연결 검증은 이번 로컬 작업에 포함하지 않았다. 위 제약은 기존 코드와 요청 계약을 분석한 결과다.

## 안전한 적용 순서 — 이번에는 실행하지 않음

1. 기존 코드/배포 revision과 Hosting release를 복구 기준으로 보관한다. 관리자에게 편집을 정리하고 작업 중인 탭을 닫도록 안내한다. catalog 포인터나 제어 설정을 바꿀 필요는 없다.
2. 로컬 검사 및 Functions manifest를 확인한다.

```powershell
flutter analyze
flutter test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/test-emulators.ps1
node tools/verify-functions-build.cjs
```

3. 별도 승인 후 공유 검증 정책이 들어 있는 **confirmSchedule과 suggestSchedule을 먼저 함께** 업데이트한다. setStaffAbsence/registerWorkPhoto/getWorkPhotos/Rules는 이 변경 때문에 배포할 필요가 없다. suggestSchedule이 사용하는 기존 Secret 접근 권한은 유지한다. AI mode/허용 목록을 자동으로 켜지 않는다.

```powershell
firebase.cmd deploy --only "functions:confirmSchedule,functions:suggestSchedule" --project senior-transport-app
```

4. 두 함수의 배포 성공·revision을 확인한 뒤 Web을 빌드한다. 기존 운영 기능 플래그를 유지하기 위한 예시는 다음과 같다. 실제 기능 활성/권한은 기존 서버 제어 설정을 따른다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build-hosting.ps1 -EnableProductionAi -EnableStorageWorkPhotos
node tools/verify-hosting-build.cjs
firebase.cmd deploy --only hosting --project senior-transport-app
```

5. 관리자/직원 브라우저를 새로고침한다. 오전 빈값·같은값·역순 시각 확정, 오후 기존값 유지와 순서 변경, 관리자 승인 AI 적용(실호출은 별도 승인), 결근·예비 직원 인계, 본인 직원 조회 및 사진 등록/관리자 조회를 점검한다. 기존 일정은 사용자가 명시적으로 확정하지 않는 한 그대로다.

## 복구 주의

- Hosting만 이전 release로 되돌리는 것은 스키마상 가능하지만 사용자에게 구 B-1/B-2가 다시 보이고 로컬 차단이 남는다.
- **새 정책으로 역순/동일 시각 일정이 확정된 뒤 서버만 구버전으로 되돌리면**, 기존 문서를 읽거나 사진 조회하는 계약은 유지되더라도 그 일정을 재확정/수정할 때 구 시간 제약으로 거절될 수 있다. 서버의 무조건적인 rollback은 안전한 정책 복구가 아니다.
- 우선 편집을 중지하고 원인을 확인한다. UI 문제만 있으면 새 서버 정책은 유지한 상태로 UI 복구를 검토한다. 서버 복구가 필요하면 새 정책으로 생성된 일정에 대한 재확정 호환성을 먼저 Emulator에서 검증한다. 시간값/출처/오후 기록을 삭제·재계산해서 맞추지 않는다.
- 데이터 마이그레이션·Rules/Auth 변경·Secret 신규 등록·AI/사진 제어 설정 변경은 이번 배포 절차에 포함하지 않는다.

## 로컬 검증 결과

최종 결과와 로그는 아래 완료 기록을 따른다. 초기 실패 로그는 삭제하지 않고 최종 통과 로그와 구분한다. 모바일/PC 검사는 widget render와 로컬 캡처 기준이며 실기기 카메라·운영 Firebase·실제 Gemini 호출을 수행한 결과가 아니다.

- flutter analyze: 문제 없음.
- Flutter 전체: **243개 통과**. B-1/B-2 전용 테스트를 제거하고 새 정책 검사로 교체했으므로 이전282개와 단순 개수 비교 대상은 아니다. 8개 신규 정책 검사와 기존 Auth·일정·AI·사진·날짜 선택·동시 수정 회귀가 포함된다.
- Auth/Firestore/Functions/Storage Emulator 전체: **196개 통과**, 실패/취소/생략0. 새 정책12개, 기존10/24·20/80·25/80·40/79 가상 fixture, 실제 로컬 Callable HTTP·Rules·Storage 권한 검사 포함. Gemini는 고정 모의 응답만 사용했다.
- 320/390/768/1280px: 약속 입력창·오후 시간 숨김·타임라인·관리자/직원 화면의 render/overflow 검사 통과. 관리자 캡처 회귀19개도 통과했고 320px 상세·PC 현황/상세 이미지를 직접 확인했다.
- Functions manifest: Node22, asia-northeast3, 기존5개 함수, Secret1개(suggestSchedule에만 연결), 원격 요청0.
- Web release: 실제 Firebase 연결 및 기존 AI/Storage 사진 플래그 활성 빌드 성공. Hosting 파일 검사 통과. fingerprint `82589cea775050885a333128b4a8a508f416550a798105acf0e58739c497edb8`. 배포하지 않았다. 기존 Web 플러그인의 Wasm 호환 안내는 JS release 빌드 성공에 영향이 없었다.
- git diff --check 통과(CRLF 변환 안내만 있음). Rules/Auth/codec/confirm 트랜잭션/결근 서비스의 변경 없음 확인.

로그: `.local-tools/time-policy-analyze-verified.log`, `time-policy-flutter-verified.log`, `time-policy-focused.log`, `time-policy-emulators-verified.log`, `time-policy-visual.log`, `time-policy-manifest.log`, `time-policy-web.log`.

초기 회귀 실패는 이전 B-1/B-2 차단 기대값 및 모바일 테스트의 목록→상세 진입 누락이었다. 새 정책의 허용/거부 검사를 분리하고 모바일 진입을 보정한 후 전체를 재실행했다. 시간과 무관한 검증을 생략하거나 완화하여 통과시키지 않았다.
