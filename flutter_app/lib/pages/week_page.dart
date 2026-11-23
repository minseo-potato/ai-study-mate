import 'package:flutter/material.dart';
import '../api.dart';
import '../widgets/common.dart';
import 'session_page.dart';

class WeekPage extends StatefulWidget {
  final int studyId;
  final Map<String, dynamic> week;
  final bool hasPdf;
  const WeekPage({super.key, required this.studyId, required this.week, required this.hasPdf});
  @override State<WeekPage> createState() => _WeekPageState();
}
class _WeekPageState extends State<WeekPage> {
  late final title = TextEditingController(text: widget.week['title']);
  late final scope = TextEditingController(text: widget.week['scope']);
  late final remainingScope = TextEditingController(text: widget.week['remaining_scope'] ?? '');
  late double progress = (widget.week['progress_percent'] as int? ?? 0).toDouble();
  late DateTime meetingDate = DateTime.parse(widget.week['meeting_date']);
  late bool includePrevious = widget.week['include_previous_questions'] != 0;
  final note = TextEditingController();
  bool busy = false;
  @override void dispose() { title.dispose(); scope.dispose(); remainingScope.dispose(); note.dispose(); super.dispose(); }
  Map<String, dynamic> weekPayload() => {
    'title': title.text.trim(), 'scope': scope.text.trim(),
    'meeting_date': '${meetingDate.year}-${meetingDate.month.toString().padLeft(2, '0')}-${meetingDate.day.toString().padLeft(2, '0')}',
    'status': widget.week['status'], 'progress_percent': progress.round(),
    'remaining_scope': remainingScope.text.trim(), 'include_previous_questions': includePrevious,
  };
  Future<void> save() async {
    if (title.text.trim().isEmpty || scope.text.trim().isEmpty) {
      errorMessage(context, '주차 목표와 교안 범위를 입력해 주세요.'); return;
    }
    setState(() => busy = true);
    try { await Api.request('PUT', '/studies/${widget.studyId}/weeks/${widget.week['week_no']}', weekPayload());
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('계획을 저장했어요!'))); Navigator.pop(context); }
    } catch (e) { if (mounted) errorMessage(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> start() async {
    if (note.text.trim().isNotEmpty && note.text.trim().length < 10) {
      errorMessage(context, '비워 두거나 10자 이상 적어 주세요.'); return;
    }
    setState(() => busy = true);
    try {
      await Api.request('PUT', '/studies/${widget.studyId}/weeks/${widget.week['week_no']}', weekPayload());
      final result = await Api.request('POST', '/studies/${widget.studyId}/weeks/${widget.week['week_no']}/sessions', {'text': note.text.trim()});
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SessionPage(id: result['session_id'])));
    } catch (e) { if (mounted) errorMessage(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text('${widget.week['week_no']}주차')),
    body: PageContent(children: [
      const SectionTitle('이번 주 계획'),
      TextField(controller: title, decoration: const InputDecoration(
        prefixIcon: Icon(Icons.flag_outlined), labelText: '이번 주 목표')),
      const SizedBox(height: 12),
      TextField(controller: scope, decoration: const InputDecoration(
        prefixIcon: Icon(Icons.menu_book_outlined), labelText: '이번 주 학습 범위',
        hintText: '예: 핵심 개념 또는 교안 1~8쪽')),
      const SizedBox(height: 12),
      SoftPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('지금까지 공부한 정도 · ${progress.round()}%', style: const TextStyle(fontWeight: FontWeight.w700)),
        Slider(value: progress, min: 0, max: 100, divisions: 20,
          onChanged: widget.week['status'] == 'complete' ? null : (value) => setState(() => progress = value)),
        TextField(controller: remainingScope, enabled: widget.week['status'] != 'complete',
          decoration: const InputDecoration(labelText: '아직 못 공부한 내용',
            hintText: '예: 3장 실습, 검증 데이터 개념')),
      ])),
      const SizedBox(height: 12),
      SoftPanel(color: const Color(0xFFF6F7F9), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.event_outlined),
          title: Text('함께 이야기하는 날 · ${meetingDate.year}-${meetingDate.month}-${meetingDate.day}'),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: () async { final selected = await showDatePicker(context: context,
            initialDate: meetingDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (selected != null) setState(() => meetingDate = selected); }),
        if ((widget.week['review'] as List).isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('이전 주 복습 · ${(widget.week['review'] as List).join(', ')}'),
        ],
      ])),
      if (widget.week['week_no'] > 1) SoftPanel(child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('이전 주차 내용도 질문받기'),
        value: includePrevious, onChanged: (value) => setState(() => includePrevious = value))),
      OutlinedButton(onPressed: busy ? null : save, child: const Text('바꾼 계획 저장하기')),
      if (widget.week['active_session_id'] != null) ...[
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: () => Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => SessionPage(id: widget.week['active_session_id']))),
          icon: const Icon(Icons.chat_bubble_outline), label: const Text('대화 이어하기')),
      ] else ...[
        const SizedBox(height: 16),
        TextField(controller: note, maxLines: 6, maxLength: 12000, decoration: const InputDecoration(
          labelText: '내가 이해한 내용 (선택)')),
        const SizedBox(height: 12), FilledButton.icon(onPressed: busy ? null : start,
          icon: const Icon(Icons.chat_bubble_outline), label: Text(busy ? '친구들 부르는 중...' : 'AI 친구들과 이야기하기')),
      ],
    ]));
}
