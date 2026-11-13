# 운영 규모 가상 환경 검증 결과

> 이 문서는 최초 운영 규모 검증 기록이다. 직원 이름 자연 정렬·검색 가능한 재배정·확정 변경 요약의 후속 구현은 [admin-usability-improvements.md](admin-usability-improvements.md)를 참고한다. 아래 최초 화면과 관찰값은 당시 기록으로 보존한다.

검증일: 2026-11-13. 실제 Firebase 데이터 조회·수정, Rules/Functions 배포, 요금제 변경은 수행하지 않았다. 이번 작업은 테스트 fixture·개발 도구·테스트·문서에만 추가했다. 관리자 화면 재설계나 인증·저장소·권한·confirmSchedule 수정은 하지 않았다.

## 환경과 재사용

| 항목 | 구성 |
|---|---|
| Firebase | demo-senior-transport, Auth 9099 / Firestore 8080 / Functions 5001, 모두 loopback |
| catalog | operations-20x80-v1, 실제 초기 등록용 deploy-test-v2와 분리 |
| 직원·차량·이용자 | 20명 / 20대 / 80명 |
| 코스 | 오전 19개 + 오후 19개 = 38개; s3는 예비/미배정 직원 |
| 계정 | 관리자 1개 + staffId s1~s20에 연결한 직원 20개 = 21개 |
| 확정 일정 | 당일/다음날 × 오전/오후 = 4개 |
| 브라우저 | Chrome 157.0.8103.78 headless, 1440×1000 / 390×844 |
| 시간대 | 브라우저를 America/Los_Angeles로 설정한 상태에서도 한국 시간 기준 자동 선택 검증 |
| 실행 도구 | Node 22.23.5, Java 21, Emulator용 release Web 빌드 |

기존 fictionalCatalog(false)의 직원 s1/s2/s3, 차량 v1/v2/v3, 이용자 p1~p5와 기본 4개 코스의 ID·내용·방문 순서를 그대로 유지했다. 직원 s4~s20과 이용자 p6~p80을 확장했으며 새 차량 정원은 6명이다. 기존 --scale의 40명/79명 fixture와 기존 20명/80명 위젯 테스트도 유지·재사용한다. 새 Emulator fixture는 원래 코스를 보존하므로 기존 위젯 fixture(20개 코스/시간대)와 코스 수가 다르다.

기존 registerCatalog 헬퍼와 서버 confirm 검증을 사용해 초기 fixture/확정본을 준비했다. 이후 브라우저 편집의 확정은 실제 Auth 토큰을 전달하는 confirmSchedule Callable을 사용했다. 계정은 ops-admin@example.invalid 및 ops-s1~ops-s20@example.invalid 형식이다. 일치하는 기존 계정·프로필은 보존하고 충돌 시 중단한다. 기존 가상 계정 생성/seed 도구와 실제 등록 CLI는 변경하지 않았다.

오전 기본 배정은 80명이다. 오후에는 p2 결석, p5 제외로 78명이며 새 코스의 방문 순서를 역순으로 구성했다. 예상 운행은 오전 08:50~09:30, 오후 16:45~18:25인 가상 입력값이다. 직원 s3는 금요일 근무 불가 설정을 유지한다.

## 실제 브라우저 + Emulator 결과

| 시나리오 | 결과·증거 |
|---|---|
| 관리자 로그인·초기 자동 선택 | 통과. 한국 시간의 `오늘 · 11월 13일 (금) · 오전` 선택. 미국 브라우저 시간대와 독립적 |
| 다른 날짜·오후 수동 조회 → 현재 일정 | 통과. 당일/다음날 오전·오후 조회, 오후의 결석/제외 화면 확인 후 현재 일정 복귀 |
| 전체 배정 현황 | 20명·19코스·80명 및 미배정 직원 표시 확인. PC 압축 행과 모바일 줄바꿈 확인 |
| 직원 검색 | 가상 직원 20 검색 및 김다정 검색 후 해당 직원 상세로 이동 |
| 이용자 검색 | 80번째 이용자 검색, 담당 직원 20·코스·위치 확인 후 상세로 이동. 모바일에서도 확인 |
| 방문 시각 편집 | 실제 입력·적용으로 p1 예상 방문 시각 변경 확인 |
| 재배정 | p1을 직원 s1에서 s4로 이동. 대상의 현재 5/6명·이동 후 6명 표시 확인. 기존 시각은 제거되어 새 코스에서 미입력으로 표시 |
| 결석·전체 확정 | p2 결석 처리 후 날짜·요일·오전 표시가 있는 19코스 검토 창에서 확정. Firestore v1→v2, 전체 배정 79명 |
| 직원 로그인·조회 | s4로 로그인해 v2 본인 일정 및 재배정된 p1 확인. 모바일에서 마지막 방문까지 스크롤 확인 |
| 권한 | 직원 토큰으로 타 직원 문서와 관리자 전체 일정 조회 HTTP 403. 직원의 Callable 확정 PERMISSION_DENIED |
| 미배정 이용자 | p80을 누락한 관리자 Callable 요청 INVALID_ARGUMENT. 기존 확정 버전 v2 유지 |
| 원격 서비스 접근 | 관측된 비-Emulator Firebase 데이터 API 요청 0건. 브라우저는 해당 원격 API를 차단한 상태로 실행 |
| 실행 예외 | 이 성공 실행의 JavaScript 미처리 예외 0건 |

미배정 이용자가 남은 문서는 정상 확정본으로 저장하지 않는다. 별도 위젯 테스트에서 불완전한 초안을 구성해 배정 79/80명·미배정 1명 표시, 검색, 확정 차단을 확인했다. 이는 테스트 메모리에만 존재하며 Firestore를 손상시키는 데이터 주입은 하지 않았다. 차량 정원 초과, 중복 배정, 근무 불가, 시각 충돌의 기존 서버 검증도 fixture 테스트 및 기존 Emulator 회귀 테스트로 확인했다.

## 가독성·검색·스크롤·성능 관찰

| 관찰 | 평가 및 개선 후보 |
|---|---|
| PC 현황은 한 화면에 약 10~12행 | 20명에서 전체 현황을 약 두 화면으로 확인 가능. 상세 카드 20개를 나열하는 문제는 없음 |
| 직원 정렬은 문서 ID 순 | s1, s10…s19, s2…가 섞인다. 이름/자연 순서 정렬과 선택 직원 위치 유지 개선 권장 |
| 재배정 대상 18개가 3줄짜리 긴 메뉴 | 인원·정원은 읽을 수 있지만 아래 대상 찾기에 스크롤이 길다. 검색·근무/여유 정원 필터가 있는 선택 창을 우선 검토 |
| 확정 검토 창에 전체 19코스 | 상세 내용은 스크롤 가능하지만 소수 변경에도 전체 검토 부담이 크다. 변경된 직원/이용자 요약과 전체 보기 분리 검토 |
| 작은 직원 화면 | 본인 일정으로 제한되며 스크롤 동작은 정상. 안내문·사진 준비 버튼·반복 헤더가 첫 방문까지의 높이를 차지한다. 안내 접기 등으로 방문 정보 우선순위 개선 가능 |
| Emulator 경고 배너 | Firebase Auth SDK의 하단 배너가 확정 footer 일부를 덮는다. 운영 앱 문제가 아닌 개발 환경 문제. 자동화에서는 배너를 계속 보이게 두고 pointer-events만 끄는 테스트용 조정을 사용했다. 수동 검증에는 하단 여백/개발 설정 개선 필요 |

측정된 자동화 단계 시간은 전체 현황 열기 382ms, 현황 직원 검색 293ms, 이용자 검색 695ms, 직원 목록 검색·이동 681ms, 확정 검토·저장 흐름 4,072ms다. **클릭 후 350ms·입력 전후 대기 및 스크린샷 시간 등이 포함된 단일 로컬 실행값**이므로 실제 UI 계산 시간이나 운영 p95로 해석하면 안 된다. 체감 정지를 관찰하지는 않았지만 성능 한계를 입증한 부하 시험도 아니다.

종료 시 JS heap 관측값은 57.1MiB다. Wasm/GPU/전체 프로세스 메모리, 장시간 누수, 20명 동시 접속, 실제 모바일 기기의 키보드·터치는 측정하지 않았다. 이번 모바일 검증은 Chrome viewport와 위젯 테스트 크기 변경이다. 이 범위에서는 검색·조회·수정에 기능 차단 오류가 없었지만, 위 메뉴/정렬/검토 가독성 개선을 다음 작업 후보로 권장한다. 이번에는 화면 구조를 변경하지 않았다.

## 테스트와 산출물

- flutter analyze: 문제 없음.
- flutter test: 74개 통과. 기존 72개 + 미배정 초안/80명 중 직원 본인 일정·스크롤 2개.
- Auth/Firestore/Functions Emulator: 37개 통과. 기존 33개 + 운영 fixture/보호 조건 검증 4개.
- 실제 브라우저: 관리자 로그인 → 검색 → 편집·재배정·결석 → Callable 확정 → 직원 조회 → 권한 거부 → 모바일 관리자 조회 완료.
- 원본 결과: [.local-tools/operations/report.json](../.local-tools/operations/report.json).
- 화면: [PC 전체 현황](../.local-tools/operations/overview-desktop.png), [재배정 목록](../.local-tools/operations/reassignment-targets.png), [모바일 관리자 검색](../.local-tools/operations/admin-mobile-search.png), [모바일 직원 마지막 방문](../.local-tools/operations/staff-mobile-scrolled.png).
- 재사용용 로컬 export: `.emulator-data/operations-20x80-20261113`. 관리자 편집 후 v2 확정본과 21개 가상 계정이 포함된다. 회귀 테스트와 섞이지 않도록 export 후 운영 검증 Emulator를 종료하고, 별도 깨끗한 Emulator에서 회귀 테스트를 실행했다. 현재 테스트 서버·Chrome은 종료했다.

위 로그·화면·export·Chrome 프로필·임시 비밀번호는 Git 제외 경로에만 있다. 서비스 계정 키나 개발 계정 비밀번호를 소스에 넣지 않았다. 재실행은 아래 절차로 새로 생성한다.

## 재현 절차

첫 터미널에서 새 환경을 시작한다. 기존 40/79 회귀 테스트나 다른 Emulator 인스턴스와 동시에 실행하지 않는다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/start_operations_emulators.ps1
```

두 번째 터미널에서 Node 22를 사용하고 Emulator Web 빌드를 생성한다.

```powershell
$env:GCLOUD_PROJECT = 'demo-senior-transport'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
flutter build web --dart-define=USE_FIREBASE_EMULATORS=true
node tools/operations_browser.cjs
```

도구는 계정·catalog·확정 일정을 준비하고 127.0.0.1:8765에서 빌드를 잠시 제공하며 9223 포트의 별도 headless Chrome을 사용한다. 기본 Chrome 경로가 다르면 OPERATIONS_CHROME에 지정한다. .local-tools의 portable Node를 쓰는 경우 그 폴더를 두 번째 터미널 PATH에도 추가한다. 기본 비밀번호는 실행 시 생성해 `.local-tools/operations/local-emulator-password.txt`에만 보관하고 출력하지 않는다. 기존 계정의 비밀번호는 변경하지 않으므로 기존 로컬 파일 또는 EMULATOR_USER_PASSWORD가 그 계정과 일치해야 한다.

자동 편집 시나리오는 초기 확정 버전 v1을 전제로 하므로 **전체 브라우저 시나리오를 다시 수행할 때는 새 Emulator 세션**을 사용한다. 기존 확정본을 도구가 원복/덮어쓰지는 않는다. 테스트한 v2 상태를 수동으로 이어서 확인하려면 첫 터미널에서 다음처럼 로컬 snapshot을 가져온다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/start_operations_emulators.ps1 -ImportSnapshot
```

수동 앱 실행은 `flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=true`를 사용한다. 계정 비밀번호는 위 로컬 파일이나 직접 지정한 Emulator 비밀번호를 사용한다. Chrome 자동화 없이 데이터를 준비하려면 EMULATOR_USER_PASSWORD를 직접 안전하게 입력한 후 `node tools/prepare_operations_emulator.cjs`를 실행할 수 있다. 비밀번호는 코드나 명령 이력에 직접 쓰지 않는다.

전체 회귀 검증은 운영 확인 Emulator를 종료한 뒤 `tools/test-emulators.ps1`, `flutter analyze`, `flutter test`로 수행한다. 실제 프로젝트용 등록 CLI, firebase deploy, 요금제/유료 서비스 설정은 이 절차에 포함하지 않는다.
