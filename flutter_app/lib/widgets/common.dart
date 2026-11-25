import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme.dart';

class PageContent extends StatelessWidget {
  final List<Widget> children;
  final bool buildAll;
  const PageContent({super.key, required this.children, this.buildAll = false});
  @override Widget build(BuildContext context) => Center(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 640),
    child: buildAll ? SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))
      : ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 100), children: children)));
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? detail;
  const SectionTitle(this.title, {super.key, this.detail});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 28, 4, 10), child: Row(children: [
      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
      if (detail != null) ...[const Spacer(), Text(detail!, style: const TextStyle(fontSize: 13, color: mutedInk))],
    ]));
}

void errorMessage(BuildContext context, Object e) {
  final message = e is http.ClientException
    ? '서버에 연결할 수 없습니다. 서버가 실행 중인지 확인해 주세요.'
    : e.toString().replaceFirst(RegExp(r'^Exception: '), '');
  showNotice(context, message);
}

/// 하단 알림. 앞 알림을 바로 치우고 짧게 보여 준다(되돌리기 같은 버튼이 있으면 조금 더).
void showNotice(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action, persist: false,
      duration: Duration(milliseconds: action == null ? 1800 : 3000)));
}

/// 휴대폰에서는 아래에서 올라오는 시트, 넓은 화면에서는 가운데 대화상자로 연다.
Future<T?> showAdaptiveSheet<T>(BuildContext context, WidgetBuilder builder) {
  final wide = MediaQuery.sizeOf(context).width >= 700;
  if (wide) {
    return showDialog<T>(context: context, builder: (dialogContext) => Dialog(
      backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 560,
        maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.8),
        child: Padding(padding: const EdgeInsets.all(24), child: builder(dialogContext)))));
  }
  return showModalBottomSheet<T>(context: context, isScrollControlled: true, showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 24),
      child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75),
        child: builder(sheetContext))));
}

/// 기초·중급·심화 중 하나를 고르는 알약 모양 선택기.
class LevelPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final bool compact;
  const LevelPicker({super.key, required this.value, required this.onChanged, this.compact = false});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(color: pageBg, borderRadius: BorderRadius.circular(12)),
    child: Row(mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max, children: [
      for (final level in peerLevels) _segment(level),
    ]));
  Widget _segment(String level) {
    final selected = level == value;
    final child = GestureDetector(
      onTap: () => onChanged(level),
      child: AnimatedContainer(duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 0, vertical: compact ? 6 : 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: selected ? const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))] : null),
        child: Text(level, style: TextStyle(fontSize: compact ? 12.5 : 14,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? ink : mutedInk))));
    return compact ? child : Expanded(child: child);
  }
}

/// 다시 볼 내용 한 줄. 누르면 채팅에서 이어서 답한다.
class ReviewRow extends StatelessWidget {
  final String text;
  final int week;
  final VoidCallback? onTap;
  final bool done;
  const ReviewRow({super.key, required this.text, required this.week, this.onTap, this.done = false});
  @override Widget build(BuildContext context) => InkWell(onTap: onTap, child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 12, 10), child: Row(children: [
      Icon(done ? Icons.check_circle_rounded : Icons.chat_bubble_outline_rounded, size: 20, color: done ? brand : mutedInk),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text, style: TextStyle(height: 1.45, fontSize: 14.5, color: done ? mutedInk : ink)),
        const SizedBox(height: 3),
        Text('$week주차', style: const TextStyle(fontSize: 12, color: mutedInk)),
      ])),
      if (!done) const Icon(Icons.chevron_right_rounded, color: mutedInk),
    ])));
}

/// 기록에 쓰는 핵심 개념 칩 줄.
class KeywordChips extends StatelessWidget {
  final List items;
  const KeywordChips(this.items, {super.key});
  @override Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
    for (final k in items) Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: brandSoft, borderRadius: BorderRadius.circular(20)),
      child: Text('#$k', style: const TextStyle(fontSize: 12.5, color: brand, fontWeight: FontWeight.w600))),
  ]);
}

/// 아이콘이 붙은 짧은 목록(내가 설명한 것, 더 다질 것 등).
class NoteList extends StatelessWidget {
  final String title;
  final List items;
  final IconData icon;
  final Color color;
  const NoteList({super.key, required this.title, required this.items, required this.icon, required this.color});
  @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: mutedInk)),
    for (final x in items) Padding(padding: const EdgeInsets.only(top: 6), child: Row(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 3), child: Icon(icon, size: 14, color: color)),
        const SizedBox(width: 6),
        Expanded(child: Text('$x', style: const TextStyle(height: 1.45, fontSize: 13.5, color: ink))),
      ])),
  ]);
}
