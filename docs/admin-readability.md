# 관리자 현황 가독성과 버튼 정리

## 화면 변경

- **PC(900px 이상):** 직원 이름, 담당 코스·차량, 이용자 수/차량 정원, 배정 상태를 열이 맞춰진 표로 표시한다. 이름 자연 정렬과 직원·이용자 이름 검색을 유지하며, 표의 셀을 선택하면 해당 직원의 기존 편집 화면으로 이동한다. 검색한 이용자는 현재 담당 코스의 방문 항목으로 연결된다. 20명 규모의 전체 표는 기존 현황 스크롤 안에서 제공한다.
- **모바일:** 표를 축소하지 않고 직원별 카드 목록으로 전환한다. 직원 이름과 코스·차량·인원/정원·배정 상태를 표시하고 기존 상세 화면으로 연결한다.
- **요약:** 이용자·담당 직원·해결할 문제 수를 간격 있는 세 카드로 묶었다. PC에서는 요약 영역을 최대 760px로 제한해 숫자가 화면 양 끝으로 흩어지지 않게 하고, 모바일에서는 같은 세 카드를 너비에 맞춰 표시한다.
- **직원 상세:** 사진 기록 조회와 결근 등록·취소를 기본적으로 접힌 **직원 정보 · 결근/사진** 안에 모았다. 펼치면 기존 조회·결근 기능을 그대로 사용한다. 방문 일정 위에 두 개의 큰 작업 버튼을 항상 배치하지 않는다.
- **중복 버튼:** 상세 화면의 전체 현황·이용자 찾기 버튼을 제거했다. 상단 **전체 현황**으로 돌아가 통합 이름 검색을 사용한다. 필터·방문 편집·개별 이용자 및 코스 재배정·사진 조회·결근 등록·시간 계산 기능은 유지한다. 기존 전체 현황 대화상자는 특정 코스로 연결할 수 없는 문제의 확인 경로로 남긴다.

## 일정 확정 표시

| 상태 | 하단 표시 |
|---|---|
| 확정 완료, 편집 없음, 오류 없음 | **일정 확정 완료 · 변경사항 없음** 안내. 불필요한 확정 버튼은 숨김 |
| 편집했지만 공유 일정과 표시 내용이 같음 | 작은 **일정 확인** 텍스트 버튼. 기존 변경 검토·확정 절차는 열 수 있음 |
| 새 일정 또는 실제 변경 있음 | 기존 **변경 내용 확인 후 확정 → 최종 일정 확정** |
| 결근 코스·방문 시간 확인 미완료·검증 오류 | 기존 안내와 확정 차단 유지 |
| 저장 실패·동시 수정 충돌 | 정상 완료 안내로 덮지 않고 오류·다시 불러오기 안내 유지 |

표시할 변경사항 비교에는 기존 `ScheduleChanges.compare`를 사용한다. 표시 내용이 같아도 내부 시간 입력 방식 등 저장할 정보가 있을 수 있으므로, 편집 상태 자체를 지우거나 변경 저장을 막지 않는다. 버튼을 약하게 표시할 뿐 요청 조건과 최종 확정 로직은 기존 그대로다. AI 일정 제안은 하단 보조 작업으로 계속 사용할 수 있다.

## 수정 파일

- `lib/widgets/admin_transport_dashboard.dart`: PC 표·모바일 카드·요약 카드와 검색 결과 표시.
- `lib/screens/admin_schedule_view.dart`: 중복 버튼 제거, 직원 정보 영역에 사진·결근 작업 정리.
- `lib/screens/schedule_screen.dart`: 확정 상태별 강조 수준 조정. 기존 검토·서버 요청 로직 유지.
- `test/admin_dashboard_test.dart`: 표/카드·마지막 직원 스크롤·접힌 사진 조회·확정 후 편집과 재확정·결근/저장 실패 안내 검증.
- `test/admin_overview_test.dart`, `test/operations_scale_test.dart`: 삭제된 중복 버튼 대신 상단 현황과 통합 검색을 통한 기존 회귀 시나리오 유지.
- `test/staff_absence_test.dart`, `test/attendance_test.dart`, `test/support/fixtures.dart`: 직원 정보 펼치기를 통한 결근·사진 조회 경로 검증.
- `test/admin_usability_test.dart`: 편집을 되돌린 상태의 작은 일정 확인 버튼과 기존 검토 절차 확인.

Firebase 데이터 모델, Authentication·역할, Firestore Rules, Cloud Functions, 일정 검증·동시 수정 방지·사진 저장 코드는 수정하지 않았다. 기존 미커밋 작업도 보존했다.

## 로컬 검증

- `flutter analyze`: 문제 없음.
- `flutter test`: 212개 통과(기존 209개 + 상태/직원 정보 관련 3개). 기존 현황 테스트를 PC 표·모바일 카드와 새 탐색 경로로 보완했다.
- Auth/Firestore/Functions Emulator 전체 회귀: 110개 통과. 기존 실행 환경을 보존하고 별도 포트 9198/8190/5102의 demo namespace에서 실행했다.
- `flutter build web --debug --dart-define=USE_FIREBASE_EMULATORS=true --no-pub`: 성공. 실제 Firebase 배포는 수행하지 않았다.
- 현황 전용 테스트 11개: 20명·80명 가상 catalog, PC 표의 20개 직원 행과 열 정렬·마지막 행 이동, 검색 후 실제 담당자/방문 항목 이동, 문제 우선순위, 모바일 카드·상세 왕복, 날짜 정책, 변경 없는 확정 표시, 편집 후 시간 확인·재확정, 결근/저장 실패 안내, 사진 조회를 검증했다.
- PC 1440×1000, 모바일 320×844·390×844 위젯 화면을 캡처해 확인했다. 기존 320×568 상세 편집·재배정·결근 등록 테스트도 통과했다.

화면 이미지: `.local-tools/dashboard/pc-overview.png`, `mobile-320.png`, `mobile-390.png`, `readability-detail-pc.png`, `readability-confirmed-pc.png`.

로그: `.local-tools/admin-readability-ui.log`, `.local-tools/admin-readability-flutter.log`, `.local-tools/admin-readability-emulator.log`, `.local-tools/admin-readability-web-build.log`.

위 화면은 Flutter 위젯 캡처이며 실제 모바일 브라우저·실기기 조작 시험이나 센터 직원의 사용성 조사를 수행했다는 의미는 아니다. 실제 Firebase 배포·운영 데이터 변경은 수행하지 않았다. 기존 Emulator·가상 계정에서 `flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=true`로 확인한다.
