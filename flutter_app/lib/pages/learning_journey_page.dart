import 'package:flutter/material.dart';
import '../api.dart';
import '../widgets/common.dart';

class LearningJourneyPage extends StatefulWidget {
  final int studyId;
  const LearningJourneyPage({super.key, required this.studyId});
  @override State<LearningJourneyPage> createState() => _LearningJourneyPageState();
}
class _LearningJourneyPageState extends State<LearningJourneyPage> {
  Map<String, dynamic>? report;
  List<dynamic> reviews = [];
  bool busy = false;
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
  Widget stat(int value, String label, IconData icon) => Expanded(child: SoftPanel(
    child: Column(children: [Icon(icon, color: const Color(0xFF7C5CFC), size: 20),
      const SizedBox(height: 6), Text('$value', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF8B8F97))),
    ])));
  Widget noteBlock(String label, String value, Color color) => Container(
    width: double.infinity, padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 7), Text(value.trim().isEmpty ? '작성한 내용이 없어요.' : value,
        style: const TextStyle(height: 1.5)),
    ]));
  @override Widget build(BuildContext context) {
    final data = report;
    final open = reviews.where((r) => r['status'] == 'open').toList();
    final done = reviews.where((r) => r['status'] == 'done').toList();
    final weeks = (data?['weeks'] as List?) ?? [];
    return Scaffold(appBar: AppBar(title: const Text('학습 성장 기록')),
      body: data == null ? const Center(child: CircularProgressIndicator()) : PageContent(children: [
        SoftPanel(color: const Color(0xFFF6F4FF), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${data['title']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5), Text('${data['goal']}'),
        ])),
        Row(children: [
          stat(data['completed_weeks'] as int, '완료한 주차', Icons.calendar_today_outlined),
          stat(data['answer_count'] as int, '답한 횟수', Icons.chat_bubble_outline),
          stat(data['open_reviews'] as int, '남은 복습', Icons.bookmark_outline),
        ]),
        SectionTitle('다시 볼 내용', detail: '${open.length}개 남음'),
        if (open.isEmpty) const SoftPanel(child: Text('지금 남아 있는 복습 항목이 없어요.')),
        ...open.map((item) => Card(child: CheckboxListTile(
          value: false, onChanged: busy ? null : (_) => setResolved(item, true),
          title: Text('${item['question']}'),
          subtitle: Text('${item['source_week']}주차'),
          controlAffinity: ListTileControlAffinity.leading))),
        if (done.isNotEmpty) ExpansionTile(title: Text('완료한 복습 ${done.length}개'),
          children: done.map((item) => CheckboxListTile(
            value: true, onChanged: busy ? null : (_) => setResolved(item, false),
            title: Text('${item['question']}'),
            controlAffinity: ListTileControlAffinity.leading)).toList()),
        const SectionTitle('주차별 설명의 변화'),
        if (weeks.every((w) => w['status'] != 'complete'))
          const SoftPanel(child: Text('아직 완료한 주차가 없어요.')),
        ...weeks.where((w) => w['status'] == 'complete').map((week) => Card(
          child: Padding(padding: const EdgeInsets.all(18), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${week['week_no']}주차 · ${week['title']}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text('질문 ${week['question_count']}개 · 답변 ${week['answer_count']}개',
              style: const TextStyle(color: Color(0xFF8B8F97), fontSize: 12)),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, constraints) => constraints.maxWidth >= 460
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: noteBlock('${week['baseline_label']}', '${week['baseline_text']}', const Color(0xFFF6F7F9))),
                  const SizedBox(width: 10),
                  Expanded(child: noteBlock('대화 뒤 다시 정리', '${week['revised_note']}', const Color(0xFFEFFAF5))),
                ])
              : Column(children: [
                  noteBlock('${week['baseline_label']}', '${week['baseline_text']}', const Color(0xFFF6F7F9)),
                  const SizedBox(height: 10),
                  noteBlock('대화 뒤 다시 정리', '${week['revised_note']}', const Color(0xFFEFFAF5)),
                ])),
            if ('${week['summary']}'.isNotEmpty) ...[
              const SizedBox(height: 14), Text('스터디 기록 · ${week['summary']}',
                style: const TextStyle(height: 1.5)),
            ],
          ])))),
      ]));
  }
}
