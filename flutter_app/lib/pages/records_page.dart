import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'learning_journey_page.dart';

/// 모든 스터디의 남은 복습과 주차별 정리를 한 화면에서 본다(요청 한 번).
class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});
  @override State<RecordsPage> createState() => _RecordsPageState();
}
class _RecordsPageState extends State<RecordsPage> {
  List<dynamic>? reviews;
  List<dynamic> weeks = [];
  int? filter; // 스터디 id로 거르기, null이면 전체
  @override void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    try {
      final data = await Api.request('GET', '/me/records');
      if (mounted) setState(() { reviews = data['reviews'] as List; weeks = data['weeks'] as List; });
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<void> resolve(dynamic item) async {
    setState(() => reviews!.remove(item));
    try {
      await Api.request('PUT', '/studies/${item['study_id']}/reviews/${item['id']}', {'resolved': true});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('복습을 마쳤어요'),
        action: SnackBarAction(label: '되돌리기', onPressed: () async {
          await Api.request('PUT', '/studies/${item['study_id']}/reviews/${item['id']}', {'resolved': false});
          refresh();
        })));
    } catch (e) { if (mounted) { errorMessage(context, e); refresh(); } }
  }

  BoxDecoration get cardDecoration => BoxDecoration(color: Colors.white,
    borderRadius: BorderRadius.circular(18), border: Border.all(color: lineColor));

  Widget studyTag(String title) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: pageBg, borderRadius: BorderRadius.circular(6)),
    child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 11.5, color: subInk, fontWeight: FontWeight.w600)));

  Widget empty(String text) => Container(padding: const EdgeInsets.symmetric(vertical: 24), decoration: cardDecoration,
    alignment: Alignment.center, child: Text(text, style: const TextStyle(color: mutedInk)));

  @override Widget build(BuildContext context) {
    final all = reviews;
    final studies = <int, String>{
      for (final r in [...?all, ...weeks]) r['study_id'] as int: '${r['study_title']}'};
    final shownReviews = (all ?? []).where((r) => filter == null || r['study_id'] == filter).toList();
    final shownWeeks = weeks.where((w) => filter == null || w['study_id'] == filter).toList();
    return ColoredBox(color: pageBg, child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: chatMaxWidth), child: Scaffold(
      appBar: AppBar(titleSpacing: 20, shape: const Border(),
        title: const Text('기록', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
      body: all == null ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: refresh,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
          if (studies.length > 1) SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final entry in [MapEntry<int?, String>(null, '전체'), ...studies.entries.map((e) => MapEntry<int?, String>(e.key, e.value))])
              Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
                label: Text(entry.value), selected: filter == entry.key, showCheckmark: false,
                labelStyle: TextStyle(fontFamily: 'NotoSansKR', fontSize: 13,
                  fontWeight: filter == entry.key ? FontWeight.w700 : FontWeight.w500,
                  color: filter == entry.key ? brand : subInk),
                side: BorderSide(color: filter == entry.key ? brand : const Color(0xFFE1E3E8)),
                onSelected: (_) => setState(() => filter = entry.key))),
          ])),
          SectionTitle('다시 볼 내용', detail: shownReviews.isEmpty ? null : '${shownReviews.length}개'),
          if (shownReviews.isEmpty) empty('남은 복습이 없어요')
          else Container(decoration: cardDecoration, clipBehavior: Clip.antiAlias, child: Column(children: [
            for (var i = 0; i < shownReviews.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 50),
              InkWell(onTap: () => resolve(shownReviews[i]), child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.radio_button_unchecked_rounded, size: 22, color: Color(0xFFC5C8CE)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${shownReviews[i]['question']}', style: const TextStyle(height: 1.45, fontSize: 14.5)),
                    const SizedBox(height: 5),
                    Row(children: [
                      if (filter == null) ...[Flexible(child: studyTag('${shownReviews[i]['study_title']}')), const SizedBox(width: 6)],
                      Text('${shownReviews[i]['source_week']}주차', style: const TextStyle(fontSize: 12, color: mutedInk)),
                    ]),
                  ])),
                ]))),
            ],
          ])),
          const SectionTitle('주차별 정리'),
          if (shownWeeks.isEmpty) empty('주차를 마치면 여기에 모여요')
          else ...shownWeeks.map((w) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Material(
            color: Colors.white, borderRadius: BorderRadius.circular(18), child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => LearningJourneyPage(studyId: w['study_id'] as int))).then((_) => refresh()),
              child: Container(padding: const EdgeInsets.all(16), decoration: cardDecoration,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('${w['week_no']}주차', style: const TextStyle(fontSize: 12.5, color: brand, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${w['title']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                    if (filter == null) ConstrainedBox(constraints: const BoxConstraints(maxWidth: 140),
                      child: studyTag('${w['study_title']}')),
                  ]),
                  if ('${w['summary']}'.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8),
                    child: Text('${w['summary']}', maxLines: 3, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(height: 1.5, color: subInk))),
                ])))))),
        ])),
    ))));
  }
}
