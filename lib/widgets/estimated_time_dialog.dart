import 'package:flutter/material.dart';

import '../models/transport.dart';

class EstimatedTimeDialog extends StatefulWidget {
  const EstimatedTimeDialog({
    super.key,
    required this.title,
    required this.labels,
    required this.minutes,
    this.defaultMinute,
    this.guidance = '시계 버튼으로 시간을 고르거나 직접 입력하세요.',
  });
  final String title;
  final List<String> labels;
  final List<int?> minutes;
  final int? defaultMinute;
  final String guidance;

  @override
  State<EstimatedTimeDialog> createState() => _EstimatedTimeDialogState();
}

class _EstimatedTimeDialogState extends State<EstimatedTimeDialog> {
  final _form = GlobalKey<FormState>();
  late final _fields = [
    for (final minute in widget.minutes)
      TextEditingController(text: minute == null ? '' : minuteLabel(minute)),
  ];

  int? _parse(String text) {
    if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(text.trim())) {
      return null;
    }
    final parts = text.trim().split(':').map(int.parse).toList();
    return parts[0] * 60 + parts[1];
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.guidance),
              if (widget.defaultMinute != null && _fields.length == 1)
                TextButton(
                  onPressed: () =>
                      _fields.first.text = minuteLabel(widget.defaultMinute),
                  child: Text('기본 시간 ${minuteLabel(widget.defaultMinute)} 사용'),
                ),
              for (var i = 0; i < _fields.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextFormField(
                    key: ValueKey('estimated-time-$i'),
                    controller: _fields[i],
                    decoration: InputDecoration(
                      labelText: widget.labels[i],
                      hintText: '08:10',
                      suffixIcon: IconButton(
                        tooltip: '시간 선택',
                        icon: const Icon(Icons.schedule),
                        onPressed: () async {
                          final minute = _parse(_fields[i].text) ?? 540;
                          final value = await showTimePicker(
                            context: context,
                            cancelText: '취소',
                            confirmText: '선택',
                            helpText: '약속 시간 선택',
                            hourLabelText: '시',
                            minuteLabelText: '분',
                            initialTime: TimeOfDay(
                              hour: minute ~/ 60,
                              minute: minute % 60,
                            ),
                          );
                          if (value != null && mounted) {
                            _fields[i].text = minuteLabel(
                              value.hour * 60 + value.minute,
                            );
                          }
                        },
                      ),
                    ),
                    keyboardType: TextInputType.datetime,
                    validator: (text) {
                      if (_fields.every((field) => field.text.trim().isEmpty)) {
                        return null;
                      }
                      final minute = _parse(text ?? '');
                      if (minute == null) {
                        return '00:00~23:59 범위의 HH:mm 시각을 입력해 주세요.';
                      }
                      return null;
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        key: const Key('save-estimated-time'),
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, [
              for (final field in _fields) _parse(field.text),
            ]);
          }
        },
        child: const Text('저장'),
      ),
    ],
  );
}
