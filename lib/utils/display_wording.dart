/// Presentation only. Never use these labels as identifiers or write them back.
String displayName(String name) => name.replaceFirst(RegExp(r'^가상\s+'), '');

String displayMessage(String message) {
  if (message.contains('승인된 관리자')) {
    return 'AI 추천을 사용할 권한이 없습니다. 관리자에게 문의해 주세요.';
  }
  if (message.contains('가상 기본 데이터')) {
    return '직원·차량 정보를 불러오지 못했습니다. 관리자에게 문의해 주세요.';
  }
  if (message.contains('서버 일정 검증')) {
    return '일정을 확정하지 못했습니다. 직원 근무 여부, 차량 정원, 중복 배정을 확인해 주세요.';
  }
  if (message.contains('서버 일정의 형식')) {
    return '일정을 불러오지 못했습니다. 관리자에게 확인을 요청해 주세요.';
  }
  if (message.contains('서버 API')) {
    return '추천을 받지 못했습니다. 연결을 확인하거나 관리자에게 문의해 주세요. 기존 일정은 유지됩니다.';
  }
  if (message.contains('형식 또는 추가 필드')) {
    return '저장된 일정과 맞지 않아 확정하지 못했습니다. 수정한 내용은 남아 있습니다. 관리자에게 확인을 요청해 주세요.';
  }
  if (message.contains('staffId')) {
    return '담당 직원 정보가 연결되지 않았습니다. 관리자에게 문의해 주세요.';
  }
  if (RegExp(r'users/|active:|active 필드|role은|boolean').hasMatch(message)) {
    return '계정 설정을 확인해야 합니다. 관리자에게 문의해 주세요.';
  }
  if (message.contains('Firestore') && message.contains('사용자')) {
    return '계정 정보를 확인하지 못했습니다. 관리자에게 권한 확인을 요청해 주세요.';
  }
  if (message.contains('결근 정보') || message.contains('결근 문서')) {
    if (RegExp(r'permission-denied|Rules|권한').hasMatch(message)) {
      return '결근 정보를 볼 수 없습니다. 관리자에게 계정 확인을 요청해 주세요. 확인 전에는 일정을 확정할 수 없습니다.';
    }
    if (RegExp(r'버전|형식|필드|연결 정보').hasMatch(message)) {
      return '결근 정보를 확인하지 못했습니다. 관리자에게 문의해 주세요. 확인 전에는 일정을 확정할 수 없습니다.';
    }
    if (RegExp(r'Firebase|캐시|디버그|서버').hasMatch(message)) {
      return '결근 정보를 확인하지 못했습니다. 연결을 확인하고 다시 불러와 주세요. 확인 전에는 일정을 확정할 수 없습니다.';
    }
  }
  if (RegExp(
    r'Firestore|Firebase|Security Rules|catalog|리비전|requestId|expectedVersion|schemaVersion',
  ).hasMatch(message)) {
    return '정보를 불러오지 못했습니다. 다시 시도하거나 관리자에게 문의해 주세요.';
  }
  return message
      .replaceAll(RegExp(r'가상\s+(?=직원|이용자|어르신|차량|\d)'), '')
      .replaceAll('직선거리', '거리 참고값')
      .replaceAll('추정', '참고')
      .replaceAll('출처', '입력 방식')
      .replaceAll('동기화', '새로 불러오기')
      .replaceAll('기본 데이터 버전', '기본 정보')
      .replaceAll('확정 버전', '공유된 일정')
      .replaceAll('버전', '변경 상태')
      .replaceAll('서버의', '저장된')
      .replaceAll('서버 데이터', '저장된 정보')
      .replaceAll('서버 원본', '저장된 일정')
      .replaceAll('서버 등록 시각', '등록 시각')
      .replaceAll('서버', '연결 상태')
      .replaceAll('API 설정', '사용 설정')
      .replaceAll('초안', '수정한 내용');
}
