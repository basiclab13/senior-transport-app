import 'package:flutter/material.dart';

import '../widgets/app_info_button.dart';
import '../utils/display_wording.dart';

import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});
  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.auth.busy || !_form.currentState!.validate()) return;
    final password = _password.text;
    _password.clear();
    await widget.auth.signIn(_email.text, password);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('송영도우미'),
      actions: const [AppInfoButton()],
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _form,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '로그인',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text('관리자가 등록한 계정으로 로그인해 주세요.'),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('email'),
                    controller: _email,
                    enabled: !widget.auth.busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '이메일'),
                    validator: (value) =>
                        value != null &&
                            RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                .hasMatch(value.trim())
                        ? null
                        : '올바른 이메일 주소를 입력해 주세요.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('password'),
                    controller: _password,
                    enabled: !widget.auth.busy,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: '비밀번호'),
                    onFieldSubmitted: (_) => _submit(),
                    validator: (value) => value == null || value.isEmpty
                        ? '비밀번호를 입력해 주세요.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  if (widget.auth.error != null)
                    Text(
                      displayMessage(widget.auth.error!),
                      semanticsLabel: displayMessage(widget.auth.error!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('login'),
                    onPressed: widget.auth.busy ? null : _submit,
                    child: widget.auth.busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              semanticsLabel: '로그인 중',
                            ),
                          )
                        : const Text('로그인'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
