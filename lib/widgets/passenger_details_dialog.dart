import 'package:flutter/material.dart';

import '../models/transport.dart';

class PassengerDetailsDialog extends StatefulWidget {
  const PassengerDetailsDialog({super.key, required this.passenger});
  final Passenger passenger;
  @override
  State<PassengerDetailsDialog> createState() => _PassengerDetailsDialogState();
}

class _PassengerDetailsDialogState extends State<PassengerDetailsDialog> {
  late int? minute = widget.passenger.defaultMorningMinute;
  late final note = TextEditingController(text: widget.passenger.note);
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.passenger.name} · 기본 정보'),
    scrollable: true,
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('기본 오전 약속 시간 · 이후 미확정 일정에 사용합니다. 이미 확정한 일정은 바뀌지 않습니다.'),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const Key('default-appointment-picker'),
                icon: const Icon(Icons.schedule),
                label: Text(minuteLabel(minute)),
                onPressed: () async {
                  final value = await showTimePicker(
                    context: context,
                    cancelText: '취소',
                    confirmText: '선택',
                    helpText: '약속 시간 선택',
                    hourLabelText: '시',
                    minuteLabelText: '분',
                    initialTime: TimeOfDay(
                      hour: (minute ?? 540) ~/ 60,
                      minute: (minute ?? 540) % 60,
                    ),
                  );
                  if (value != null && mounted) {
                    setState(() => minute = value.hour * 60 + value.minute);
                  }
                },
              ),
              TextButton(
                onPressed: () => setState(() => minute = null),
                child: const Text('기본 시간 지우기'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('passenger-note-input'),
            controller: note,
            minLines: 3,
            maxLines: 7,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: '특이사항',
              hintText: '필요한 안내를 적어 주세요. 비우고 저장하면 삭제됩니다.',
              border: OutlineInputBorder(),
            ),
          ),
          const Text('담당 직원이 일정을 다시 조회하면 특이사항을 확인할 수 있습니다.'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        key: const Key('save-passenger-details'),
        onPressed: () =>
            Navigator.pop(context, (note: note.text, minute: minute)),
        child: const Text('기본 정보 저장'),
      ),
    ],
  );
}
