import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/schedule_repository.dart';
import 'login_screen.dart';
import 'schedule_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.auth, required this.schedules});
  final AuthService auth;
  final ScheduleRepository schedules;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: auth,
    builder: (context, _) {
      if (auth.initializing) {
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(semanticsLabel: '사용 권한 확인 중'),
          ),
        );
      }
      if (!auth.signedIn) return LoginScreen(auth: auth);
      final user = auth.user;
      if (user == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('계정 확인')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(auth.error ?? '사용 권한을 확인할 수 없습니다.'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: auth.busy ? null : auth.retry,
                    child: const Text('다시 확인'),
                  ),
                  TextButton(
                    onPressed: auth.busy ? null : auth.signOut,
                    child: const Text('로그아웃'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      // Discard protected routes AND open dialogs when identity/role changes.
      return Navigator(
        key: ValueKey('${user.uid}/${user.role.name}/${user.staffId}'),
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => ListenableBuilder(
            listenable: auth,
            builder: (context, _) => ScheduleScreen(
              user: user,
              repository: schedules,
              onSignOut: auth.signOut,
              signingOut: auth.busy,
              authError: auth.error,
            ),
          ),
        ),
      );
    },
  );
}
