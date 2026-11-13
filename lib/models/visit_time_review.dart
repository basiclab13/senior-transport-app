enum VisitTimeReviewDecision {
  pending('방문 시간 확인 필요'),
  kept('기존 시간 확인 완료'),
  applied('방문 시간 조정 완료');

  const VisitTimeReviewDecision(this.label);
  final String label;
}

/// Local draft workflow state. Never serialized as an authorization claim.
class VisitTimeReview {
  VisitTimeReview(this.decision, Iterable<String> reasons)
    : reasons = Set.unmodifiable(reasons);
  final VisitTimeReviewDecision decision;
  final Set<String> reasons;
}
