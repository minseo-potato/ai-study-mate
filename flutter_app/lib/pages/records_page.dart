import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';
import 'chat_room_page.dart';
import 'learning_journey_page.dart';

/// 스터디별로 다시 볼 내용과 주차별 정리를 모아 본다(요청 한 번).
class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});
  @override State<RecordsPage> createState() => _RecordsPageState();
}
class _RecordsPageState extends State<RecordsPage> {
  List<dynamic>? studies;
  List<dynamic> reviews = [], weeks = [];
  /// 펼쳐 둔 스터디. 처음에는 첫 스터디만 펼친다.
  final open = <int>{};
  @override void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    try {
      final data = await Api.request('GET', '/me/records');
      if (!mounted) return;
      setState(() {
        final first = studies == null;
        reviews = data['reviews'] as List; weeks = data['weeks'] as List;
        studies = (data['studies'] as List).where((s) =>
          reviews.any((r) => r['study_id'] == s['id']) || weeks.any((w) => w['study_id'] == s['id'])).toList();
        if (first && studies!.isNotEmpty) open.add(studies!.first['id'] as int);
      });
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<void> openReview(dynamic item) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatRoomPage(
      studyId: item['study_id'] as int, title: '${item['study_title']}', reviewId: item['id'] as int)));
    if (mounted) refresh();
  }
  Future<void> openWeek(dynamic w) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) =>
      LearningJourneyPage(studyId: w['study_id'] as int, weekNo: w['week_no'] as int)));
    if (mounted) refresh();
  }

  BoxDecoration get cardDecoration => BoxDecoration(color: Colors.white,
    borderRadius: BorderRadius.circular(18), border: Border.all(color: lineColor));
  Widget label(String text) => Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: mutedInk)));

  Widget weekRow(dynamic w) {
    final summary = '${w['summary']}'.trim();
    return InkWell(onTap: () => openWeek(w), child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(w['kind'] == 'presentation' ? '발표' : '${w['week_no']}주차', style: const TextStyle(fontSize: 12.5, color: brand, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Expanded(child: Text('${w['title']}', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            if (w['evaluated'] == true) const Text('발표 평가',
              style: TextStyle(fontSize: 12, color: brand, fontWeight: FontWeight.w600)),
          ]),
          if (summary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(summary, maxLines: 2,
            overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.5, fontSize: 13.5, color: subInk))),
          if ((w['keywords'] as List? ?? []).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8),
            child: KeywordChips((w['keywords'] as List).take(4).toList())),
        ])),
        const Icon(Icons.chevron_right_rounded, color: mutedInk),
      ])));
  }

  Widget studyCard(dynamic s) {
    final id = s['id'] as int;
    final ownReviews = reviews.where((r) => r['study_id'] == id).toList();
    final ownWeeks = weeks.where((w) => w['study_id'] == id).toList();
    final opened = open.contains(id);
    return Container(margin: const EdgeInsets.only(bottom: 12), decoration: cardDecoration, clipBehavior: Clip.antiAlias,
      child: Material(type: MaterialType.transparency, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(onTap: () => setState(() => opened ? open.remove(id) : open.add(id)), child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14), child: Row(children: [
            ProfileAvatar(roomAvatar(s as Map), size: 42, soft: true),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s['title']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${s['completed']}/${s['weeks']}주 완료${ownReviews.isEmpty ? '' : ', 다시 볼 내용 ${ownReviews.length}개'}',
                style: const TextStyle(fontSize: 12.5, color: mutedInk)),
            ])),
            Icon(opened ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: mutedInk),
          ]))),
        AnimatedSize(duration: const Duration(milliseconds: 200), curve: Curves.easeOut, alignment: Alignment.topCenter,
          child: !opened ? const SizedBox(width: double.infinity) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Divider(height: 1),
            if (ownReviews.isNotEmpty) ...[
              label('다시 볼 내용'),
              for (final r in ownReviews) ReviewRow(text: '${r['question']}', week: r['source_week'] as int, onTap: () => openReview(r)),
            ],
            if (ownReviews.isNotEmpty && ownWeeks.isNotEmpty) const Divider(height: 1),
            if (ownWeeks.isNotEmpty) ...[label('주차별 정리'), for (final w in ownWeeks) weekRow(w)],
            const SizedBox(height: 6),
          ])),
      ])));
  }

  @override Widget build(BuildContext context) {
    final items = studies;
    return ColoredBox(color: pageBg, child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: chatMaxWidth), child: Scaffold(
      appBar: AppBar(titleSpacing: 20, shape: const Border(),
        title: const Text('기록', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
      body: items == null ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: refresh,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
          if (items.isEmpty) const Padding(padding: EdgeInsets.only(top: 120),
            child: Center(child: Text('아직 기록이 없어요', style: TextStyle(color: mutedInk)))),
          for (final s in items) studyCard(s),
        ])),
    ))));
  }
}
