# 팀원 시작 안내

Windows PC와 GitHub Desktop 기준입니다. 코드를 고치지 않고 앱만 확인하려면 [앱 테스트 안내](TEST_GUIDE.md)부터 읽으세요. 설치에 막히면 오류 화면을 남기고 담당자에게 질문하세요. 운영 Firebase 설정을 바꿔 해결하지 않습니다.

## 1. 계정 만들고 초대 수락하기

1. [GitHub 가입](https://github.com/signup)에서 본인 이메일로 계정을 만들고 이메일 인증을 완료합니다.
2. 담당자에게 **GitHub 사용자 이름**을 알려 저장소 초대를 요청합니다. 비밀번호는 보내지 않습니다.
3. 초대 이메일의 링크 또는 GitHub 알림에서 저장소 이름을 확인하고 **Accept invitation**을 누릅니다.
4. [프로젝트 저장소](https://github.com/baek-jaekwang/senior-transport-app)가 열리는지 확인합니다. 404가 보이면 로그인 계정과 초대 수락 여부를 확인합니다.

GitHub는 코드 공유용이고 앱 로그인은 Firebase 계정입니다. 두 계정은 별개입니다. 로컬 앱 계정은 아래 준비 단계에서 만듭니다.

## 2. GitHub Desktop 설치와 Clone

1. [GitHub Desktop](https://desktop.github.com/download/)을 설치합니다.
2. 첫 화면의 **Sign in to GitHub.com**을 누르고 브라우저에서 본인 계정으로 승인합니다. 이미 실행 중이면 **File → Options → Accounts**에서 로그인합니다.
3. **File → Clone Repository… → URL**을 선택합니다.
4. Repository URL에 `https://github.com/baek-jaekwang/senior-transport-app.git`을 입력합니다.
5. Local Path에는 예를 들어 `C:\dev\senior-transport-app`을 지정하고 **Clone**을 누릅니다. OneDrive 공유 폴더는 피하는 편이 좋습니다.
6. **Repository → Open in Visual Studio Code**로 엽니다. 메뉴가 없으면 VS Code 설치 후 **File → Open Folder…**에서 내려받은 폴더를 선택합니다.

Clone은 코드를 내 컴퓨터에 내려받는 일입니다. Fork를 만들라는 창이나 권한 오류가 나오면 담당자에게 초대 상태를 확인하세요. 새 저장소나 Firebase 프로젝트를 만들 필요는 없습니다.

## 3. 개발 프로그램 설치

아래는 현재 프로젝트에서 확인한 조합입니다. 임의로 최신 버전을 설치했을 때 문제가 나면 이 조합부터 맞춥니다.

| 프로그램 | 기준 | 설치 안내 |
| --- | --- | --- |
| Git for Windows | Git 명령을 PATH에서 실행 가능하게 설치 | [공식 설치](https://git-scm.com/install/windows) |
| VS Code | Windows용 | [공식 다운로드](https://code.visualstudio.com/download) |
| Flutter SDK | Flutter 3.47.9 stable / Dart 3.13.7 | [공식 설치](https://docs.flutter.dev/install/with-vs-code), [버전별 SDK](https://docs.flutter.dev/install/archive) |
| Node.js | 22.x, 확인 버전 22.23.5 | [공식 다운로드](https://nodejs.org/en/download) |
| Java JDK | 21 | [Temurin 다운로드](https://adoptium.net/temurin/releases/)에서 Windows·JDK 21 선택 |
| Chrome | 웹 앱 실행용 | 설치되어 있으면 재사용 |

GitHub Desktop을 설치했어도 Flutter가 사용할 Git 명령이 별도로 필요할 수 있으므로 Git for Windows도 설치합니다. Git 설치 중 명령줄에서도 Git을 쓰는 PATH 옵션을 유지하세요. Java는 설치 시 PATH와 JAVA_HOME 설정 옵션을 사용합니다.

Flutter를 ZIP으로 설치한다면 `C:\dev\flutter`처럼 프로젝트 밖에 풀고 `C:\dev\flutter\bin`을 사용자 PATH에 추가합니다. [PATH 설정 안내](https://docs.flutter.dev/install/add-to-path)를 참고하세요. 저장소의 `.local-tools`는 개인 도구 폴더이므로 Clone에 포함되지 않습니다.

VS Code 왼쪽 **Extensions**에서 제작자가 Dart Code인 **Flutter** 확장을 설치합니다. Dart 확장도 함께 설치되는지 확인합니다. 설치 후 VS Code와 터미널을 모두 닫았다 다시 엽니다.

VS Code **Terminal → New Terminal**을 누르고 PowerShell인지 확인한 뒤 실행합니다.

```powershell
git --version
flutter --version
dart --version
node --version
npm.cmd --version
java -version
flutter doctor
flutter devices
```

`flutter devices`에 Chrome이 나와야 합니다. 웹 개발만 하는 경우 Android SDK나 Visual Studio C++ 관련 doctor 경고를 해결하려고 추가 설치할 필요는 없습니다. Flutter/Dart와 Chrome 항목을 먼저 확인하세요.

Firebase CLI도 설치합니다. 이 프로젝트에서 확인한 버전은 다음과 같습니다.

```powershell
npm.cmd install -g firebase-tools@15.36.0
firebase.cmd --version
```

이 안내의 로컬 작업에는 Firebase Console 권한, 결제 등록, 서비스 계정 키가 필요하지 않습니다. `firebase init`, `flutterfire configure`, 실제 프로젝트 로그인이나 배포를 실행하지 마세요. [Emulator 공식 설치 안내](https://firebase.google.com/docs/emulator-suite/install_and_configure)도 참고할 수 있습니다.

## 4. 수정 전에 내 작업 브랜치 만들기

브랜치는 다른 사람의 작업에 영향을 주지 않는 개인 작업 줄기입니다.

1. Desktop의 **Changes**에 수정 파일이 없는지 확인합니다.
2. **Current Branch**에서 기준 브랜치를 선택합니다. 보통 `main`입니다. 최신 앱이 아직 작업 브랜치에만 있다면 **담당자가 지정한 기준 브랜치**를 사용합니다.
3. **Fetch origin**을 누르고 **Pull origin**이 나타나면 누릅니다.
4. **Current Branch → New Branch**에서 이름을 입력합니다. 예: `docs/minsu-first-guide`, `feature/minsu-photo-label`.
5. 생성 기준이 2번 브랜치인지 확인하고 **Create Branch**를 누릅니다.
6. 상단에 내 새 브랜치 이름이 표시되는지 확인한 다음 파일을 수정합니다.

`main`과 다른 사람·공동 작업 브랜치에는 직접 Commit·Push하지 않습니다. 자세한 규칙은 [CONTRIBUTING](../CONTRIBUTING.md)을 따릅니다.

## 5. 프로젝트 준비와 외부 AI 호출 차단

VS Code에서 연 폴더 안에 `pubspec.yaml`, `firebase.json`, `functions`, `tools`가 보여야 합니다. 터미널도 이 최상위 폴더에서 실행합니다.

```powershell
flutter pub get
npm.cmd --prefix functions ci
```

처음에는 AI 실호출 없이 기본 업무를 연습합니다. Emulator여도 Gemini API는 외부 서비스이므로 별도 차단이 필요합니다.

VS Code 탐색기에서 `functions` 폴더를 우클릭하여 **New File**로 `.secret.local`을 만듭니다. **이미 파일이 있다면 덮어쓰지 말고 담당자에게 확인**하세요. 새 파일에는 아래 한 줄만 넣습니다. 따옴표 사이에는 **공백 한 칸**이 있습니다. 빈 문자열로 바꾸지 마세요.

```dotenv
GEMINI_API_KEY=" "
```

이 값은 키가 아닙니다. 로컬 Secret 대체값을 제공하고 서버가 외부 호출 전에 중단하게 합니다. `.secret.local`은 Git 제외 대상입니다. Desktop의 Changes에도 나타나지 않는지 확인하세요. 실제 Gemini 키나 서비스 계정 파일을 받아 넣지 않습니다. [로컬 Secret 공식 안내](https://firebase.google.com/docs/emulator-suite/connect_functions)를 참고하세요.

## 6. 터미널 A: Emulator 켜기

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/start_operations_emulators.ps1
```

서버가 계속 켜져 있어야 합니다. 준비 완료 로그가 나올 때까지 기다립니다. 첫 실행에는 도구 다운로드가 필요할 수 있습니다.

| 구분 | 로컬 Emulator | 실제 Firebase |
| --- | --- | --- |
| 대상 | 내 PC의 `demo-senior-transport` | 팀이 공유하는 실제 프로젝트 |
| 계정·데이터 | 로컬 전용 | 배포된 앱에서 사용하는 계정·기록 |
| 연결 | Auth 9099, Firestore 8080, Functions 5001 | 인터넷의 Firebase 서비스 |
| 주의 | Gemini 같은 외부 API는 따로 차단 | 변경이 다른 팀원에게 보이고 비용이 발생할 수 있음 |

현재 실행 도구는 Emulator 관리 웹 화면을 켜지 않습니다. `localhost:4000`이 안 열려도 정상입니다. `-ImportSnapshot`은 별도 로컬 파일이 필요한 담당자용 옵션이므로 처음에는 사용하지 않습니다.

## 7. 터미널 B: 로컬 계정과 일정 준비

터미널 우측 **+**로 PowerShell을 하나 더 엽니다. A는 계속 켜 둡니다. 아래를 B에 붙여 넣습니다.

```powershell
$env:GCLOUD_PROJECT = 'demo-senior-transport'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
$localDemoPassword = Read-Host '로컬 전용 비밀번호를 12자 이상 입력하세요' -AsSecureString
try {
    $env:EMULATOR_USER_PASSWORD = [System.Net.NetworkCredential]::new('', $localDemoPassword).Password
    node tools/prepare_operations_emulator.cjs
    if ($LASTEXITCODE -ne 0) { throw '로컬 준비 실패: 표시된 안전한 오류 코드를 확인하세요.' }
} finally {
    Remove-Item Env:EMULATOR_USER_PASSWORD -ErrorAction SilentlyContinue
    $localDemoPassword.Dispose()
}
```

입력한 비밀번호는 표시되지 않습니다. 실제 서비스에서 쓰는 비밀번호를 재사용하지 말고, 브라우저 로그인에 사용할 수 있도록 본인이 기억하세요. Git·Issues·단체 채팅에 쓰지 않습니다. 성공 결과에는 생성 개수가 표시되며 비밀번호나 UID는 출력하지 않습니다.

이 도구는 직원 20명·어르신 80명·차량 20대, 오전/오후 각각 기본 코스 19개, 오늘·내일의 확정 일정을 준비합니다. 예비 직원이 포함되므로 직원 수와 코스 수가 다릅니다. 오후에는 결석·제외 상황도 들어 있습니다. 다른 등록 도구의 10명·24명 또는 25명·80명 자료와 혼용하지 마세요.

| 로컬 로그인 이메일 | 용도 |
| --- | --- |
| `ops-admin@example.invalid` | 관리자 |
| `ops-s1@example.invalid` | 첫 번째 직원 |
| `ops-s2@example.invalid` ~ `ops-s20@example.invalid` | 나머지 직원 |

이 주소들은 **로컬 준비 도구 전용**입니다. 비밀번호는 위에서 직접 입력한 값입니다. 기존 로컬 계정을 재사용하면 비밀번호는 바뀌지 않으므로 최초 등록 때의 값을 사용합니다. 충돌 오류가 나면 기존 데이터 삭제나 비밀번호 초기화를 하지 말고 담당자에게 문의하세요.

## 8. 앱 실행과 첫 확인

같은 터미널 B에서 실행합니다.

```powershell
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=ENABLE_PRODUCTION_AI=false --dart-define=ENABLE_STORAGE_WORK_PHOTOS=false
```

1. 시작 로그에서 `project=demo-senior-transport`, `environment=emulator`를 확인합니다. 실제 프로젝트가 보이면 로그인하지 말고 `q`로 종료합니다.
2. 위 로컬 관리자 계정으로 로그인합니다. 날짜와 오전/오후, 직원 목록을 확인합니다.
3. 직원 한 명을 선택하여 방문 순서를 바꾸고 변경 확인 후 확정합니다.
4. 로그아웃 후 해당 직원의 로컬 계정으로 로그인하여 공유된 일정을 확인합니다.
5. 사진은 **오늘의 본인 확정 일정**에서 개인정보 없는 샘플로 등록합니다. 결근·휴무 등 등록이 불가능한 상태는 우회하지 않습니다.

오전 약속 시간은 직접 입력하는 선택 항목이고 오후에는 방문 순서를 사용합니다. AI 추천은 위 설정에서 호출되지 않는 것이 정상입니다. `ENABLE_PRODUCTION_AI=false`만으로 Emulator의 외부 AI 호출을 막을 수 없으므로 5번의 로컬 Secret 설정도 필요합니다.

기본 사진 경로는 로컬 Firestore 저장 방식입니다. 운영 Storage 사진 기능 검증과는 구분합니다. Storage 전용 테스트·실제 AI 호출은 담당자와 별도로 진행합니다.

한국 시간 기준 09:30부터 오늘 오후, 19:00부터 내일 오전이 처음 선택됩니다. 직접 날짜를 고르면 자동으로 바뀌지 않으며 **현재 일정**으로 돌아갈 수 있습니다. 19시 이후 오늘 사진을 연습하려면 날짜를 오늘로 선택합니다.

VS Code 기본 F5나 옵션 없는 Flutter 실행은 실제 Firebase에 연결될 수 있습니다. 항상 위 명령을 사용하세요. 실행 옵션을 바꿀 때는 `q`로 종료하고 명령 전체를 다시 실행합니다.

## 9. 종료와 다음 실행

- Flutter 터미널에서 `q`, Emulator 터미널에서 `Ctrl+C`로 종료합니다.
- 기본 도구는 종료 시 데이터를 자동 저장하지 않습니다. 재시작하면 6~8번을 다시 진행합니다. 별도 저장본이 필요하면 담당자에게 요청하세요.
- 다른 도구가 준비한 데이터나 저장본이 있다면 삭제하지 않습니다. 초기화·정리 명령은 이 안내에 포함하지 않습니다.

## 10. 수정 확인, Commit, Push, Pull Request

1. 내 개인 브랜치에서 작은 작업 하나를 수정하고 저장합니다.
2. 앱 코드를 바꿨으면 터미널에서 실행합니다.

   ```powershell
   flutter analyze
   flutter test
   ```

3. 서버·권한·사진 관련 작업은 수동 Emulator를 먼저 종료한 뒤 회귀 테스트도 합니다. 모의 AI 응답을 사용하며 Gemini 키는 필요하지 않습니다.

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/test-emulators.ps1
   ```

4. Desktop **Changes**에서 파일별 변경 줄을 읽고 관련 파일만 체크합니다. 키, 비밀번호, 로컬 데이터, 빌드 파일이 없는지 확인합니다.
5. **Summary**에 예를 들어 `직원 화면 안내 문구 정리`를 쓰고 **Commit to 내-브랜치**를 누릅니다. Commit은 내 PC에 변경을 기록하는 일입니다.
6. 첫 공유는 **Publish branch**, 이후에는 **Push origin**을 누릅니다. Push는 내 브랜치를 GitHub에 보내는 일입니다.
7. **Preview Pull Request / Create Pull Request**로 브라우저를 엽니다. 메뉴 이름은 Desktop 버전에 따라 다를 수 있습니다.
8. **base**는 담당자가 정한 기준 브랜치, **compare**는 내 개인 브랜치인지 확인합니다. 예상 밖의 많은 파일이 보이면 제출 전에 담당자에게 문의합니다.
9. 제목과 변경 목적, 테스트 결과, 남은 문제를 적고 **Create pull request**를 누릅니다. 검토자를 요청하고 스스로 병합하지 않습니다.

문서만 수정했다면 명령·링크·화면 설명을 검토하고 PR에 문서만 수정했다고 적습니다. PR은 코드 검토 요청이며 앱 배포가 아닙니다. 공개 Firebase 웹 설정과 달리 Gemini 키·서비스 계정 키는 비밀정보입니다. 기존 설정 파일을 임의로 지우거나 교체하지 않습니다.

## 11. 다른 팀원의 최신 변경 받기

1. 현재 작업을 개인 브랜치에 Commit합니다. 저장하지 않은 변경이 있는 채로 브랜치를 바꾸지 않습니다.
2. 기준 브랜치로 이동하여 **Fetch origin → Pull origin**을 누릅니다.
3. 내 개인 브랜치로 돌아옵니다. **Current Branch → Choose a branch to merge into…**에서 기준 브랜치를 선택하고 병합 버튼을 누릅니다.
4. 충돌 표시가 나오면 진행을 멈추고 담당자와 해결합니다. 전체 파일을 버리는 **Discard**, **Force push**, 임의의 초기화로 해결하지 않습니다.
5. 의존성이 바뀌었다면 `flutter pub get`, `npm.cmd --prefix functions ci`를 다시 실행하고 테스트합니다.

Fetch는 새 변경이 있는지 확인하고, Pull은 현재 브랜치로 내려받습니다. [공식 Desktop 최신 변경 받기 안내](https://docs.github.com/en/desktop/working-with-your-remote-repository-on-github-or-github-enterprise/syncing-your-branch-in-github-desktop)도 참고하세요.

## 12. 자주 발생하는 문제

| 증상 | 확인할 일 |
| --- | --- |
| 명령을 찾을 수 없음 | 설치와 PATH를 확인하고 VS Code·터미널을 다시 엽니다. |
| `npm.ps1` 실행 정책 오류 | 안내처럼 `npm.cmd`, `firebase.cmd`를 사용합니다. 시스템 정책을 통째로 해제하지 않습니다. |
| `pubspec.yaml`을 찾지 못함 | 터미널을 프로젝트 최상위 폴더로 옮깁니다. |
| Dart 버전 조건 불일치 | 위 Flutter/Dart 버전을 확인합니다. `pubspec.yaml` 조건을 낮추지 않습니다. |
| 포트 사용 중 | 기존 Emulator 터미널을 확인합니다. 다른 사람·프로그램을 임의 종료하지 않습니다. |
| 로컬 준비 실패 | 출력된 `errorCode`, `stage`와 Emulator 준비 완료 여부를 확인합니다. 데이터를 지우지 않습니다. |
| 로그인 `user-not-found` | Emulator 옵션과 7번 준비 성공 여부를 확인합니다. 실제 계정을 넣어 해결하지 않습니다. |
| 로그인 비밀번호 오류 | 로컬 계정을 처음 만들 때 사용한 비밀번호인지 확인합니다. 준비 도구는 기존 비밀번호를 바꾸지 않습니다. |
| 권한 없음, 결근 조회 실패 | 로그인 역할·연결 환경과 Emulator 로그를 담당자에게 전달합니다. Rules를 완화하지 않습니다. |
| 실제 Firebase 연결 로그가 나옴 | 앱을 종료하고 8번 명령 전체로 다시 실행합니다. 이미 변경했다면 담당자에게 즉시 알립니다. |
| 사진 등록 불가 | 오늘 날짜, 본인 확정 코스, 결근 여부를 확인합니다. 운영 Storage 설정을 켜서 해결하지 않습니다. |
| AI 키 설정 안내 | 기본 연습에서는 정상입니다. 실제 키를 넣거나 반복 요청하지 않습니다. |
| `firebase_options.dart` 없음 | 담당자가 지정한 최신 브랜치인지 확인합니다. 직접 Firebase 연결을 다시 구성하지 않습니다. |
| Clone/Push 권한 없음 | GitHub 로그인 계정과 초대 수락을 확인하고 담당자에게 요청합니다. |

질문할 때는 실행 단계, 안전한 오류 코드, 사용한 명령(민감정보 제외), 화면을 전달합니다. 비밀번호·토큰·키·UID·전체 Console 로그는 올리지 않습니다. 실수로 비밀정보를 Commit/Push했다면 파일만 지우지 말고 담당자에게 비공개로 즉시 알려 폐기·교체하도록 합니다.

## 처음 참여한 날의 완료 기준

- GitHub 초대를 수락하고 저장소를 Clone했습니다.
- 필요한 프로그램의 버전을 확인하고 개인 브랜치를 만들었습니다.
- Emulator 연결 로그를 확인하고 로컬 관리자·직원으로 각각 로그인했습니다.
- 관리자가 확정한 일정이 직원에게 보이는지 확인했습니다.
- 개인정보 없는 사진으로 오늘의 시작·종료 등록을 연습했습니다.
- 수정 사항이 있다면 테스트 결과와 함께 개인 브랜치에서 PR을 보냈습니다.

## 이 안내서와 Issue 양식을 GitHub에 반영하기

이번 문서는 현재 작업 내용이 있는 브랜치를 기준으로 새 `docs/본인이름-team-guide` 브랜치를 만들어 제출합니다. 이미 수정된 파일이 있다면 Desktop의 브랜치 이동 창에서 **Bring my changes to…**로 새 개인 브랜치에 가져갑니다. 기존 작업 브랜치에 그대로 Commit·Push하지 않습니다.

Changes에서 `README.md`, `CONTRIBUTING.md`, `docs/TEAM_GUIDE.md`, `docs/TEST_GUIDE.md`와 `.github/ISSUE_TEMPLATE/` 안의 YAML 3개, 총 7개 파일만 선택합니다. Commit → Publish branch → PR을 진행하고, base가 승인된 기준 브랜치인지 확인합니다. 아직 기준이 `main`이 아니라면 다른 기능까지 섞어 `main`에 직접 PR하지 않습니다.

Issue 양식은 **저장소 기본 브랜치에 병합된 뒤** 사용됩니다. 담당자가 최종 기본 브랜치 반영과 Issues 활성화를 확인한 다음 **Issues → New issue**에서 오류 제보·개선 제안 양식이 보이는지 확인합니다. 문서 공유에는 Firebase 빌드·배포가 필요하지 않습니다.
