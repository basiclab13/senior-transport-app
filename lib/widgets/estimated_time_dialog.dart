import 'package:flutter/material.dart';

import '../models/transport.dart';

class EstimatedTimeDialog extends StatefulWidget {
  const EstimatedTimeDialog({
    super.key,
    required this.title,
    required this.labels,
    required this.minutes,
  });
  final String title;
  final List<String> labels;
  final List<int?> minutes;

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
              const Text(
                '관리자 입력 예상 시각입니다. HH:mm 형식으로 입력하세요. 모두 비우면 미입력으로 변경됩니다.',
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
                      if (i == 1 &&
                          _parse(_fields[0].text) != null &&
                          minute <= _parse(_fields[0].text)!) {
                        return '종료 시각은 출발 시각보다 늦어야 합니다.';
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
        child: const Text('적용'),
      ),
    ],
  );
}
