import 'package:flutter/material.dart';

import '../models/schedule_catalog.dart';
import '../models/transport.dart';
import '../services/visit_time_calculator.dart';
import '../utils/schedule_wording.dart';

class VisitTimeApplication {
  const VisitTimeApplication(
    this.preview, {
    this.manualOverwriteConfirmed = false,
  });
  final VisitTimePreview preview;
  final bool manualOverwriteConfirmed;
}

class BulkVisitTimeDialog extends StatefulWidget {
  const BulkVisitTimeDialog({
    super.key,
    required this.catalog,
    required this.snapshot,
    required this.routeId,
  });
  final ScheduleCatalog catalog;
  final ScheduleSnapshot snapshot;
  final String routeId;
  @override
  State<BulkVisitTimeDialog> createState() => _BulkVisitTimeDialogState();
}

class _BulkVisitTimeDialogState extends State<BulkVisitTimeDialog> {
  final _form = GlobalKey<FormState>();
  late final route = widget.snapshot.routes.firstWhere(
    (r) => r.baseRouteId == widget.routeId,
  );
  late final _first = TextEditingController(
    text:
        route.passengerIds.isEmpty ||
            route.estimatedVisitMinutes[route.passengerIds.first] == null
        ? ''
        : minuteLabel(route.estimatedVisitMinutes[route.passengerIds.first]),
  );
  final _interval = TextEditingController(
    text: '${FixedIntervalVisitTimeCalculator.defaultIntervalMinutes}',
  );
  bool _replaceManual = false;
  VisitTimePreview? _preview;
  String? _error;
  int? _minute(String text) {
    if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(text.trim())) {
      return null;
    }
    final parts = text.trim().split(':').map(int.parse).toList();
    return parts[0] * 60 + parts[1];
  }

  String name(String id) =>
      widget.catalog.passengers.firstWhere((p) => p.id == id).name;
  void _changed() => setState(() {
    _preview = null;
    _error = null;
  });
  void _calculate() {
    if (!_form.currentState!.validate()) return;
    try {
      final preview = previewVisitTimes(
        widget.snapshot,
        route.baseRouteId,
        _minute(_first.text)!,
        int.parse(_interval.text.trim()),
        replaceManual: _replaceManual,
      );
      setState(() {
        _preview = preview;
        _error = null;
      });
    } on ArgumentError catch (error) {
      setState(() {
        _preview = null;
        _error = error.message as String;
      });
    }
  }

  Future<void> _apply() async {
    final preview = _preview;
    if (preview == null || preview.warnings.isNotEmpty) return;
    var confirmed = false;
    if (preview.manualChanges.isNotEmpty) {
      confirmed =
          await showDialog<bool>(
            context: context,
            useRootNavigator: false,
            builder: (context) => AlertDialog(
              scrollable: true,
              title: const Text('직접 입력한 방문 시간 변경 확인'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('이전에 저장된 시간도 직접 입력한 시간으로 보고 있습니다. 아래와 같이 바꿀까요?'),
                  for (final id in preview.manualChanges)
                    Text(
                      '${name(id)}: ${minuteLabel(route.estimatedVisitMinutes[id])} → ${minuteLabel(preview.result[id])}',
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('유지'),
                ),
                FilledButton(
                  key: const Key('confirm-manual-visit-overwrite'),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('직접 입력한 시간 ${preview.manualChanges.length}개 바꾸기'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;
    }
    if (mounted) {
      Navigator.pop(
        context,
        VisitTimeApplication(preview, manualOverwriteConfirmed: confirmed),
      );
    }
  }

  @override
  void dispose() {
    _first.dispose();
    _interval.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final oldWarnings = visitTimeWarnings(route, route.estimatedVisitMinutes);
    return AlertDialog(
      scrollable: true,
      title: const Text('방문 시간 맞추기'),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${dateKey(widget.snapshot.date)} · ${widget.snapshot.period.label} · ${widget.catalog.baseRoutes.firstWhere((r) => r.id == route.baseRouteId).name}',
              ),
              const Text(
                '방문 사이 간격으로 예상 시간을 정합니다. 실제 도착 시간과 다를 수 있습니다. 적용하기 전에는 일정이 바뀌지 않습니다.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 180,
                    child: TextFormField(
                      key: const Key('bulk-first-minute'),
                      controller: _first,
                      decoration: const InputDecoration(
                        labelText: '첫 방문 시간',
                        hintText: '08:30',
                      ),
                      keyboardType: TextInputType.datetime,
                      onChanged: (_) => _changed(),
                      validator: (v) => _minute(v ?? '') == null
                          ? 'HH:mm (00:00~23:59)'
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: TextFormField(
                      key: const Key('bulk-interval'),
                      controller: _interval,
                      decoration: const InputDecoration(
                        labelText: '방문 사이 간격(분)',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _changed(),
                      validator: (v) {
                        final value = int.tryParse((v ?? '').trim());
                        return value == null || value <= 0 ? '1분 이상의 정수' : null;
                      },
                    ),
                  ),
                ],
              ),
              CheckboxListTile(
                key: const Key('preview-manual-visit-overwrite'),
                contentPadding: EdgeInsets.zero,
                title: const Text('직접 입력한 시간도 함께 맞추기'),
                subtitle: const Text(
                  '직접 입력한 시간은 그대로 둡니다. 함께 바꾸려면 선택하세요. 적용 전에 다시 확인합니다.',
                ),
                value: _replaceManual,
                onChanged: (value) => setState(() {
                  _replaceManual = value ?? false;
                  _preview = null;
                  _error = null;
                }),
              ),
              for (final warning in oldWarnings)
                Text(
                  '확인할 내용: ${easyScheduleMessage(warning)}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              OutlinedButton(
                key: const Key('calculate-visit-preview'),
                onPressed: route.passengerIds.isEmpty ? null : _calculate,
                child: const Text('바뀌는 시간 확인'),
              ),
              if (route.passengerIds.isEmpty) const Text('방문 이용자가 없는 코스입니다.'),
              if (_error != null)
                Text(
                  easyScheduleMessage(_error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (preview != null) ...[
                const Divider(),
                Text(
                  '직접 입력한 시간 유지 ${preview.protectedIds.length}명 · 바뀌는 직접 입력 시간 ${preview.manualChanges.length}명',
                ),
                for (final id in route.passengerIds)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(name(id)),
                    subtitle: Text(
                      '현재 ${minuteLabel(route.estimatedVisitMinutes[id])} → 바뀔 시간 ${minuteLabel(preview.result[id])}${preview.protectedIds.contains(id) ? ' · 직접 입력한 시간 유지' : ''}',
                    ),
                  ),
                for (final warning in preview.warnings)
                  Text(
                    '확인할 내용: ${easyScheduleMessage(warning)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (preview.warnings.isNotEmpty)
                  const Text(
                    '첫 방문 시간을 앞당기거나 간격을 줄여 주세요. 직접 입력한 시간 때문에 맞지 않으면 「직접 입력한 시간도 함께 맞추기」를 선택하세요.',
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          key: const Key('apply-bulk-visit-times'),
          onPressed: preview != null && preview.warnings.isEmpty
              ? _apply
              : null,
          child: const Text('적용'),
        ),
      ],
    );
  }
}
