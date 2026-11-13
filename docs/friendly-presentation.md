# 송영도우미: 앱명·가상 이름·추천/확정 화면 개선

## 앱 표시 이름

앱 제목·로그인 제목·MaterialApp 제목·Web 문서 제목·PWA 이름/짧은 이름·Apple Web 앱 제목을 **송영도우미**로 통일했다. Android 앱 label, iOS/macOS 표시 이름, macOS 메뉴/창 제목, Windows 창·제품 설명도 같은 이름을 사용한다.

Firebase 프로젝트 ID, Flutter 패키지 이름, Android applicationId, iOS/macOS 번들 ID, macOS PRODUCT_NAME, Windows 내부 실행 파일 식별자는 유지했다. 네이티브 표시 리소스는 수정했지만 이번 환경에서는 Web 빌드만 실행했다.

Emulator 빌드의 로그인·관리자·직원 화면에 **테스트 데이터** 표시를 유지한다. `flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=true`로 확인한다.

## 기존 snapshot을 보존하는 가상 이름

`tools/prepare_operations_emulator.cjs`는 catalog 문서의 이름까지 기존 fixture와 정확히 비교한다. seed의 이름을 직접 바꾸면 기존 `operations-20x80-v1`과 충돌하고, 직원용 확정 일정에 포함된 catalog 이름과도 달라질 수 있다.

따라서 이번 작업은 **저장 이름을 덮어쓰는 마이그레이션이 아니라 클라이언트 표시 별칭**이다.

- 적용 범위: `USE_FIREBASE_EMULATORS=true`, 프로젝트 `demo-senior-transport`, catalog 버전 `operations-20x80-v1`인 경우만 적용한다.
- `s1`~`s20`: 고정된 한국식 가상 직원 이름 20개. 기존 김다정·이온유·박여유도 유지한다.
- `p1`~`p80`: 성 10개와 이름 8개를 조합한 가상 이용자 이름 80개. 예: `p1 → 김영숙`, `p80 → 임종수`.
- 특정 인물이나 명부에서 수집한 데이터가 아니다. 실제 사람과 같은 이름이 있을 수 있지만 개인정보 자료를 사용하지 않았다. 주소·특이사항은 기존 가상 값을 유지한다.
- 관리자 catalog와 직원 본인의 snapshot 내 부분 catalog에 **동일한 ID 매핑**을 적용한다. 문서 순서가 달라도 같은 이름이 나온다.
- 알 수 없는 ID, 다른 catalog, 운영 프로젝트에는 적용하지 않는다. 기본 3명/5명 데이터와 40명/79명 부하 테스트 fixture도 바꾸지 않는다.
- 이름 이외의 ID·active·휴무 요일·차량·기본 코스·방문 순서·예상 시각·출처·계정 `staffId` 연결은 유지한다. 확정 payload에 이름이나 별칭 필드를 추가하지 않는다.

**기존 Emulator snapshot은 삭제·재등록·수정할 필요가 없다.** 앱을 완전히 새로고침하거나 다시 실행하면 기존 문서에서 읽은 이름을 새 별칭으로 표시한다. 기존 초기 데이터 도구와 fixture 파일, Authentication 계정·users·날짜별 일정은 이번 작업에서 변경하지 않았다. Emulator Console이나 서버가 읽는 원본 문서에는 기존 저장 이름이 남는다.

매핑 정의는 `lib/data/emulator_display_names.dart`에 있다. `FirebaseScheduleRepository`의 읽기 결과에만 적용하며, 서버용 데이터나 Functions의 AI 요청 로직을 변경하지 않는다.

## AI 일정 추천 검토

1. 대상 날짜·오전/오후, **가상 직선거리 비교와 감소/증가량·비율**을 먼저 표시한다.
2. **실제 도로 거리나 운행 시간 절감 수치가 아니다**라는 안내는 접지 않고 항상 표시한다. 변경이 같거나 개선이 없는 결과의 기존 안내도 유지한다.
3. 바뀌는 코스 수와 실제 변경 내용을 표시한다. 담당 직원·코스별로 **기존 순서 / 추천 순서**를 번호 목록으로 비교한다. PC에서는 나란히, 좁은 화면에서는 위아래로 배치한다.
4. 계산 방법, 긴 안내, 추천 근거는 **자세히 보기**에 접어 둔다. 화면의 수치와 요약은 기존 서버에서 계산한 거리 비교 결과를 사용한다.
5. **이 일정 사용하기 → 기존 방문 시간 확인 → 기존 최종 일정 확정** 흐름을 유지한다. 검토 UI가 초안이나 서버 데이터를 직접 바꾸지 않는다. 오래된 추천안 적용 차단도 유지한다.

## 최종 일정 확정 검토

대상 날짜·요일·오전/오후와 **최종 일정 확정 후 직원에게 공유됨**을 먼저 표시한다. 변경 코스 수와 변경 유형별 건수를 요약한 뒤 코스별 상세는 접어 둔다.

코스를 펼치면 기존/변경 방문 순서, 담당자·차량 변경, 이용자 이동·결석·제외, 운행·방문 시각 변경을 확인한다. 모든 코스를 확인하는 기존 전체 일정 펼치기도 유지한다.

변경 항목에는 표시용 `routeIds`를 연결했다. 이용자 이동은 출발·도착 두 코스의 상세에서 확인하지만 전체 유형별 건수는 한 번만 센다. 이 값은 Dart UI 비교 모델의 메타데이터이며 Firestore 스키마·요청 DTO에 추가하지 않는다. 기본 코스 기준으로만 연결 가능한 결석/제외 변경은 그 코스에 표시한다. 첫 확정은 ‘처음 확정할 코스’로 구분하고, 변경이 없는 경우도 명확히 안내한다.

## 변경 파일

- `lib/main.dart`, `lib/screens/login_screen.dart`, `lib/screens/schedule_screen.dart`, `web/index.html`, `web/manifest.json`: 앱명·테스트 데이터 표시, 간결한 방문 시간 확인 안내.
- Android/iOS/macOS/Windows의 표시 리소스: 플랫폼 표시 이름만 통일.
- `lib/data/emulator_display_names.dart`, `lib/services/schedule_repository.dart`: Emulator 읽기 결과에만 적용하는 표시 별칭.
- `lib/models/schedule_changes.dart`: 변경 항목의 코스별 UI 연결 정보. 기존 변경 유형·설명·서버 payload는 유지.
- `lib/widgets/course_change_details.dart`: 코스별 기존/변경 방문 순서와 상세를 보여주는 공통 표시 위젯.
- `lib/widgets/ai_schedule_suggestion_dialog.dart`, `lib/widgets/schedule_change_review.dart`: 효과/요약 우선 배치와 접이식 상세.
- `test/friendly_presentation_test.dart` 및 기존 관련 UI 테스트: 별칭·snapshot 호환성·표시 전환·추천/확정 동선 검증.

Cloud Functions, Firestore/Storage Rules, Firebase 설정과 실제 사용자 데이터는 이번 작업에서 수정하거나 배포하지 않았다. 기존 미커밋 작업도 보존했다.

## 로컬 검증

- `flutter analyze`: 문제 없음.
- Flutter 전체 테스트: **222개 통과**(기존 212개 + 신규 10개).
- Auth/Firestore/Functions Emulator 회귀: **110개 통과**. 기존 시연 인스턴스를 보존하고 별도 demo namespace와 포트 9198/8190/5102에서 실행했다.
- `flutter build web --debug --dart-define=USE_FIREBASE_EMULATORS=true --no-pub`: 성공. 생성된 HTML의 브라우저/Apple Web 앱 제목도 확인했다.
- 신규 테스트는 20명·80명 ID/속성/확정 payload 보존, 운영/다른 fixture 미적용, 기존 JSON 불변·반복 읽기·직원 부분 snapshot의 이름 일치, 이동 건수와 양쪽 코스 연결, 320/390/1280px 추천·확정 UI를 검증한다. 기존 검증·오래된 결과 차단·AI 적용→시간 확인→최종 확정 테스트도 유지한다.
- `USE_FIREBASE_EMULATORS=true` 옵션으로 직원·관리자·추천/확정 UI 관련 31개 테스트도 통과했다. 테스트 데이터 표시가 추가된 실제 빌드 조건에서 작은 화면 레이아웃을 확인했다.

화면 이미지: `.local-tools/friendly-ui/ai-320.png`, `ai-390.png`, `ai-1280.png`, `confirm-320.png`, `confirm-390.png`, `confirm-1280.png`. Flutter 위젯 캡처와 가상 저장소 검증이며 실제 모바일 기기·네이티브 앱 실행 시험은 남아 있다. 자동 테스트는 고정 AI 응답을 사용한다.

로그: `.local-tools/friendly-ui-flutter.log`, `friendly-ui-emulator.log`, `friendly-ui-web-build.log`, `friendly-ui-emulator-layout.log`.
