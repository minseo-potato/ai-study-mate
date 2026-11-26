import 'dart:convert';
import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import 'avatar.dart';
import 'common.dart';

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
  /// 말풍선 아래 작은 표시(복습 완료 등).
  final String? note;
  /// 말풍선 위 작은 표시(다시 볼 내용 등).
  final String? lead;
  const ChatBubble({super.key, required this.name, required this.text, required this.mine,
    this.caption, this.onCaptionTap, this.member, this.grouped = false, this.note, this.lead});
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
                if (lead != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(lead!,
                  style: const TextStyle(fontSize: 12, color: brand, fontWeight: FontWeight.w700))),
                bubble,
                if (note != null) Padding(padding: const EdgeInsets.only(top: 4, left: 2), child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF12B886)), const SizedBox(width: 4),
                  Text(note!, style: const TextStyle(fontSize: 12, color: subInk, fontWeight: FontWeight.w600)),
                ])),
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
/// 대화 단계 이름: 'N주차 · 제목' 또는 '최종 발표'.
bool isPresentationStage(Map s) => s['kind'] == 'presentation';
String stageTitle(Map s) => isPresentationStage(s) ? '마무리 주 · 그동안 배운 것 정리하기' : '${s['week_no']}주차 · ${(s['week'] as Map)['title']}';
/// 진행 칸 수. 주차를 다 마친 뒤의 마무리 주도 한 칸으로 센다.
int stageCount(Map s) => s['stages'] as int? ?? s['total_weeks'] as int;
int stageDone(Map s) => isPresentationStage(s) ? stageCount(s) : s['week_no'] as int;

/// 주차를 모두 마친 뒤 이어지는 최종 발표 안내.
class PresentationNextLine extends StatelessWidget {
  const PresentationNextLine({super.key});
  @override Widget build(BuildContext context) => const Row(children: [
    Icon(Icons.arrow_forward_rounded, size: 16, color: brand), SizedBox(width: 8),
    Expanded(child: Text('마무리 주  그동안 배운 것 정리하기', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: ink))),
  ]);
}

class WeekDivider extends StatelessWidget {
  final Map<String, dynamic> session;
  const WeekDivider({super.key, required this.session});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 6),
    child: Center(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: const Color(0xFFE6E8EC), borderRadius: BorderRadius.circular(20)),
      child: Text(stageTitle(session),
        style: const TextStyle(fontSize: 12, color: Color(0xFF5B5F68), fontWeight: FontWeight.w600)))));
}

/// 주차를 마쳤을 때 채팅 안에 남는 정리 카드.
class StudySummaryCard extends StatelessWidget {
  final Map<String, dynamic> session;
  /// 방금 마쳤으면 부드럽게 나타난다.
  final bool fresh;
  const StudySummaryCard({super.key, required this.session, this.fresh = false});
  @override Widget build(BuildContext context) {
    final raw = session['minutes'] as String? ?? '';
    final minutes = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
    final checks = (minutes['next_checks'] as List?) ?? [];
    final keywords = (minutes['keywords'] as List?) ?? [];
    final learned = ((minutes['learned'] as List?) ?? []).take(2).toList();
    if ('${minutes['summary'] ?? ''}'.isEmpty) return const SizedBox.shrink();
    final card = Center(child: Container(margin: const EdgeInsets.only(top: 16), constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2))]),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(color: brandSoft, padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.check_circle_rounded, size: 18, color: brand), const SizedBox(width: 8),
            Expanded(child: Text(isPresentationStage(session) ? '마무리 주 정리' : '${session['week_no']}주차 정리',
              style: const TextStyle(fontWeight: FontWeight.w700, color: ink))),
            Text(isPresentationStage(session) ? '스터디 완료' : '${session['week_no']}/${session['total_weeks']}주',
              style: const TextStyle(fontSize: 12.5, color: brand, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          WeekDots(total: stageCount(session), done: stageDone(session)),
        ])),
        Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${minutes['summary'] ?? ''}', style: const TextStyle(height: 1.55, color: ink)),
          if (keywords.isNotEmpty) ...[const SizedBox(height: 10), KeywordChips(keywords)],
          if (learned.isNotEmpty) ...[const SizedBox(height: 14), NoteList(title: '내가 설명한 것', items: learned,
            icon: Icons.check_circle_rounded, color: const Color(0xFF12B886))],
          if (checks.isNotEmpty) ...[const SizedBox(height: 14), NoteList(title: '다음에 다시 볼 것', items: checks,
            icon: Icons.bookmark_rounded, color: brand)],
        ])),
        if (session['next_week'] is Map) Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: lineColor))),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), child: NextWeekLine(session['next_week'] as Map))
        else if (session['presentation_next'] == true) Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: lineColor))),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), child: const PresentationNextLine()),
      ])));
    return fresh ? RiseIn(child: card) : card;
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

/// 새로 올라온 카드를 한 번 부드럽게 펼친다.
class RiseIn extends StatelessWidget {
  final Widget child;
  const RiseIn({super.key, required this.child});
  @override Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context) ? child
    : TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic, child: child,
        builder: (context, t, child) => ClipRect(child: Align(alignment: Alignment.topCenter, heightFactor: t,
          child: Opacity(opacity: t, child: child))));
}

/// 주차 정리나 발표 평가를 만드는 동안 채팅에 보이는 자리.
class WorkingNote extends StatelessWidget {
  final String text;
  const WorkingNote(this.text, {super.key});
  @override Widget build(BuildContext context) => RiseIn(child: Center(child: Container(
    margin: const EdgeInsets.only(top: 18), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const TypingDots(), const SizedBox(width: 10),
      Text(text, style: const TextStyle(fontSize: 13, color: subInk, fontWeight: FontWeight.w600)),
    ]))));
}

/// 발표 평가 내용: 항목별 점수, 잘한 점, 고칠 점.
class EvaluationBody extends StatelessWidget {
  final Map data;
  final String? summary;
  const EvaluationBody(this.data, {super.key, this.summary});
  @override Widget build(BuildContext context) {
    final scores = (data['scores'] as List?) ?? [];
    final strengths = (data['strengths'] as List?) ?? [];
    final improvements = (data['improvements'] as List?) ?? [];
    final text = summary ?? '${data['summary'] ?? ''}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (text.isNotEmpty) Text(text, style: const TextStyle(height: 1.55, color: ink)),
      for (final s in scores) Padding(padding: const EdgeInsets.only(top: 14), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${s['label']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
            Text('${s['score']}/5', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: brand)),
          ]),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: (s['score'] as num) / 5, minHeight: 6,
            borderRadius: BorderRadius.circular(6), backgroundColor: brandSoft),
          if ('${s['reason'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text('${s['reason']}',
            style: const TextStyle(fontSize: 13, height: 1.45, color: subInk))),
        ])),
      if (strengths.isNotEmpty) ...[const SizedBox(height: 16), NoteList(title: '잘한 점', items: strengths,
        icon: Icons.check_circle_rounded, color: const Color(0xFF12B886))],
      if (improvements.isNotEmpty) ...[const SizedBox(height: 14), NoteList(title: '고치면 좋을 점', items: improvements,
        icon: Icons.flag_rounded, color: const Color(0xFFF59F00))],
    ]);
  }
}

class EvaluationCard extends StatelessWidget {
  final String summary;
  final Map data;
  const EvaluationCard({super.key, required this.summary, required this.data});
  @override Widget build(BuildContext context) => Center(child: Container(
    margin: const EdgeInsets.only(top: 16), constraints: const BoxConstraints(maxWidth: 520),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
      boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2))]),
    clipBehavior: Clip.antiAlias,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(color: brandSoft, padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: const Text('마무리 피드백', style: TextStyle(fontWeight: FontWeight.w700, color: ink))),
      Padding(padding: const EdgeInsets.all(16), child: EvaluationBody(data, summary: summary)),
    ])));
}

/// 끝낸 주와 남은 주를 보여 주는 칸.
class WeekDots extends StatelessWidget {
  final int total, done;
  const WeekDots({super.key, required this.total, required this.done});
  @override Widget build(BuildContext context) => Semantics(label: '전체 $total주 가운데 $done주 완료', child: Row(children: [
    for (var i = 0; i < total; i++) Expanded(child: Container(height: 6, margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(3),
        color: i < done ? brand : brand.withValues(alpha: 0.18)))),
  ]));
}

class NextWeekLine extends StatelessWidget {
  final Map week;
  const NextWeekLine(this.week, {super.key});
  @override Widget build(BuildContext context) => Row(children: [
    const Icon(Icons.arrow_forward_rounded, size: 16, color: brand), const SizedBox(width: 8),
    Expanded(child: Text('${week['week_no']}주차  ${week['title']}', maxLines: 1, overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: ink))),
    const SizedBox(width: 8),
    Text(friendlyDate('${week['meeting_date']}'), style: const TextStyle(fontSize: 12.5, color: mutedInk)),
  ]);
}

/// 채팅 입력창 위 오른쪽의 마치기 버튼. 다른 칩과 섞이지 않게 따로 둔다.
class FinishButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  const FinishButton({super.key, required this.label, required this.icon, this.onPressed});
  @override Widget build(BuildContext context) => TextButton.icon(onPressed: onPressed,
    style: TextButton.styleFrom(backgroundColor: onPressed == null ? Colors.white : brandSoft, foregroundColor: brand,
      elevation: 2, shadowColor: const Color(0x33000000),
      disabledForegroundColor: mutedInk, minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 14),
      textStyle: const TextStyle(fontFamily: 'NotoSansKR', fontSize: 13, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19))),
    icon: Icon(icon, size: 17), label: Text(label));
}

/// 주차를 마치기 전에 이번 주를 돌아보고 다음 주를 확인하는 창.
class FinishSheet extends StatelessWidget {
  final Map<String, dynamic> session;
  final int said, files, reviews;
  const FinishSheet({super.key, required this.session, required this.said, required this.files, required this.reviews});
  Widget stat(String label, int value) => Expanded(child: Column(children: [
    Text('$value', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontSize: 12, color: mutedInk)),
  ]));
  @override Widget build(BuildContext context) {
    final next = session['next_week'] as Map?;
    final weekNo = session['week_no'] as int;
    final toPresentation = session['presentation_next'] == true;
    return SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(next == null && !toPresentation ? '스터디를 마칠까요?' : '$weekNo주차를 마칠까요?',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
      const SizedBox(height: 4),
      Text(isPresentationStage(session) ? '그동안 배운 것 정리하기' : '${(session['week'] as Map)['title']}', maxLines: 2, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, color: subInk)),
      const SizedBox(height: 18),
      TweenAnimationBuilder<double>(tween: Tween(begin: MediaQuery.disableAnimationsOf(context) ? 1 : 0, end: 1),
        duration: const Duration(milliseconds: 500), curve: Curves.easeOut,
        builder: (context, t, _) => WeekDots(total: stageCount(session), done: t > 0.5 ? stageDone(session) : stageDone(session) - 1)),
      const SizedBox(height: 18),
      Container(padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: pageBg, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [stat('내가 한 말', said < 0 ? 0 : said), stat('올린 파일', files), stat('복습 표시', reviews)])),
      if (next != null) Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 0), child: NextWeekLine(next))
      else if (toPresentation) const Padding(padding: EdgeInsets.fromLTRB(4, 16, 4, 0), child: PresentationNextLine()),
      const SizedBox(height: 22),
      FilledButton(onPressed: () => Navigator.pop(context, true),
        child: Text(next != null ? '정리하고 ${next['week_no']}주차로' : toPresentation ? '정리하고 마무리 주로' : '스터디 마치기')),
      const SizedBox(height: 6),
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('더 이야기하기')),
    ]));
  }
}

/// 주차 정리가 만들어지는 동안, 곧 올라올 카드 모양으로 자리를 잡아 둔다.
class SummarySkeleton extends StatefulWidget {
  final String title;
  const SummarySkeleton({super.key, required this.title});
  @override State<SummarySkeleton> createState() => _SummarySkeletonState();
}
class _SummarySkeletonState extends State<SummarySkeleton> with SingleTickerProviderStateMixin {
  late final controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  @override void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) { controller.stop(); } else if (!controller.isAnimating) { controller.repeat(reverse: true); }
  }
  @override void dispose() { controller.dispose(); super.dispose(); }
  Widget bar(double width, double t) => FractionallySizedBox(widthFactor: width, alignment: Alignment.centerLeft,
    child: Container(height: 12, margin: const EdgeInsets.only(top: 10), decoration: BoxDecoration(
      color: Color.lerp(pageBg, brandSoft, t), borderRadius: BorderRadius.circular(6))));
  @override Widget build(BuildContext context) => RiseIn(child: Center(child: Container(
    margin: const EdgeInsets.only(top: 16), constraints: const BoxConstraints(maxWidth: 520),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), clipBehavior: Clip.antiAlias,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(color: brandSoft, padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: Row(children: [
        Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, color: ink))),
        const TypingDots(),
      ])),
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 18), child: AnimatedBuilder(animation: controller,
        builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          bar(0.95, controller.value), bar(0.88, controller.value), bar(0.6, controller.value),
          const SizedBox(height: 8), bar(0.4, controller.value), bar(0.7, controller.value),
        ]))),
    ]))));
}
