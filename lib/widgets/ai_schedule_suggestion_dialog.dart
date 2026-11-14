import 'package:flutter/material.dart';

import '../models/ai_schedule_suggestion.dart';
import '../models/schedule_changes.dart';
import '../services/schedule_controller.dart';
import '../utils/schedule_wording.dart';
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
      final date =
          '${suggestion.origin.date.year}년 ${suggestion.origin.date.month}월 ${suggestion.origin.date.day}일 · ${suggestion.origin.period.label}';
      const stale = '일정 또는 결근 상태가 바뀌었습니다. 닫고 다시 추천받아 주세요.';
      if (diff.items.isEmpty) {
        return AlertDialog(
          key: const Key('ai-unchanged-dialog'),
          title: const Text('추천 일정 확인'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(date),
              const SizedBox(height: 12),
              Text(current ? '현재 일정 그대로 사용해도 됩니다' : stale),
            ],
          ),
          actions: [
            TextButton(
              key: const Key('close-ai-suggestion'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('확인'),
            ),
          ],
        );
      }
      final before = {
        for (final r in suggestion.origin.routes)
          for (final id in r.passengerIds) id: r.baseRouteId,
      };
      final moved = suggestion.candidate.routes.fold(
        0,
        (count, r) =>
            count +
            r.passengerIds.where((id) => before[id] != r.baseRouteId).length,
      );
      final staff = diff.items
          .where((i) => i.kind == ScheduleChangeKind.staff)
          .length;
      final order = diff.items
          .where((i) => i.kind == ScheduleChangeKind.order)
          .length;
      return AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        actionsPadding: const EdgeInsets.all(12),
        title: const Text('추천 일정 확인'),
        content: SizedBox(
          width: 700,
          height:
              (220 + changedCourseIds(diff, suggestion.candidate).length * 72)
                  .clamp(300, 480)
                  .toDouble(),
          child: ListView(
            children: [
              Text(date),
              if (!current)
                const Text(stale, style: TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              Text(
                '바뀌는 코스 ${changedCourseIds(diff, suggestion.candidate).length}개',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (staff > 0) Text('담당 직원 변경 $staff코스'),
                  if (moved > 0) Text('이용자 이동 $moved명'),
                  if (order > 0) Text('방문 순서 변경 $order코스'),
                ],
              ),
              CourseChangeDetails(
                catalog: suggestion.catalog,
                before: suggestion.origin,
                after: suggestion.candidate,
                changes: diff,
                showVisitTimes: false,
                afterLabel: '추천 순서',
              ),
              if (suggestion.needsAppointmentNotice)
                const Text('약속 시간 조정이 필요할 수 있으니 확인해 주세요.'),
              const Text('직원에게 공유하려면 적용 후 일정을 확정해 주세요.'),
              ExpansionTile(
                key: const Key('ai-more-details'),
                title: const Text('자세히 보기'),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (suggestion.distanceComparison case final distance?) ...[
                    Text(
                      '거리 참고값 · ${distance.beforeKm.toStringAsFixed(3)} → ${distance.afterKm.toStringAsFixed(3)} km',
                      key: const Key('ai-distance-comparison'),
                    ),
                    Text(
                      easyScheduleMessage(distance.summary),
                      key: const Key('ai-distance-change'),
                    ),
                  ] else
                    const Text('거리 비교 정보가 없습니다.'),
                  const Text(
                    '지도나 도로를 반영하지 않은 계산입니다. 실제 이동 거리·운행 시간의 절감 효과가 아닙니다.',
                    key: Key('ai-distance-limit'),
                  ),
                  for (final reason in suggestion.reasons)
                    Text(easyScheduleMessage(reason)),
                  const Text('입력한 약속 시간은 바뀌지 않습니다.'),
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
            onPressed: current ? () => Navigator.pop(context, true) : null,
            child: const Text('이 일정 사용하기'),
          ),
        ],
      );
    },
  );
}
