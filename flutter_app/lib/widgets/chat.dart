import 'dart:convert';
import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import 'avatar.dart';

/// AI 스터디원 프로필(아이콘·색은 직접 바꿀 수 있고, 기본값은 역할별 모양).
class PeerAvatar extends StatelessWidget {
  final Map member;
  final double size;
  const PeerAvatar(this.member, {super.key, this.size = 36});
  @override Widget build(BuildContext context) => ProfileAvatar(memberAvatar(member), size: size);
}

/// 내 프로필.
class MyAvatar extends StatelessWidget {
  final double size;
  const MyAvatar({super.key, this.size = 36});
  @override Widget build(BuildContext context) => ProfileAvatar(userAvatar(Api.account?['user'] as Map?), size: size);
}

class ChatBubble extends StatelessWidget {
  final String name;
  final String text;
  final bool mine;
  final String? caption;
  final VoidCallback? onCaptionTap;
  final Map? member;
  /// 같은 사람이 이어서 말하면 이름과 프로필을 한 번만 보여준다.
  final bool grouped;
  const ChatBubble({super.key, required this.name, required this.text, required this.mine,
    this.caption, this.onCaptionTap, this.member, this.grouped = false});
  @override Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(!mine && !grouped ? 4 : 18), topRight: Radius.circular(mine && !grouped ? 4 : 18),
      bottomLeft: const Radius.circular(18), bottomRight: const Radius.circular(18));
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: mine ? brand : Colors.white, borderRadius: radius,
        boxShadow: mine ? null : const [BoxShadow(color: Color(0x0F000000), blurRadius: 3, offset: Offset(0, 1))]),
      child: SelectableText(text, style: TextStyle(color: mine ? Colors.white : ink, height: 1.5, fontSize: 15)));
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width < 600 ? width * 0.84 : 560),
        child: Padding(padding: EdgeInsets.only(top: grouped ? 3 : 12), child: Row(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!mine) ...[
              grouped || member == null ? const SizedBox(width: 36) : PeerAvatar(member!),
              const SizedBox(width: 8),
            ],
            Flexible(child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!mine && !grouped) Padding(padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
                  child: Text(name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF3A3D44)))),
                bubble,
                if (caption != null) Padding(padding: const EdgeInsets.only(top: 4), child: InkWell(
                  onTap: onCaptionTap, borderRadius: BorderRadius.circular(12),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: brandSoft, borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.menu_book_outlined, size: 14, color: brand), const SizedBox(width: 4),
                      Text(caption!, style: const TextStyle(fontSize: 12, color: brand, fontWeight: FontWeight.w600)),
                    ])))),
              ])),
          ]))));
  }
}

class TypingDots extends StatefulWidget {
  const TypingDots({super.key});
  @override State<TypingDots> createState() => _TypingDotsState();
}
class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  @override void dispose() { controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: controller, builder: (context, child) =>
    Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
      final t = ((controller.value * 3) - i).clamp(0.0, 1.0);
      final lift = t < 0.5 ? t * 2 : (1 - t) * 2;
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Transform.translate(
        offset: Offset(0, -3 * lift), child: Container(width: 7, height: 7, decoration: BoxDecoration(
          shape: BoxShape.circle, color: Color.lerp(const Color(0xFFC4C7CE), mutedInk, lift)))));
    })));
}


/// 채팅 안에서 주차가 바뀌는 지점을 알려주는 알약 모양 구분선.
class WeekDivider extends StatelessWidget {
  final Map<String, dynamic> session;
  const WeekDivider({super.key, required this.session});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 6),
    child: Center(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: const Color(0xFFE6E8EC), borderRadius: BorderRadius.circular(20)),
      child: Text('${session['week_no']}주차 · ${(session['week'] as Map)['title']}',
        style: const TextStyle(fontSize: 12, color: Color(0xFF5B5F68), fontWeight: FontWeight.w600)))));
}

/// 주차를 마쳤을 때 채팅 안에 남는 정리 카드.
class StudySummaryCard extends StatelessWidget {
  final Map<String, dynamic> session;
  const StudySummaryCard({super.key, required this.session});
  @override Widget build(BuildContext context) {
    final raw = session['minutes'] as String? ?? '';
    final minutes = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
    final checks = (minutes['next_checks'] as List?) ?? [];
    return Center(child: Container(margin: const EdgeInsets.only(top: 16), constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2))]),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(color: brandSoft, padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), child: Row(children: [
          const Icon(Icons.auto_awesome_rounded, size: 18, color: brand), const SizedBox(width: 8),
          Text('${session['week_no']}주차 스터디 정리', style: const TextStyle(fontWeight: FontWeight.w700, color: ink)),
        ])),
        Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${minutes['summary'] ?? ''}', style: const TextStyle(height: 1.55, color: ink)),
          if (checks.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('다음에 다시 볼 것', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: mutedInk)),
            ...checks.map((x) => Padding(padding: const EdgeInsets.only(top: 6), child: Row(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 3), child: Icon(Icons.bookmark_rounded, size: 14, color: brand)),
                const SizedBox(width: 6),
                Expanded(child: Text('$x', style: const TextStyle(height: 1.45, fontSize: 13.5))),
              ]))),
          ],
        ])),
      ])));
  }
}

/// 스터디원이 답을 쓰는 중일 때 보이는 말풍선.
class TypingBubble extends StatelessWidget {
  final Map? member;
  const TypingBubble({super.key, this.member});
  @override Widget build(BuildContext context) => Align(alignment: Alignment.centerLeft, child: Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (member != null) PeerAvatar(member!) else const SizedBox(width: 36),
      const SizedBox(width: 8),
      Container(padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(18)),
          boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 3, offset: Offset(0, 1))]),
        child: const TypingDots()),
    ])));
}

/// 상단 바에 겹쳐 보이는 스터디원 프로필.
class MemberStack extends StatelessWidget {
  final List members;
  const MemberStack({super.key, required this.members});
  @override Widget build(BuildContext context) {
    final shown = members.take(3).toList();
    return SizedBox(width: 22.0 * shown.length + 14, height: 36, child: Stack(children: [
      for (var i = 0; i < shown.length; i++) Positioned(left: 22.0 * i, top: 0, child: Container(
        padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: PeerAvatar(shown[i] as Map, size: 32))),
    ]));
  }
}

/// 채팅방 정보 패널의 소제목과 내용 묶음.
class InfoSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const InfoSection({super.key, required this.title, required this.children});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: mutedInk)),
      const SizedBox(height: 10),
      ...children,
    ]));
}
