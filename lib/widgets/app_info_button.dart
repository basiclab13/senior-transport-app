import 'package:flutter/material.dart';

class AppInfoButton extends StatelessWidget {
  const AppInfoButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('app-info'),
    tooltip: '앱 안내',
    icon: const Icon(Icons.info_outline),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('송영도우미 안내'),
        scrollable: true,
        content: const Text(
          '송영 일정과 업무 사진을 확인하는 앱입니다.\n\n'
          '시연용 데이터\n실제 개인정보가 아닌 시연용 이름과 일정을 사용합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    ),
  );
}
