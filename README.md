# 송영도우미

주간보호센터의 송영 일정을 관리하고, 직원이 자신의 방문 순서와 업무 사진을 확인·등록하는 Flutter Web 시제품입니다. 직원·어르신·주소·차량·코스는 모두 시연용 가상 데이터입니다.

## 처음 오셨나요?

| 하고 싶은 일 | 읽을 문서 |
| --- | --- |
| 설치 없이 배포된 앱 사용해 보기, 의견 보내기 | [앱 테스트 안내](docs/TEST_GUIDE.md) |
| 내 컴퓨터에 설치하고 개발 참여하기 | [팀원 시작 안내](docs/TEAM_GUIDE.md) |
| 작업 브랜치와 코드 검토 규칙 확인하기 | [개발 참여 규칙](CONTRIBUTING.md) |

GitHub 계정과 앱 로그인 계정은 서로 다릅니다. 앱 계정은 담당자에게 개인적으로 요청하며, 회원가입 화면은 제공하지 않습니다.

## 주요 기능

- 관리자: 송영 현황, 직원·어르신 검색, 방문 순서와 배정 변경, 일정 확정
- 날짜별 오전·오후 일정 관리, 선택적으로 입력하는 오전 약속 시간
- 직원 결근 등록, 코스 인계, 어르신 결석·복귀 및 재배정
- AI 일정 추천을 검토하고 적용하기: AI가 일정을 자동 확정하지 않습니다.
- 직원: 본인의 확정 일정 조회, 업무 시작·종료 사진 등록
- 관리자: 직원별 사진 등록 여부와 등록 시각 조회
- Firebase 로그인과 역할별 접근 제한, 일정 검증 및 동시 수정 방지

기본 코스와 날짜별 일정은 구분합니다. 오전 변경은 오후에 자동 적용되지 않습니다. 편집 중인 내용은 확정 전까지 다른 직원에게 공유되지 않으며, 새로고침하면 저장하지 않은 변경이 사라질 수 있습니다. 확정 일정은 Firestore에 저장합니다.

## 안전한 로컬 실행

**기본 실행은 실제 Firebase에 연결됩니다.** 아래 옵션을 빼거나 VS Code의 기본 실행 버튼만 누르지 마세요. 팀원의 기본 개발 환경은 `demo-senior-transport` Emulator입니다. 실제 계정·API 키는 필요하지 않습니다.

먼저 [팀원 시작 안내](docs/TEAM_GUIDE.md)의 설치, AI 외부 호출 차단, 로컬 계정 준비를 완료하세요. 아래 명령은 프로젝트 최상위 폴더의 PowerShell에서 실행합니다.

```powershell
flutter pub get
npm.cmd --prefix functions ci
```

터미널 A에서 Emulator를 켜 둡니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/start_operations_emulators.ps1
```

터미널 B에서 안내서의 **로컬 계정과 일정 준비** 단계를 실행한 뒤 앱을 켭니다.

```powershell
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=ENABLE_PRODUCTION_AI=false --dart-define=ENABLE_STORAGE_WORK_PHOTOS=false
```

시작 로그에서 `project=demo-senior-transport`, `environment=emulator`를 확인하고 **로컬 계정으로만** 로그인합니다. `localhost` 주소만으로는 Emulator 연결 여부를 판단할 수 없습니다.

## 로컬에서 확인할 흐름

1. 관리자로 로그인하여 날짜·오전/오후를 선택합니다.
2. 직원의 코스를 열고 결석 처리, 어르신 이동, 방문 순서 변경을 해 봅니다.
3. 변경 내용을 확인하고 일정 확정을 진행합니다. 정원 초과 등 오류는 먼저 해결합니다.
4. 로그아웃 후 해당 직원의 로컬 계정으로 로그인하여 확정된 본인 일정을 확인합니다.
5. 오늘의 확정 일정에서 개인정보가 없는 샘플 사진으로 시작·종료 등록을 확인합니다.

정원은 운전 직원을 제외한 이용자 수 기준이며 직원·차량 중복, 근무 불가, 결근, 잘못된 이용자 배정 등을 검증합니다. 로컬 준비 도구는 직원 20명·어르신 80명 데이터를 사용합니다. 운영에 등록된 다른 규모의 데이터와 별개입니다. AI 실호출은 외부 비용이 발생할 수 있어 기본 안내에서는 차단합니다. 자동 테스트는 모의 AI 응답을 사용합니다.

## 테스트

```powershell
flutter analyze
flutter test
```

전체 서버 회귀 테스트는 먼저 실행 중인 로컬 Emulator를 `Ctrl+C`로 종료한 뒤 실행합니다. Storage Emulator도 자동으로 사용합니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/test-emulators.ps1
```

## 프로젝트 구조와 참고 문서

| 위치 | 내용 |
| --- | --- |
| `lib/` | Flutter 화면, 모델, 로그인·일정·사진 처리 |
| `functions/` | 서버 권한 검사, 일정 확정, AI·사진 함수 |
| `tools/` | 로컬 가상 데이터 준비 및 검증 도구. 운영용 도구는 담당자만 사용 |
| `test/` | Flutter 기능·화면 테스트 |
| `docs/` | 요구사항, 기능별 설계 및 배포 검토 |

- [최초 프로젝트 개요](docs/project-overview.md), [요구사항](docs/requirements.md), [업무 규칙](docs/business-rules.md)
- [Firestore 일정 구조](docs/firestore-schedules.md), [현재 약속 시간 정책](docs/appointment-time-simplification.md)

과거 설계 문서는 작성 당시의 정책을 담을 수 있습니다. 현재 실행은 팀 안내서와 코드 기준으로 확인합니다. Firebase 배포·계정 생성·운영 데이터 변경은 담당자만 수행합니다. 비밀번호, Gemini 키, 서비스 계정 키는 Git이나 Issues에 올리지 마세요.
