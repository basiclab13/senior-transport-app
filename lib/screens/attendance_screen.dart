import 'package:flutter/material.dart';

import '../models/transport.dart';

class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({
    super.key,
    required this.staffName,
    required this.date,
    required this.period,
  });
  final String staffName;
  final DateTime date;
  final TransportPeriod period;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('출퇴근 사진 인증 안내')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.camera_alt_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              '사진 인증 기능 준비 중',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text('$staffName · ${dateKey(date)} · ${period.label}'),
            const SizedBox(height: 12),
            const Text(
              '사진 촬영·업로드 및 출퇴근 기록 저장은 아직 제공되지 않습니다. 이 화면에서는 출퇴근 인증이 기록되지 않습니다.',
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('내 일정으로 돌아가기'),
            ),
          ],
        ),
      ),
    ),
  );
}
