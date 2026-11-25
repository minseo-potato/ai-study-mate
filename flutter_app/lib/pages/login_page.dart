import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 이름과 비밀번호만으로 로그인·가입한다.
class LoginPage extends StatefulWidget {
  final void Function(Map<String, dynamic> account) onSignedIn;
  const LoginPage({super.key, required this.onSignedIn});
  @override State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final name = TextEditingController(), password = TextEditingController();
  final passwordFocus = FocusNode();
  bool signup = false, busy = false, hidden = true;
  @override void dispose() { name.dispose(); password.dispose(); passwordFocus.dispose(); super.dispose(); }

  bool get valid => name.text.trim().length >= 2 && password.text.length >= (signup ? 8 : 4);

  Future<void> submit() async {
    if (!valid || busy) return;
    setState(() => busy = true);
    try {
      final data = await Api.request('POST', signup ? '/auth/signup' : '/auth/login',
        {'name': name.text.trim(), 'password': password.text}) as Map<String, dynamic>;
      await Api.saveToken(data['token'] as String);
      widget.onSignedIn(data);
    } catch (e) { if (mounted) errorMessage(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 380), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(alignment: Alignment.centerLeft, child: Container(width: 64, height: 64, alignment: Alignment.center,
            decoration: BoxDecoration(color: brand, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.forum_rounded, color: Colors.white, size: 32))),
          const SizedBox(height: 20),
          const Text('AI 스터디메이트', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: ink)),
          const SizedBox(height: 6),
          Text(signup ? '이름과 비밀번호만 정하면 바로 시작해요' : 'AI 친구들과 함께 공부해요',
            style: const TextStyle(fontSize: 15, color: subInk)),
          const SizedBox(height: 32),
          TextField(controller: name, autofocus: true, maxLength: 20, textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}), onSubmitted: (_) => passwordFocus.requestFocus(),
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(hintText: '이름 (2자 이상)', counterText: '',
              prefixIcon: Icon(Icons.person_outline_rounded))),
          const SizedBox(height: 10),
          TextField(controller: password, focusNode: passwordFocus, obscureText: hidden, maxLength: 64,
            onChanged: (_) => setState(() {}), onSubmitted: (_) => submit(),
            autofillHints: [signup ? AutofillHints.newPassword : AutofillHints.password],
            decoration: InputDecoration(hintText: signup ? '비밀번호 (8자 이상)' : '비밀번호', counterText: '',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(tooltip: hidden ? '비밀번호 보기' : '비밀번호 숨기기',
                icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                onPressed: () => setState(() => hidden = !hidden)))),
          const SizedBox(height: 20),
          FilledButton(onPressed: valid && !busy ? submit : null,
            child: Text(busy ? '잠시만요...' : signup ? '가입하고 시작하기' : '로그인')),
          const SizedBox(height: 8),
          TextButton(onPressed: busy ? null : () => setState(() => signup = !signup),
            child: Text(signup ? '이미 계정이 있어요' : '처음이에요 · 가입하기')),
        ]))))),
  );
}
