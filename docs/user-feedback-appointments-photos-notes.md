# 사용자 피드백 반영: 기본 약속 시간·사진·특이사항·전체 현황

2026-11-22. 로컬 코드와 가상 데이터 Emulator 검증 작업이다. 실제 Firebase 데이터·계정·Secret·IAM 변경, Gemini 실호출, commit/push 및 배포는 하지 않는다.

## 1. 기본 오전 약속 시간

관리자 직원별 화면에서 어르신 항목을 펼쳐 **기본 시간·특이사항**을 선택한다. 시계 버튼으로 기본 오전 약속 시간을 고르고 저장한다. 기본 정보 저장은 일정 확정과 별도로 즉시 서버에 저장된다.

- 이후 새로 만드는 미확정 오전 일정은 어르신의 기본 시간을 복사해 사용한다. 직접 설정한 기본 시간이므로 기존 `estimatedVisitMinutes`와 `estimatedVisitSources: manual`로 확정할 수 있다.
- **이 날짜 시간 변경**은 해당 날짜의 값만 바꾼다. 이 변경은 기존 전체 일정 확정으로 저장한다. 다른 날짜와 기본 시간에는 영향이 없다. 입력창에서 기본 시간으로 돌아갈 수도 있다.
- 미입력·중복 시각·방문 순서와 맞지 않는 시각은 여전히 확정을 막지 않는다. 잘못된 분 범위·참조·출처 형식은 거절한다.
- 이미 확정한 일정은 약속 시간이 비어 있더라도 기본값 변경으로 채우거나 수정하지 않는다. 그 일정에서 명시적으로 시간 편집 후 재확정해야 바뀐다.
- 관리자가 직접 지정한 날짜별 값 또는 명시적으로 지운 값은 기본 시간 변경으로 덮어쓰지 않는다. 약속 시간을 지우고 그 날짜를 확정하면 그 날짜는 빈 값으로 보존된다.
- 과거 `fixedInterval` 또는 출처 없는 시간은 기본 시간으로 승격하지 않는다. 기존 날짜의 수동 시간도 자동으로 기본 정보에 이관하지 않는다. 읽기·저장 기본값 변경만으로 과거 시각·출처를 삭제하지 않는다.
- 오후에는 시간 입력·표시를 하지 않는다. 기존 오후 시각·출처는 저장 및 AI·코스 이동 후에도 보존한다.

다른 관리자가 기본 정보를 바꾸면 열어 둔 편집 화면은 다시 불러와 확인한다. 이미 열려 있는 다른 관리자의 초안 시간을 서버가 임의로 교체하지는 않는다.

## 2. 오전 시작 / 오후 종료 사진

사진 종류는 등록한 사진 수가 아니라 선택한 오전·오후로 결정한다.

| 선택 일정 | 새로 등록할 수 있는 사진 | 오전 기록 필요 여부 |
| --- | --- | --- |
| 오전 | 업무 시작 | 필요 없음 |
| 오후 | 업무 종료 | 오전 시작이 없어도 등록 가능 |

Flutter의 별도 사진 화면과 직원 첫 화면의 통합 사진 영역을 모두 수정했다. 서버 `registerWorkPhoto`와 Emulator Blob용 Firestore Rules도 동일한 조합만 허용한다. 오후 시작 또는 오전 종료 요청은 거절한다. 기존 기록 개수로 다음 사진 종류를 추측하지 않는다.

본인 확정 일정, 한국 시간 오늘, 활성 직원, 결근·일정 버전, JPEG 크기·픽셀·재인코딩, 중복 요청·슬롯·업로드 후 재검사는 유지한다. Storage 경로·사진 기록 구조·기존 사진·등록 시각은 변경하지 않는다. 이전 정책으로 등록된 사진도 그대로 조회하며 자동 재분류하지 않는다. 오전이 누락되었다고 오후 사진을 오전으로 옮기지 않는다.

## 3. 특이사항 저장과 권한

기존 `Passenger.note`를 화면과 모델에서 재사용한다. 관리자가 기본 정보 창에서 입력·수정하고, 비우고 저장하면 특이사항이 없는 상태로 저장한다. 2,000자 제한과 줄바꿈을 지원한다. 직원 화면에서는 이름·주소 아래에 바로 표시하고 빈 내용이면 영역을 만들지 않는다.

기본 catalog 원본과 등록 도구의 무결성 검사를 깨뜨리지 않도록 수정 정보는 별도 하위 문서로 관리한다.

```text
catalogs/{catalogVersion}/passengerSettings/{passengerId}
  version: 양의 정수 (최초 1)
  defaultMorningMinute: 0~1439 정수 또는 null
  note: 문자열 (삭제 상태는 빈 문자열)
  updatedBy: 서버가 결정한 관리자 식별자
  updatedAt: 서버 시각
```

- 부모 catalog, 기존 `passengers`, settings 포인터, users, 확정 일정, 사진 기록을 자동 수정하는 이관 작업은 없다. 최초 기본 정보 저장 시 새 문서가 생긴다.
- 기본 정보는 해당 catalog 안에서 날짜·코스 변경과 무관하게 유지된다. 다른 catalog로 전환할 때 설정을 자동 복사하지 않는다. catalog 간 직원·어르신 ID 의미를 확인하는 별도 검토가 필요하다.
- `updatePassengerDetails`: 활성 관리자만 변경한다. catalog 준비·가상 데이터·어르신 존재와 `expectedVersion`을 트랜잭션에서 검사한다. 두 관리자가 동시에 저장하면 하나만 성공하고 다른 요청은 `aborted`로 거절한다.
- `getPassengerDetails`: 활성 관리자는 선택한 catalog의 정보를 조회한다. 직원은 서버가 본인의 해당 날짜·시간대 확정 projection을 읽고 그 안의 어르신 ID만 결정한다. 클라이언트가 다른 직원이나 어르신 ID 목록을 지정해 조회할 수 없다. 배정이 사라진 날짜의 조회도 거절한다.
- Firestore 클라이언트의 `passengerSettings` 직접 읽기·쓰기는 기존 최종 거부 규칙으로 차단된다. 관리자도 새 Callable을 통해 접근한다. 다른 직원용 전역 어르신 목록을 공개하지 않는다.
- 확정 시 `confirmSchedule`이 같은 트랜잭션의 읽기 단계에서 기본 정보를 읽어 담당자별 catalog 표현에 반영한다. 기록된 방문 시각은 요청의 날짜별 값을 그대로 저장한다.
- 직원의 최초 조회·날짜 전환·재조회에서도 담당 범위의 최신 특이사항을 합친다. 따라서 과거 확정 문서를 다시 쓰지 않고 최신 안내를 표시한다. 별도의 실시간 기본 정보 구독은 추가하지 않았으므로 이미 열린 직원 화면은 재조회가 필요하다.
- AI 입력 허용 목록과 시간·출처 보존은 그대로다. 새 특이사항·기본 시간 필드를 Gemini에 전송하지 않는다. 기본 정보를 바꾼 관리자의 오래된 추천 적용도 기존 catalog 동일성 검사로 차단한다.

시연에는 실제 사람의 건강정보·연락처 등을 입력하지 않는다. 새 API는 Secret이나 새로운 Firebase 서비스를 요구하지 않지만 Callable 실행과 Firestore 조회·저장 비용은 발생할 수 있다.

## 4. 전체 현황 재사용

- 관리자 첫 현황의 PC 표에 코스별 방문 순서·이름·오전 수동 약속 시간을 추가했다. 모바일 직원 카드에도 같은 순서를 표시한다.
- 기존 전체 배정 현황 창에 오전·오후 전환을 추가하고, 방문 순서를 잘라 숨기지 않고 줄별로 표시한다.
- 결근·대체 직원 필요 상태, 결석자 이름, 미배정 인원 및 상세 창의 미배정 이름을 확인할 수 있다. 직원 선택 후 기존 편집으로 이동하는 흐름을 유지한다.
- 오후 시간과 과거 자동 계산 시간은 현황에서도 표시하지 않는다. 새 페이지·새 일정 저장 경로는 추가하지 않았다.

## 변경 파일

| 영역 | 파일 |
| --- | --- |
| 기본 정보 서버 | `functions/passenger-details.js`, `functions/index.js`, `functions/schedule-service.js` |
| 모델·연결 | `lib/models/transport.dart`, `schedule_catalog.dart`, `lib/services/schedule_repository.dart`, `schedule_controller.dart`, `lib/data/emulator_display_names.dart` |
| 관리자 입력 | `lib/screens/admin_schedule_view.dart`, `lib/widgets/passenger_details_dialog.dart`, `estimated_time_dialog.dart` |
| 직원 표시 | `lib/widgets/route_timeline.dart` |
| 사진 정책 | `functions/work-photo-service.js`, `firestore.rules`, `lib/screens/attendance_screen.dart`, `lib/services/attendance_repository.dart` |
| 전체 현황 | `lib/widgets/admin_transport_dashboard.dart`, `admin_assignment_overview.dart` |
| 검증 | `test/passenger_details_test.dart`, 기존 attendance·staff_ux 테스트, `functions/test/passenger-details.test.cjs`, 기존 attendance·work-photos·demo10·function-entry 테스트, `tools/verify-functions-build.cjs` |

작업 시작 전부터 있던 `.gitignore` 변경과 보안 점검 보고서는 보존했다. 이번 기능 변경과 별개다. 실제 Secret 파일·stash·Git 기록은 건드리지 않았다. Emulator 검증 중에만 공백 키를 사용해 Gemini 실호출을 막고 검증 후 해당 임시 파일을 제거한다.

## 배포 순서 — 실제 실행하지 않음

1. 현재 Hosting release와 함수 revision을 복구 기준으로 기록한다. 관리자 편집을 정리하고 직원에게 앱 새로고침을 안내한다. 기존 catalog·계정·사진·제어 설정을 초기화하지 않는다.
2. 로컬 분석·Flutter·Emulator 회귀 및 Functions manifest를 통과한 코드를 검토한다. Gemini·사진 허용 목록이나 Secret을 새로 설정할 필요는 없다.
3. 기본 정보 조회·저장 함수와 confirmSchedule을 먼저 배포한다. 사진 정책도 서버에서 먼저 강제한다.

```powershell
firebase.cmd deploy --only "functions:getPassengerDetails,functions:updatePassengerDetails,functions:confirmSchedule,functions:registerWorkPhoto" --project senior-transport-app
```

4. 사진의 Emulator Blob 경로에도 같은 정책이 적용되도록 Rules를 반영한다. 새 기본 정보 collection은 기존 거부 규칙을 그대로 따른다. Storage Rules·Auth 설정 변경은 필요 없다.

```powershell
firebase.cmd deploy --only firestore:rules --project senior-transport-app
```

5. 새 함수들이 준비된 다음 기존 운영 플래그를 유지해 Web을 빌드·검사·배포한다. 다음은 기존 운영 AI·Storage 사진을 사용하는 경우의 예시다. 플래그는 서버의 AI 승인·한도를 우회하지 않는다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build-hosting.ps1 -EnableProductionAi -EnableStorageWorkPhotos
node tools/verify-hosting-build.cjs
firebase.cmd deploy --only hosting --project senior-transport-app
```

6. 직원·관리자 모두 브라우저 또는 PWA를 새로고침한다. 기본 시간 저장 → 다른 미확정 날짜 조회 → 날짜별 예외 확정 → 기본 시간 변경 후 기존 확정본 불변을 확인한다. 오전 미등록 상태의 오후 종료 등록, 관리자 사진 조회, 특이사항 수정·삭제, 다른 직원 접근 거부를 확인한다. 실호출 AI 검증은 별도 승인 때만 한다.

### 구버전·복구 주의

- 구 Web은 새 기본 정보를 저장·조회하지 못하지만 기존 일정 필드와 사진 기록을 읽는 계약은 유지된다. 새 Functions가 준비되기 전에 새 Web을 먼저 올리면 기본 정보 조회 실패로 일정 화면도 조회 오류가 날 수 있다.
- 새 서버와 구 Web이 함께 있으면 구 Web이 잘못된 오전 종료·오후 시작 요청을 보낼 때 거절된다. 사진 종류를 임의로 바꾸어 저장하지 않는다. 전환 중 사진 등록이 잠시 제한될 수 있으므로 배포 시간을 알리고 열린 앱을 업데이트한다.
- UI 문제는 Hosting 복구를 우선 검토하되 기본 정보 Callable은 유지한다. 사진 서버를 과거 정책으로 되돌리면 잘못된 종류의 등록이 다시 가능해질 수 있으므로 무조건 rollback하지 않는다.
- 기본 정보 collection을 삭제하거나 빈 값으로 일괄 덮어써서 복구하지 않는다. 기존 확정 시각과 사진 기록을 이관·정리할 필요가 없다. 실제 데이터 복구가 필요하면 범위를 확인하고 별도 승인한다.

## 검증 결과

최종 실행 결과와 로그는 작업 완료 시 아래에 기록한다. UI 검증은 320·390·768·1280px widget render/overflow 검사이며 실제 스마트폰 카메라·PWA 촬영이나 운영 Firebase를 사용한 결과는 아니다.

| 항목 | 최종 결과 |
| --- | --- |
| Flutter analyze | 문제 없음 |
| Flutter 전체 | 265개 통과, 실패 0 |
| Auth·Firestore·Functions·Storage Emulator 전체 | 205개 통과, 실패·취소·생략 0 |
| Functions manifest | Node22, asia-northeast3, 7개 함수 확인. Gemini Secret은 suggestSchedule 1개에만 연결, 원격 요청 0 |
| 모바일·PC | 320·390·768·1280px 현황, 기본 시간 선택창, 긴 특이사항 표시 render/overflow 검사 통과 |
| 변경 파일 형식 | git diff --check 통과 |

기능별 검증:

- 기본 시간: 날짜를 바꿔도 유지, 기본값 수정, 날짜별 예외·빈값 보존, 확정본 불변, 기존 fixedInterval 기록 보존, 오전/오후 분리.
- 특이사항: 입력·수정·빈값 삭제, 서버 재조회, 동시 수정 충돌, 원본 catalog 불변, 담당자별 조회 범위, 코스 인계 후 이전 직원 접근 거부, 직접 Firestore 접근 차단. 새 Callable의 실제 로컬 Auth·HTTP 직렬화도 확인.
- 사진: 오전 누락 후 오후 종료 성공, 오후 시작·오전 종료 거절, 기존 사진 보존, 본인·관리자 권한, JPEG 검증·중복·부분 실패·만료 정리 회귀. Blob Rules와 Storage Callable 모두 검증.
- 기존 기능: AI 모의 응답·비식별화·호출 제한, 결근·코스 인계, 정원·중복 배정·동시 확정, 로그인·직원 조회 회귀 유지.

초기 실패는 이전 사진 정책의 기대값, 추가 사진으로 늘어난 만료 정리 개수, 특이사항 끝 공백 제거를 반영하지 않은 UI 기대값이었다. 새 업무 규칙에 맞게 검사를 수정하고 전체를 재실행했다. 서버 권한·정원·동시 수정 검사를 완화하지 않았다.

로그: `.local-tools/user-feedback-analyze-final.log`, `user-feedback-flutter-verified.log`, `user-feedback-emulators-final.log`. 이전 실패 로그도 별도 이름으로 보존한다. 테스트용 Java21·Node22는 Git 제외된 로컬 도구 폴더에만 준비했으며 실제 서비스·유료 설정을 활성화하지 않았다. 최종 Emulator 실행은 운영 ADC 사용 경로를 차단하고 공백 키로 외부 AI 호출을 막았다.
