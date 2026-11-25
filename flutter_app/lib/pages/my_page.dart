import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';

/// 마이페이지: 내 프로필과 학습 숫자, 앱 상태, 로그아웃.
class MyPage extends StatelessWidget {
  final Map<String, dynamic> account;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final Future<void> Function() onSignOut;
  const MyPage({super.key, required this.account, required this.onChanged, required this.onSignOut});

  Map get user => account['user'] as Map;
  Map get stats => account['stats'] as Map;

  Future<void> rename(BuildContext context) async {
    final edit = await showProfileEditor(context, title: '내 프로필', name: '${user['name']}',
      avatar: userAvatar(user), nameMin: 2);
    if (edit == null) return;
    try {
      onChanged(await Api.request('PUT', '/me', {
        if (edit.name != user['name']) 'name': edit.name, 'avatar': edit.avatar.code}) as Map<String, dynamic>);
    } catch (e) { if (context.mounted) errorMessage(context, e); }
  }

  Future<void> confirmSignOut(BuildContext context) async {
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('로그아웃할까요?'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('로그아웃'))],
    ));
    if (ok == true) await onSignOut();
  }

  Widget stat(String label, Object value) => Expanded(child: Column(children: [
    Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: ink)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontSize: 12, color: mutedInk)),
  ]));

  @override Widget build(BuildContext context) {
    final name = '${user['name']}';
    final joined = DateTime.tryParse('${user['created_at']}');
    final card = BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: lineColor));
    final divider = Container(width: 1, height: 32, color: lineColor);
    return ColoredBox(color: pageBg, child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: chatMaxWidth), child: Scaffold(
      appBar: AppBar(titleSpacing: 20, shape: const Border(),
        title: const Text('마이', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        Container(padding: const EdgeInsets.all(18), decoration: card, child: Row(children: [
          GestureDetector(onTap: () => rename(context), child: ProfileAvatar(userAvatar(user), size: 56)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (joined != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(
              '${joined.year}년 ${joined.month}월 ${joined.day}일 가입', style: const TextStyle(fontSize: 12.5, color: mutedInk))),
          ])),
          IconButton(tooltip: '프로필 바꾸기', onPressed: () => rename(context), icon: const Icon(Icons.edit_outlined, color: mutedInk)),
        ])),
        const SizedBox(height: 10),
        Container(padding: const EdgeInsets.symmetric(vertical: 18), decoration: card, child: Row(children: [
          stat('스터디', stats['studies'] ?? 0), divider,
          stat('완료한 주차', stats['completed_weeks'] ?? 0), divider,
          stat('내 답변', stats['answers'] ?? 0), divider,
          stat('남은 복습', stats['open_reviews'] ?? 0),
        ])),
        const SectionTitle('설정'),
        Container(decoration: card, clipBehavior: Clip.antiAlias, child: Column(children: [
          ListTile(leading: const Icon(Icons.logout_rounded, color: Color(0xFFE03131)),
            title: const Text('로그아웃', style: TextStyle(fontSize: 15, color: Color(0xFFE03131))),
            onTap: () => confirmSignOut(context)),
        ])),
      ]),
    ))));
  }
}
