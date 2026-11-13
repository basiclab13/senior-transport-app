import 'package:flutter/material.dart';

import '../models/ai_schedule_suggestion.dart';
import '../models/schedule_changes.dart';
import '../services/schedule_controller.dart';
import '../services/visit_time_calculator.dart';
import 'course_change_details.dart';

class AiScheduleSuggestionDialog extends StatelessWidget {
  const AiScheduleSuggestionDialog({
    super.key,
    required this.controller,
    required this.suggestion,
  });
  final ScheduleController controller;
  final AiScheduleSuggestion suggestion;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final current = controller.isSuggestionCurrent(suggestion);
      final diff = ScheduleChanges.compare(
        suggestion.origin,
        suggestion.candidate,
        suggestion.catalog,
      );
      final timeWarnings = [
        for (final r in suggestion.candidate.routes)
          ...visitTimeWarnings(r, r.estimatedVisitMinutes),
      ];
      return AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        actionsPadding: const EdgeInsets.all(12),
        title: const Text('AI 일정 제안 검토'),
        content: SizedBox(
          width: 700,
          height: 480,
          child: ListView(
            children: [
              Text(
                '${suggestion.origin.date.year}년 ${suggestion.origin.date.month}월 ${suggestion.origin.date.day}일 · ${suggestion.origin.period.label}',
              ),
              if (!current)
                const Text(
                  '일정 또는 결근 상태가 변경되었습니다. 닫고 다시 요청해 주세요.',
                  style: TextStyle(color: Colors.red),
                ),
              const SizedBox(height: 12),
              if (suggestion.distanceComparison case final distance?) ...[
                Text(
                  '가상 직선거리 비교 · ${distance.beforeKm.toStringAsFixed(3)} → ${distance.afterKm.toStringAsFixed(3)} km',
                  key: const Key('ai-distance-comparison'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  distance.summary,
                  key: const Key('ai-distance-change'),
                  style: TextStyle(
                    color: distance.worsened ? Colors.deepOrange : null,
                  ),
                ),
              ] else
                const Text('가상 좌표가 준비되지 않아 추정 거리 비교를 제공하지 않습니다.'),
              const Text(
                '가상 좌표의 직선거리 추정치입니다. 실제 도로 거리나 운행 시간 절감 수치가 아닙니다.',
                key: Key('ai-distance-limit'),
              ),
              const Divider(),
              Text(
                diff.items.isEmpty
                    ? '현재 일정과 변경사항이 없습니다.'
                    : '바뀌는 코스 ${changedCourseIds(diff, suggestion.candidate).length}개 · 변경 ${diff.items.length}항목',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              CourseChangeDetails(
                catalog: suggestion.catalog,
                before: suggestion.origin,
                after: suggestion.candidate,
                changes: diff,
                expand: true,
                showVisitTimes: false,
                afterLabel: '추천 순서',
              ),
              if (diff.items.isNotEmpty)
                const Text('선택 후 방문 시간을 확인합니다. 최종 일정 확정은 따로 진행합니다.'),
              ExpansionTile(
                key: const Key('ai-more-details'),
                title: const Text('자세히 보기'),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '계산 방법: 가상 평면 좌표에서 센터 출발·복귀를 포함한 직선거리 합을 비교합니다. 실제 도로·교통은 반영하지 않습니다.',
                  ),
                  const Text('계산으로 확인한 추천 설명'),
                  for (final reason in suggestion.reasons) Text(reason),
                  const Text(
                    '추천안은 아직 직원에게 전달되지 않았습니다. 기존 방문 시각과 입력 방식은 자동으로 바뀌지 않습니다.',
                  ),
                  if (timeWarnings.isNotEmpty || suggestion.warnings.isNotEmpty)
                    const Text('방문 순서가 바뀌어 시간을 다시 맞춰야 합니다. 다음 화면에서 확인해 주세요.'),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const Key('approve-ai-suggestion'),
            onPressed: current && diff.items.isNotEmpty
                ? () => Navigator.pop(context, true)
                : null,
            child: const Text('이 일정 사용하기'),
          ),
        ],
      );
    },
  );
}
