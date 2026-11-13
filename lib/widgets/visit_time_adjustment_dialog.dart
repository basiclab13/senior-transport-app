import 'package:flutter/material.dart';

import '../models/transport.dart';
import '../services/schedule_controller.dart';
import '../services/visit_time_calculator.dart';
import '../utils/schedule_wording.dart';

class VisitTimeBatchApplication {
  const VisitTimeBatchApplication(this.review, this.manualConfirmed);
  final VisitTimeBatchReview review;
  final bool manualConfirmed;
}

/// The existing fixed-interval calculator, reviewed once for all changed courses.
class VisitTimeAdjustmentDialog extends StatefulWidget {
  const VisitTimeAdjustmentDialog({super.key, required this.controller});
  final ScheduleController controller;
  @override
  State<VisitTimeAdjustmentDialog> createState() =>
      _VisitTimeAdjustmentDialogState();
}

class _VisitTimeAdjustmentDialogState extends State<VisitTimeAdjustmentDialog> {
  ScheduleController get c => widget.controller;
  late final snapshot = c.draft;
  late final catalog = c.catalog;
  late final revision = c.absenceRevisionKey;
  late final ids = Set<String>.of(c.pendingTimeReviewRouteIds);
  final firstFields = <String, TextEditingController>{};
  final interval = TextEditingController(
    text: '${FixedIntervalVisitTimeCalculator.defaultIntervalMinutes}',
  );
  VisitTimeBatchReview? review;
  String? error;
  bool get current =>
      !c.loading &&
      !c.busy &&
      !c.conflict &&
      c.dataError == null &&
      !c.availabilityLoading &&
      c.availabilityError == null &&
      identical(snapshot, c.draft) &&
      identical(catalog, c.catalog) &&
      revision == c.absenceRevisionKey;
  String courseName(String id) =>
      catalog.baseRoutes.firstWhere((r) => r.id == id).name;
  String passengerName(String id) =>
      catalog.passengers.firstWhere((p) => p.id == id).name;

  @override
  void initState() {
    super.initState();
    for (final r in snapshot.routes.where(
      (r) => ids.contains(r.baseRouteId) && r.passengerIds.isNotEmpty,
    )) {
      final times = r.estimatedVisitMinutes.values.toList()..sort();
      var minute = times.isEmpty ? r.startMinute : times.first;
      if (minute != null && r.startMinute != null && minute < r.startMinute!) {
        minute = r.startMinute;
      }
      firstFields[r.baseRouteId] = TextEditingController(
        text: minute == null ? '' : minuteLabel(minute),
      );
    }
    calculate();
  }

  int? parseMinute(String value) {
    if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value.trim())) {
      return null;
    }
    final parts = value.trim().split(':').map(int.parse).toList();
    return parts.first * 60 + parts.last;
  }

  void calculate() {
    review = null;
    error = null;
    if (!current) {
      error = '일정이 바뀌었습니다. 닫고 방문 시간을 다시 확인해 주세요.';
      return;
    }
    final gap = int.tryParse(interval.text.trim());
    if (gap == null || gap <= 0) {
      error = '방문 간격을 1분 이상으로 입력해 주세요.';
      return;
    }
    final first = <String, int>{};
    for (final entry in firstFields.entries) {
      final minute = parseMinute(entry.value.text);
      if (minute == null) {
        error = '${courseName(entry.key)}의 첫 방문 시간을 08:30처럼 입력해 주세요.';
        return;
      }
      first[entry.key] = minute;
    }
    try {
      review = c.prepareVisitTimeBatch(first, gap);
    } on StateError catch (e) {
      error = e.message;
    } on ArgumentError catch (e) {
      error = e.message as String;
    }
  }

  Future<void> apply() async {
    final result = review;
    if (result == null ||
        !c.isVisitTimeBatchCurrent(result) ||
        result.previews.any((p) => p.warnings.isNotEmpty)) {
      return;
    }
    var confirmed = false;
    if (result.manualChanges > 0) {
      confirmed =
          await showDialog<bool>(
            context: context,
            useRootNavigator: false,
            builder: (context) => AlertDialog(
              scrollable: true,
              title: const Text('직접 입력한 방문 시간도 바꿀까요?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '직접 입력한 시간 ${result.manualChanges}개가 아래와 같이 바뀝니다. 이전에 저장된 시간도 포함합니다.',
                  ),
                  for (final p in result.previews)
                    for (final id in p.manualChanges)
                      Text(
                        '${passengerName(id)}: ${minuteLabel(p.route.estimatedVisitMinutes[id])} → ${minuteLabel(p.result[id])}',
                      ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('바꾸지 않기'),
                ),
                FilledButton(
                  key: const Key('confirm-batch-manual-times'),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('확인하고 시간 바꾸기'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;
    }
    if (mounted) {
      Navigator.pop(context, VisitTimeBatchApplication(result, confirmed));
    }
  }

  @override
  void dispose() {
    for (final field in firstFields.values) {
      field.dispose();
    }
    interval.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final result = review;
      final ready =
          result != null &&
          current &&
          c.isVisitTimeBatchCurrent(result) &&
          result.previews.every((p) => p.warnings.isEmpty);
      return AlertDialog(
        title: const Text('방문 시간 한 번에 맞추기'),
        content: SizedBox(
          width: 620,
          height: 440,
          child: ListView(
            children: [
              Text(
                '${dateKey(snapshot.date)} · ${snapshot.period.label} · 바뀐 코스 ${ids.length}개',
              ),
              const Text(
                '현재 방문 순서에 맞춰 시간을 일정한 간격으로 정합니다. 실제 도착 시간과 다를 수 있습니다. 적용 후에도 최종 일정 확정은 따로 해야 합니다.',
              ),
              if (!current)
                const Text(
                  '일정이 바뀌었습니다. 닫고 다시 확인해 주세요.',
                  style: TextStyle(color: Colors.red),
                ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('batch-time-interval'),
                controller: interval,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '방문 사이 간격(분)'),
                onChanged: (_) => setState(() {
                  review = null;
                  error = null;
                }),
              ),
              for (final r in snapshot.routes.where(
                (r) => ids.contains(r.baseRouteId),
              ))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: r.passengerIds.isEmpty
                      ? Text(
                          '${courseName(r.baseRouteId)}: 방문할 이용자가 없어 시간 변경이 없습니다.',
                        )
                      : TextField(
                          key: ValueKey('batch-first-${r.baseRouteId}'),
                          controller: firstFields[r.baseRouteId],
                          decoration: InputDecoration(
                            labelText: '${courseName(r.baseRouteId)} 첫 방문 시간',
                            hintText: '08:30',
                          ),
                          keyboardType: TextInputType.datetime,
                          onChanged: (_) => setState(() {
                            review = null;
                            error = null;
                          }),
                        ),
                ),
              TextButton(
                key: const Key('calculate-batch-times'),
                onPressed: current ? () => setState(calculate) : null,
                child: const Text('바뀌는 시간 확인'),
              ),
              if (error != null)
                Text(
                  easyScheduleMessage(error!),
                  style: const TextStyle(color: Colors.red),
                ),
              if (result != null) ...[
                Text(
                  '방문 시간 ${result.changedTimes}개 변경 · 직접 입력한 시간 ${result.manualChanges}개 포함',
                ),
                ExpansionTile(
                  title: const Text('바뀌는 시간 자세히 보기'),
                  children: [
                    for (final p in result.previews)
                      for (final id in p.route.passengerIds.where(
                        (id) =>
                            p.route.estimatedVisitMinutes[id] != p.result[id],
                      ))
                        ListTile(
                          dense: true,
                          title: Text(passengerName(id)),
                          subtitle: Text(
                            '${minuteLabel(p.route.estimatedVisitMinutes[id])} → ${minuteLabel(p.result[id])}',
                          ),
                        ),
                  ],
                ),
                for (final p in result.previews)
                  for (final warning in p.warnings)
                    Text(
                      '${courseName(p.route.baseRouteId)}: ${easyScheduleMessage(warning)}',
                      style: const TextStyle(color: Colors.red),
                    ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('나중에 하기'),
          ),
          FilledButton(
            key: const Key('apply-batch-times'),
            onPressed: ready ? apply : null,
            child: const Text('이 시간으로 적용'),
          ),
        ],
      );
    },
  );
}
