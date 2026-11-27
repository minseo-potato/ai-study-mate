import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'learning_journey_page.dart';

/// 전체 계획·일정. 주차를 누르면 제목·범위·모임 날짜를 바로 고칠 수 있다.
class StudyPage extends StatefulWidget {
  final int id;
  const StudyPage({super.key, required this.id});
  @override State<StudyPage> createState() => _StudyPageState();
}
class _StudyPageState extends State<StudyPage> {
  Map<String, dynamic>? study;
  bool busy = false;
  @override void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    try {
      final data = await Api.request('GET', '/studies/${widget.id}');
      if (mounted) setState(() => study = data);
    } catch (e) { if (mounted) errorMessage(context, e); }
  }

  /// 남은 주차 계획을 AI에게 다시 받아 확인 후 적용한다.
  Future<void> redraft() async {
    final weeks = study!['weeks'] as List;
    final replan = weeks.any((w) => w['status'] == 'complete');
    setState(() => busy = true);
    try {
      final result = await Api.request('POST', '/studies/${widget.id}/${replan ? 'replan-draft' : 'plan-draft'}');
      if (!mounted) return;
      final drafts = result['weeks'] as List<dynamic>;
      final approved = await showAdaptiveSheet<bool>(context, (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('새 계획안', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Flexible(child: ListView(shrinkWrap: true, children: [
            for (final w in drafts) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 48, child: Text('${w['week_no']}주차',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: brand))),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${w['title']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if ('${w['scope']}' != '${w['title']}')
                    Text('${w['scope']}', style: const TextStyle(fontSize: 13, color: subInk)),
                ])),
              ])),
          ])),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheetContext, false), child: const Text('그대로 두기'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(onPressed: () => Navigator.pop(sheetContext, true), child: const Text('적용'))),
          ]),
        ]));
      if (approved != true) return;
      // 여러 주차를 요청 한 번으로 바꾼다.
      final data = await Api.request('PUT', '/studies/${widget.id}/weeks', {'weeks': [
        for (final item in drafts) {'week_no': item['week_no'], 'title': item['title'], 'scope': item['scope']}]});
      if (mounted) setState(() => study = data);
    } catch (e) { if (mounted) errorMessage(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> editWeek(Map week) async {
    final title = TextEditingController(text: '${week['title']}');
    final scope = TextEditingController(text: '${week['scope']}');
    var date = DateTime.parse('${week['meeting_date']}');
    var includePrevious = week['include_previous_questions'] != 0;
    final complete = week['status'] == 'complete';
    final saved = await showAdaptiveSheet<bool>(context, (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheet) => Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${week['week_no']}주차 계획', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(controller: title, maxLength: 120, decoration: const InputDecoration(labelText: '주제', counterText: '')),
          const SizedBox(height: 12),
          TextField(controller: scope, maxLength: 300, minLines: 1, maxLines: 3,
            decoration: const InputDecoration(labelText: '공부할 범위', hintText: '예: 교안 1~8쪽, 역전파 원리', counterText: '')),
          const SizedBox(height: 12),
          Material(color: Colors.white, borderRadius: BorderRadius.circular(14), child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final picked = await showDatePicker(context: sheetContext, initialDate: date,
                firstDate: DateTime(date.year - 1), lastDate: DateTime(date.year + 2));
              if (picked != null) setSheet(() => date = picked);
            },
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE1E3E8))),
              child: Row(children: [
                const Icon(Icons.event_outlined, color: mutedInk), const SizedBox(width: 12),
                const Text('시작 날짜', style: TextStyle(color: subInk)), const Spacer(),
                Text(friendlyDate(date.toIso8601String().substring(0, 10)), style: const TextStyle(fontWeight: FontWeight.w600)),
              ])))),
          if (week['week_no'] > 1 && !complete) SwitchListTile(contentPadding: const EdgeInsets.only(left: 4),
            title: const Text('지난 주차 내용도 질문받기', style: TextStyle(fontSize: 14)),
            value: includePrevious, onChanged: (v) => setSheet(() => includePrevious = v)),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(sheetContext, true), child: const Text('저장')),
        ])));
    final payload = {
      'title': title.text.trim(), 'scope': scope.text.trim().isEmpty ? title.text.trim() : scope.text.trim(),
      'meeting_date': date.toIso8601String().substring(0, 10), 'status': week['status'],
      'include_previous_questions': includePrevious,
    };
    title.dispose(); scope.dispose();
    if (saved != true || !mounted) return;
    if ((payload['title'] as String).isEmpty) { errorMessage(context, '주제를 입력해 주세요.'); return; }
    try {
      final data = await Api.request('PUT', '/studies/${widget.id}/weeks/${week['week_no']}', payload);
      if (mounted) setState(() => study = data);
    } catch (e) { if (mounted) errorMessage(context, e); }
  }

  Widget weekRow(Map w, bool current) {
    final complete = w['status'] == 'complete';
    final showScope = '${w['scope']}'.trim() != '${w['title']}'.trim();
    return Material(color: Colors.white, borderRadius: BorderRadius.circular(16), child: InkWell(
      onTap: () => editWeek(w), borderRadius: BorderRadius.circular(16),
      child: Container(padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16),
          border: Border.all(color: current ? brand.withValues(alpha: 0.45) : lineColor)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 30, height: 30, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: complete ? brand : current ? brandSoft : pageBg),
            child: complete ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
              : Text('${w['week_no']}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                  color: current ? brand : mutedInk))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${w['title']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
            if (showScope) Padding(padding: const EdgeInsets.only(top: 3),
              child: Text('${w['scope']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: subInk, height: 1.4))),
            const SizedBox(height: 6),
            // 주차 날짜는 그 주차로 넘어간 날이라, 아직 시작하지 않은 주차는 날짜 없이 둔다.
            Text(complete || current ? '${friendlyDate('${w['meeting_date']}')}${current ? ' · 진행 중' : ' · 완료'}' : '예정',
              style: TextStyle(fontSize: 12, color: current ? brand : mutedInk,
                fontWeight: current ? FontWeight.w600 : FontWeight.w400)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: mutedInk),
        ]))));
  }

  @override Widget build(BuildContext context) {
    final weeks = (study?['weeks'] as List?) ?? [];
    final completed = weeks.where((w) => w['status'] == 'complete').length;
    final current = weeks.cast<Map?>().firstWhere((w) => w?['status'] != 'complete', orElse: () => null);
    return Scaffold(
      appBar: AppBar(title: const Text('계획·일정')),
      body: study == null ? const Center(child: CircularProgressIndicator()) : PageContent(children: [
        Container(padding: const EdgeInsets.all(18), margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: lineColor)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$completed', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: brand, height: 1)),
              Text(' / ${weeks.length}주 완료', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: subInk)),
            ]),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: weeks.isEmpty ? 0 : completed / weeks.length, minHeight: 8,
              borderRadius: BorderRadius.circular(8), backgroundColor: brandSoft),
            if (current != null) ...[
              const SizedBox(height: 14),
              Row(children: [
                const Icon(Icons.event_outlined, size: 16, color: mutedInk), const SizedBox(width: 6),
                Text('${current['week_no']}주차 시작 ${friendlyDate('${current['meeting_date']}')}',
                  style: const TextStyle(fontSize: 13, color: subInk)),
              ]),
            ],
          ])),
        const SizedBox(height: 10),
        Material(color: Colors.white, borderRadius: BorderRadius.circular(16), child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => LearningJourneyPage(studyId: widget.id))).then((_) => refresh()),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: lineColor)),
            child: const Row(children: [
              Icon(Icons.insights_rounded, color: brand), SizedBox(width: 12),
              Expanded(child: Text('복습·성장 기록', style: TextStyle(fontWeight: FontWeight.w600))),
              Icon(Icons.chevron_right_rounded, color: mutedInk),
            ])))),
        Padding(padding: const EdgeInsets.fromLTRB(4, 24, 0, 8), child: Row(children: [
          const Expanded(child: Text('주차별 계획', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink))),
          TextButton.icon(onPressed: busy ? null : redraft,
            icon: busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('AI로 다시 짜기')),
        ])),
        for (final w in weeks) Padding(padding: const EdgeInsets.only(bottom: 8),
          child: weekRow(w as Map, identical(w, current))),
      ]));
  }
}
