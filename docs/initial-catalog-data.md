# 실제 Firebase 초기 등록용 기준 가상 데이터

이 문서는 tools/fictional_catalog.cjs의 `fictionalCatalog(false)`와 Flutter의 ScheduleCatalog 파서를 기준으로 한다. 실제 Firestore에 접속하거나 데이터를 수정하지 않았다. 기본 데이터와 설정의 최종 목표 상태는 [deploy-test-v1.baseline.json](fixtures/deploy-test-v1.baseline.json)에 정리했다. 이 JSON은 운영자용 `tools/register-initial-catalog.cjs`의 입력 manifest이며 Firebase CLI import 형식은 아니다.

## staff/s1에 입력할 값

경로: `catalogs/deploy-test-v1/staff/s1`

| 필드 | Firestore 타입 | 값 | 필수 여부 |
|---|---|---|---|
| name | string | 김다정 | 파서에서 필수 |
| active | boolean | true | 파서에서 필수; 직원 로그인 허용에도 필요 |
| unavailableWeekdays | array | [] | 현재 코드상 생략/null이면 빈 목록. 기준 데이터와 동일하게 명시 권장 |

```json
{
  "name": "김다정",
  "active": true,
  "unavailableWeekdays": []
}
```

id는 필드로 입력할 필요가 없다. 문서 ID s1에서 읽는다. 직원 master에 role/email/staffId/비밀번호를 넣을 필요도 없다. 로그인 계정의 `users/<Auth UID>`에 role="staff", active=true, staffId="s1"을 유지하여 연결한다. 기존 Auth UID를 바꾸지 않는다.

요일 배열의 원소는 정수이며 월=1, 화=2, 수=3, 목=4, 금=5, 토=6, 일=7이다.

| 직원 문서 ID | name | active | unavailableWeekdays |
|---|---|---|---|
| s1 | 김다정 | true | [] |
| s2 | 이온유 | true | [] |
| s3 | 박여유 | true | [5] |

## 차량

경로: `catalogs/deploy-test-v1/vehicles/<문서 ID>`

필수 필드는 name(string), passengerCapacity(number 정수)다.

```json
{
  "name": "햇살 1호",
  "passengerCapacity": 3
}
```

| 문서 ID | name | passengerCapacity |
|---|---|---|
| v1 | 햇살 1호 | 3 |
| v2 | 나무 2호 | 3 |
| v3 | 예비 3호 | 2 |

## 이용자

경로: `catalogs/deploy-test-v1/passengers/<문서 ID>`

name, address, note는 모두 string이며 현재 파서에서 모두 필요하다. 주의사항이 없더라도 필드를 생략하지 않고 빈 문자열을 사용할 수 있다. 아래 값은 프로젝트에 정의된 가상 정보다.

```json
{
  "name": "가상 어르신 A",
  "address": "가상마을 햇살길 1",
  "note": "승하차 시 천천히 안내"
}
```

| 문서 ID | name | address | note |
|---|---|---|---|
| p1 | 가상 어르신 A | 가상마을 햇살길 1 | 승하차 시 천천히 안내 |
| p2 | 가상 어르신 B | 가상마을 햇살길 2 | 도착 후 초인종으로 안내 |
| p3 | 가상 어르신 C | 가상마을 햇살길 3 | 현관 앞에서 탑승 |
| p4 | 가상 어르신 D | 가상마을 나무길 1 | 승하차 시 천천히 안내 |
| p5 | 가상 어르신 E | 가상마을 나무길 2 | 정문 앞에서 탑승 |

## 기본 코스

경로: `catalogs/deploy-test-v1/baseRoutes/<문서 ID>`

필수 필드는 name/period/staffId/vehicleId(string), passengerIds(array of string)이다. period는 정확히 morning 또는 afternoon이다. passengerIds 배열 순서가 기본 방문 순서다.

```json
{
  "name": "햇살 A코스",
  "period": "morning",
  "staffId": "s1",
  "vehicleId": "v1",
  "passengerIds": ["p1", "p2", "p3"]
}
```

| 문서 ID | name | period | staffId | vehicleId | passengerIds |
|---|---|---|---|---|---|
| morning-a | 햇살 A코스 | morning | s1 | v1 | ["p1","p2","p3"] |
| morning-b | 나무 B코스 | morning | s2 | v2 | ["p4","p5"] |
| afternoon-a | 햇살 A코스 | afternoon | s1 | v1 | ["p3","p1","p2"] |
| afternoon-b | 나무 B코스 | afternoon | s2 | v2 | ["p5","p4"] |

예상 방문/운행 시각은 기본 코스 필드가 아니라 날짜별 일정(RouteAssignment)에 저장한다. 초기 기본 데이터 등록 도구가 schedules/staffSchedules/commits를 미리 생성해서는 안 된다.

## 개수 및 부모 설정

| 구분 | 실제 초기 등록용 기준 | Emulator 부하 검증용 |
|---|---|---|
| 직원 | 3명 | 40명 |
| 차량 | 3대 | 40대 |
| 이용자 | 5명 | 79명 |
| 기본 코스 | 4개 (오전 2 + 오후 2) | 78개 (오전 39 + 오후 39) |
| catalog 자식 문서 합계 | 15개 | 237개 |

실제 초기 등록 대상은 왼쪽 기준이다. catalog 부모와 settings 문서까지 포함하면 17개 문서다. Auth 계정, users, 날짜별 확정 일정은 이 개수에 포함하지 않는다.

부모 `catalogs/deploy-test-v1`의 최종 필드:

```json
{"ready": true, "fictional": true, "schemaVersion": 1}
```

설정은 **settings/schedules 문서**의 필드다.

```json
{"catalogVersion": "deploy-test-v1"}
```

개별 Console 등록 중에는 ready=false로 두고, 모든 자식 데이터 검증 후 ready=true 및 settings 전환을 수행한다. 실제 활성 사용자의 staffId가 s1/s2/s3 외에 이미 존재한다면 이 기준 catalog로 무조건 전환하지 않는다. 해당 연결을 먼저 확인해야 한다.

## 수동 입력 대신 안전하게 일괄 등록하는 방법

운영자용 `tools/register-initial-catalog.cjs`를 구현했다. [실행 절차와 충돌 대응](initial-catalog-cli.md)을 따른다. 기존 tools/seed_emulator.cjs는 변경하지 않았으며 계속 Emulator 전용이다. 내부 registerCatalog 헬퍼는 settings를 set으로 교체하므로 실제 DB에 직접 호출하지 않는다.

권장 방식은 신뢰할 수 있는 개발 환경에서 IAM/ADC를 사용하는 **별도 Firebase Admin SDK 일회성 등록 도구**다. 일반 Flutter 앱이나 공개 Callable로 제공하지 않는다. firebase login만으로 Admin SDK 자격 증명이 자동 구성된다고 가정하지 않으며, 서비스 계정 개인키를 Git/앱에 넣지 않는다. [Admin SDK 설정](https://firebase.google.com/docs/admin/setup)

구현된 실제용 도구의 동작:

1. 등록 데이터는 이 manifest의 기준 15개로 고정한다. --scale을 허용하지 않는다.
2. 프로젝트 ID senior-transport-app, 기본 DB, catalog 버전 및 대상 경로 목록을 명시한다. 오타·다른 프로젝트·예상하지 못한 Emulator 환경이면 거부한다.
3. 오프라인 계획 확인 → 실제 DB 읽기 전용 사전 점검 → 사용자 명시적 적용 단계로 나눈다. 읽기 전용 점검도 실제 Firestore 읽기 비용은 발생할 수 있으므로 사용자 선택으로 수행한다.
4. 기존 부모/자식 문서와 settings를 먼저 읽는다. 정확히 같은 자식은 보존하고 누락 자식만 생성한다. 값이 다른 문서, 예상 외 자식, 잘못된 부모 필드, 미완료 부모, 다른 버전 포인터는 중단 사유다. 자동 덮어쓰기·삭제·부모 보정은 하지 않는다.
5. 모든 읽기를 쓰기 전에 수행하는 트랜잭션으로 누락 자식을 create한다. 저장된 자식 15개를 재검증한 뒤 별도 트랜잭션에서 전체 데이터·계정을 다시 검증하고 부모 ready=true와 settings 포인터를 함께 create한다. 실패 시 비활성 자식을 자동 삭제하지 않는다. 기존 부모·포인터는 수정하지 않는다.
6. settings 전환 전에 기존 활성 사용자들의 staffId가 새 catalog에 모두 존재하는지 확인한다. settings의 현재 값이 사전 검토 이후 바뀌었으면 적용을 중단한다.
7. users, Authentication 계정, schedules, staffSchedules, commits에는 쓰지 않는다. 기존 포인터가 다른 버전이면 전환하지 않고 중단한다.
8. 결과는 문서 경로·개수·성공 여부만 출력한다. 비밀번호·토큰·키를 출력하지 않는다.

실제 프로젝트에서 도구를 실행하지 않았다. 로컬 오프라인 계획과 Emulator에서만 검증한다. 부모를 이미 ready=false 또는 잘못된 배열 필드와 함께 만들었다면 CLI는 자동 보정하지 않고 안내만 출력한다.
