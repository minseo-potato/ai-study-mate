import 'package:flutter/material.dart';
import '../api.dart';
import '../widgets/common.dart';
import 'learning_journey_page.dart';
import 'week_page.dart';
import 'session_page.dart';

class StudyPage extends StatefulWidget {
  final int id;
  const StudyPage({super.key, required this.id});
  @override State<StudyPage> createState() => _StudyPageState();
}
class _StudyPageState extends State<StudyPage> {
  Map<String, dynamic>? study;
  List<dynamic> minutes = [];
  bool busy = false;
  int selectedWeek = 1;
  @override void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    try {
      final data = await Api.request('GET', '/studies/${widget.id}');
      final records = await Api.request('GET', '/studies/${widget.id}/minutes');
      if (mounted) {
        setState(() {
          if (study == null) {
            final weeks = data['weeks'] as List;
            selectedWeek = (weeks.firstWhere((w) => w['status'] != 'complete', orElse: () => weeks.first))['week_no'];
          }
          study = data; minutes = records;
        });
      }
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<void> draft([bool replan = false]) async {
    setState(() => busy = true);
    try {
      final result = await Api.request('POST', '/studies/${widget.id}/${replan ? 'replan-draft' : 'plan-draft'}');
      if (!mounted) return;
      final drafts = result['weeks'] as List<dynamic>;
      final approved = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: Text(replan ? '남은 일정 변경안 확인' : 'AI 계획 확인'),
        content: SizedBox(width: 500, child: ListView(shrinkWrap: true, children: drafts.map((w) =>
          ListTile(title: Text('${w['week_no']}주차 · ${w['title']}'), subtitle: Text(w['scope']))).toList())),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('적용'))],
      ));
      if (approved != true) return;
      for (final item in drafts) {
        final old = (study!['weeks'] as List).firstWhere((w) => w['week_no'] == item['week_no']);
        await Api.request('PUT', '/studies/${widget.id}/weeks/${item['week_no']}', {
          'title': item['title'], 'scope': item['scope'], 'meeting_date': old['meeting_date'], 'status': old['status']});
      }
      await refresh();
    } catch (e) { if (mounted) errorMessage(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) {
    final weeks = (study?['weeks'] as List?) ?? [];
    final current = weeks.isEmpty ? null : weeks.firstWhere((w) => w['week_no'] == selectedWeek,
      orElse: () => weeks.first);
    final completed = weeks.where((w) => w['status'] == 'complete').length;
    return Scaffold(appBar: AppBar(title: Text(study?['title'] ?? '스터디')),
      body: study == null ? const Center(child: CircularProgressIndicator()) : PageContent(children: [
        SoftPanel(color: const Color(0xFFF6F4FF), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(study!['goal'], style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text((study!['pdf_name'] as String).isEmpty ? '교안 없이 내 방식대로 공부해요' : '함께 볼 교안 · ${study!['pdf_name']}',
            style: const TextStyle(color: Color(0xFF8B8F97))),
          const SizedBox(height: 16),
          Text('$completed / ${weeks.length}주 완료', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          LinearProgressIndicator(value: completed / weeks.length, minHeight: 8,
            borderRadius: BorderRadius.circular(8), backgroundColor: const Color(0xFFE6E0FF)),
        ])),
        Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          leading: const CircleAvatar(backgroundColor: Color(0xFFF1EDFF),
            child: Icon(Icons.insights_rounded, color: Color(0xFF7C5CFC))),
          title: const Text('학습 성장 기록', style: TextStyle(fontWeight: FontWeight.w700)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => LearningJourneyPage(studyId: widget.id))).then((_) => refresh()))),
        const SectionTitle('주간 학습'),
        SizedBox(height: 64, child: ListView(scrollDirection: Axis.horizontal, children: weeks.map((w) {
          final selected = w['week_no'] == selectedWeek;
          return Padding(padding: const EdgeInsets.only(right: 8), child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => selectedWeek = w['week_no']),
            child: Container(width: 92, padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(color: selected ? const Color(0xFF7C5CFC) : const Color(0xFFF1EDFF),
                borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                Text('${w['week_no']}주차', style: TextStyle(fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : const Color(0xFF191A1C))),
                const SizedBox(height: 3),
                Text(weekStatusLabel(w['status']), style: TextStyle(fontSize: 11,
                  color: selected ? Colors.white70 : const Color(0xFF8B8F97))),
              ]))));
        }).toList())),
        if (current != null) SoftPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CircleAvatar(backgroundColor: Color(0xFFF1EDFF),
              child: Icon(Icons.menu_book_rounded, color: Color(0xFF7C5CFC))),
            const SizedBox(width: 12),
            Expanded(child: Text('${current['title']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 18),
          Text('${current['scope']}'),
          if ((current['progress_percent'] as int) > 0) ...[
            const SizedBox(height: 12),
            Text('학습 진행률 ${current['progress_percent']}%', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            LinearProgressIndicator(value: (current['progress_percent'] as int) / 100,
              minHeight: 7, borderRadius: BorderRadius.circular(7)),
          ],
          if ((current['remaining_scope'] as String).isNotEmpty) ...[
            const SizedBox(height: 8), Text('남은 내용 · ${current['remaining_scope']}',
              style: const TextStyle(color: Color(0xFFB15E38))),
          ],
          const SizedBox(height: 10), Text('함께 이야기하는 날 · ${current['meeting_date']}',
            style: const TextStyle(color: Color(0xFF8B8F97), fontSize: 12)),
          if ((current['review'] as List).isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(width: double.infinity, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF5E5), borderRadius: BorderRadius.circular(12)),
              child: Text('지난주 복습 · ${(current['review'] as List).join(', ')}')),
          ],
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WeekPage(
              studyId: widget.id, week: Map<String,dynamic>.from(current),
              hasPdf: (study!['pdf_name'] as String).isNotEmpty))).then((_) => refresh()),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(current['active_session_id'] == null ? '이번 주 공부 시작하기' : '친구들과 대화 이어하기'))),
        ])),
        const SectionTitle('계획'),
        Wrap(spacing: 10, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: busy ? null : () => draft(), icon: const Icon(Icons.auto_awesome),
            label: Text(busy ? '만드는 중...' : 'AI 계획 받기')),
          OutlinedButton(onPressed: busy ? null : () => draft(true), child: const Text('남은 일정 재조정')),
        ]),
        SectionTitle('기록', detail: '${minutes.length}개'),
        if (minutes.isEmpty) const SoftPanel(child: Text('아직 기록이 없어요.')),
        ...minutes.map((m) => Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          leading: const CircleAvatar(backgroundColor: Color(0xFFF1EDFF),
            child: Icon(Icons.description_outlined, color: Color(0xFF7C5CFC))),
          title: Text('${m['week_no']}주차 이야기 기록', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${m['minutes']['summary']}', maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SessionPage(id: m['session_id'])))))),
      ]));
  }
}
