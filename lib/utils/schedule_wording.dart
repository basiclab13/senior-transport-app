import 'display_wording.dart';

/// Translate validation feedback for the screen; the validation rules stay intact.
String easyScheduleMessage(String message) =>
    displayMessage(_plainMessage(message));

String _plainMessage(String message) => message
    .replaceAll('기본 데이터 버전', '기본 정보')
    .replaceAll('확정 버전', '공유된 일정')
    .replaceAll(
      'AI 추천안이 업무 규칙을 충족하지 못했습니다.',
      'AI가 조건에 맞는 일정을 찾지 못했습니다. 결근 직원과 차량 정원을 확인하거나 직접 배정해 주세요.',
    )
    .replaceAll(
      'AI 추천안의 배정 검증에 실패했습니다.',
      '직원 근무 여부와 차량 정원을 확인한 뒤 다시 요청하거나 직접 배정해 주세요.',
    )
    .replaceAll(
      '직원이 같은 시간대에 중복 배정되었습니다.',
      '같은 시간에 여러 코스를 맡고 있습니다. 다른 직원에게 나눠 배정해 주세요.',
    )
    .replaceAll(
      '차량이 같은 시간대에 중복 배정되었습니다.',
      '같은 시간에 같은 차량을 쓰고 있습니다. 다른 차량을 선택해 주세요.',
    )
    .replaceAll(
      '이용자가 중복 배정되었습니다.',
      '같은 이용자가 여러 번 포함되어 있습니다. 한 코스에 한 번만 남겨 주세요.',
    )
    .replaceAll('예상 시각 출처:', '시간 입력 방식:')
    .replaceAll('수동', '직접 입력')
    .replaceAll('고정 간격', '일정한 간격')
    .replaceAll('초안', '변경 중인 일정')
    .replaceAll('재배정이 필요합니다.', '다른 직원에게 코스를 넘겨주세요.')
    .replaceAll('재배정 필요', '다른 직원 배정 필요')
    .replaceAll('검증 오류', '확인할 문제');
