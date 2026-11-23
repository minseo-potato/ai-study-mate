import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 복습·성장 기록: 숫자 요약, 다시 볼 내용 체크, 주차별 정리.
class LearningJourneyPage extends StatefulWidget {
  final int studyId;
  const LearningJourneyPage({super.key, required this.studyId});
  @override State<LearningJourneyPage> createState() => _LearningJourneyPageState();
}
class _LearningJourneyPageState extends State<LearningJourneyPage> {
  Map<String, dynamic>? report;
  List<dynamic> reviews = [];
  bool busy = false, showDone = false;
  /// 문답을 펼쳐 본 주차 번호들.
  final openQa = <int>{};
  @override void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    try {
      final results = await Future.wait([
        Api.request('GET', '/studies/${widget.studyId}/learning-report'),
        Api.request('GET', '/studies/${widget.studyId}/reviews'),
      ]);
      if (mounted) setState(() { report = results[0] as Map<String, dynamic>; reviews = results[1] as List<dynamic>; });
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<void> setResolved(dynamic item, bool resolved) async {
    setState(() => busy = true);
    try {
      await Api.request('PUT', '/studies/${widget.studyId}/reviews/${item['id']}', {'resolved': resolved});
      await refresh();
    } catch (e) { if (mounted) errorMessage(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }

  BoxDecoration get cardDecoration => BoxDecoration(color: Colors.white,
    borderRadius: BorderRadius.circular(18), border: Border.all(color: lineColor));

  Widget stat(int value, String label) => Expanded(child: Column(children: [
    Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: ink)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontSize: 12, color: mutedInk)),
  ]));

  Widget reviewRow(dynamic item, bool done) => InkWell(
    onTap: busy ? null : () => setResolved(item, !done),
    child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 16, 12), child: Row(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 22, color: done ? brand : const Color(0xFFC5C8CE)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${item['question']}', style: TextStyle(height: 1.45, fontSize: 14.5,
            color: done ? mutedInk : ink, decoration: done ? TextDecoration.lineThrough : null)),
          const SizedBox(height: 3),
          Text('${item['source_week']}주차', style: const TextStyle(fontSize: 12, color: mutedInk)),
        ])),
      ])));

  Widget note(String label, String value, Color color) => Container(
    width: double.infinity, padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(top: 10),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: subInk)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(height: 1.5, fontSize: 14)),
    ]));

  Widget weekCard(Map week) {
    final summary = '${week['summary'] ?? ''}'.trim();
    final baseline = '${week['baseline_text'] ?? ''}'.trim();
    final revised = '${week['revised_note'] ?? ''}'.trim();
    final keywords = (week['keywords'] as List?) ?? [];
    final learned = (week['learned'] as List?) ?? [];
    final gaps = (week['gaps'] as List?) ?? [];
    final highlight = '${week['highlight'] ?? ''}'.trim();
    final qa = ((week['qa'] as List?) ?? []).where((p) => '${p['question']}'.isNotEmpty).toList();
    final weekNo = week['week_no'] as int;
    final hints = week['hint_count'] ?? 0;
    final richRecord = learned.isNotEmpty || gaps.isNotEmpty || highlight.isNotEmpty;
    return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16), decoration: cardDecoration,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: brandSoft, borderRadius: BorderRadius.circular(8)),
            child: Text('${week['week_no']}주차', style: const TextStyle(fontSize: 12, color: brand, fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          Expanded(child: Text('${week['title']}', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          Text('질문 ${week['question_count']} · 답변 ${week['answer_count']}${hints > 0 ? ' · 힌트 $hints' : ''}',
            style: const TextStyle(fontSize: 12, color: mutedInk)),
        ]),
        if (summary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10),
          child: Text(summary, style: const TextStyle(height: 1.55, color: ink))),
        if (keywords.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: KeywordChips(keywords)),
        if (highlight.isNotEmpty) Container(
          width: double.infinity, margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(color: pageBg, borderRadius: BorderRadius.circular(12),
            border: const Border(left: BorderSide(color: brand, width: 3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('가장 잘 설명한 말', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: subInk)),
            const SizedBox(height: 4),
            Text('“$highlight”', style: const TextStyle(height: 1.5, fontSize: 14, color: ink)),
          ])),
        if (learned.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: NoteList(
          title: '내가 설명한 것', items: learned, icon: Icons.check_circle_rounded, color: const Color(0xFF12B886))),
        if (gaps.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: NoteList(
          title: '더 다질 것', items: gaps, icon: Icons.flag_rounded, color: const Color(0xFFF59F00))),
        // 예전 기록처럼 정리 항목이 없을 때만 처음·마지막 메모를 보여 준다.
        if (!richRecord && baseline.isNotEmpty) note('${week['baseline_label']}', baseline, pageBg),
        if (revised.isNotEmpty) note('마치며 다시 정리', revised, const Color(0xFFEFFAF5)),
        if (qa.isNotEmpty) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() => openQa.contains(weekNo) ? openQa.remove(weekNo) : openQa.add(weekNo)),
            style: TextButton.styleFrom(foregroundColor: subInk, padding: EdgeInsets.zero),
            icon: Icon(openQa.contains(weekNo) ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
            label: Text('문답 다시 보기 ${qa.length}', style: const TextStyle(fontSize: 13))),
          if (openQa.contains(weekNo)) for (final p in qa) Container(
            width: double.infinity, margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: pageBg, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Q. ${p['question']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.45)),
              const SizedBox(height: 6),
              Text('${p['answer']}'.trim().isEmpty ? '답하지 않고 넘어갔어요' : 'A. ${p['answer']}',
                style: TextStyle(fontSize: 13.5, height: 1.45,
                  color: '${p['answer']}'.trim().isEmpty ? mutedInk : ink)),
              if (p['hint'] == true) const Padding(padding: EdgeInsets.only(top: 4),
                child: Text('힌트를 받았어요', style: TextStyle(fontSize: 12, color: Color(0xFFF59F00)))),
            ])),
        ],
      ]));
  }

  Widget empty(String text) => Container(padding: const EdgeInsets.symmetric(vertical: 22), decoration: cardDecoration,
    alignment: Alignment.center, child: Text(text, style: const TextStyle(color: mutedInk)));

  @override Widget build(BuildContext context) {
    final data = report;
    final open = reviews.where((r) => r['status'] == 'open').toList();
    final done = reviews.where((r) => r['status'] == 'done').toList();
    final weeks = ((data?['weeks'] as List?) ?? []).where((w) => w['status'] == 'complete').toList();
    return Scaffold(appBar: AppBar(title: const Text('복습·성장 기록')),
      body: data == null ? const Center(child: CircularProgressIndicator()) : PageContent(children: [
        Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: cardDecoration, child: Row(children: [
            stat(data['completed_weeks'] as int, '완료한 주차'),
            Container(width: 1, height: 32, color: lineColor),
            stat(data['answer_count'] as int, '내 답변'),
            Container(width: 1, height: 32, color: lineColor),
            stat(data['open_reviews'] as int, '남은 복습'),
          ])),
        SectionTitle('다시 볼 내용', detail: open.isEmpty ? null : '${open.length}개'),
        if (open.isEmpty) empty('남은 복습이 없어요')
        else Container(decoration: cardDecoration, clipBehavior: Clip.antiAlias, child: Column(children: [
          for (var i = 0; i < open.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 48),
            reviewRow(open[i], false),
          ],
        ])),
        if (done.isNotEmpty) ...[
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(
            onPressed: () => setState(() => showDone = !showDone),
            icon: Icon(showDone ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
            label: Text('완료한 복습 ${done.length}개', style: const TextStyle(fontSize: 13)),
            style: TextButton.styleFrom(foregroundColor: mutedInk))),
          if (showDone) Container(decoration: cardDecoration, clipBehavior: Clip.antiAlias, child: Column(children: [
            for (var i = 0; i < done.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 48),
              reviewRow(done[i], true),
            ],
          ])),
        ],
        const SectionTitle('주차별 기록'),
        if (weeks.isEmpty) empty('주차를 마치면 여기에 정리돼요')
        else ...weeks.map((w) => weekCard(w as Map)),
      ]));
  }
}
