import 'dart:convert';
import 'package:file_picker/file_picker.dart';
// Flutter 3.50 still ships this API; this demo keeps compatibility with older SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const apiBase = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');
void main() => runApp(const StudyMateApp());

class Api {
  static Uri url(String path) => Uri.parse('$apiBase$path');
  static Future<dynamic> request(String method, String path, [Map<String, dynamic>? body]) async {
    final request = http.Request(method, url(path));
    if (method != 'GET') {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body ?? {});
    }
    final client = http.Client();
    final result = await client.send(request);
    final text = await result.stream.bytesToString();
    client.close();
    if (result.statusCode >= 400) {
      dynamic error;
      try { error = jsonDecode(text)['detail']; } catch (_) { error = text; }
      throw Exception(error);
    }
    return jsonDecode(text);
  }
  static Future<dynamic> create(Map<String, String> fields, PlatformFile pdf) async {
    final request = http.MultipartRequest('POST', url('/studies'))..fields.addAll(fields);
    request.files.add(http.MultipartFile.fromBytes('pdf', pdf.bytes!, filename: pdf.name));
    final response = await request.send();
    final text = await response.stream.bytesToString();
    if (response.statusCode >= 400) {
      dynamic error;
      try { error = jsonDecode(text)['detail']; } catch (_) { error = text; }
      throw Exception(error);
    }
    return jsonDecode(text);
  }
}

class StudyMateApp extends StatelessWidget {
  const StudyMateApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AI 스터디메이트',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansKR',
      scaffoldBackgroundColor: const Color(0xFFF6F8FC),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2452A6), surface: Colors.white),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF6F8FC),
        surfaceTintColor: Colors.transparent, centerTitle: false,
        titleTextStyle: TextStyle(fontFamily: 'NotoSansKR', fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1B2740))),
      cardTheme: CardThemeData(color: Colors.white, elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE4EAF3)))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDCE4EF))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDCE4EF)))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    ),
    home: const HomePage(),
  );
}

class PageContent extends StatelessWidget {
  final List<Widget> children;
  const PageContent({super.key, required this.children});
  @override Widget build(BuildContext context) => Center(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 760),
    child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 100), children: children)));
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? detail;
  const SectionTitle(this.title, {super.key, this.detail});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 24, 2, 10), child: Row(children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      if (detail != null) ...[const Spacer(), Text(detail!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))],
    ]));
}

class SoftPanel extends StatelessWidget {
  final Widget child;
  const SoftPanel({super.key, required this.child});
  @override Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(18), child: child));
}

void errorMessage(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  List<dynamic> studies = [];
  bool demoMode = false;
  @override void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    try {
      final health = await Api.request('GET', '/health');
      final items = await Api.request('GET', '/studies');
      if (mounted) setState(() { studies = items; demoMode = health['demo_mode'] == true; });
    }
    catch (e) { if (mounted) errorMessage(context, e); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI 스터디메이트')),
    body: PageContent(children: [
      SoftPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.auto_stories_rounded, size: 30, color: Color(0xFF2452A6)),
        const SizedBox(height: 14),
        Text('교안에서 시작하는 스터디', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('계획을 세우고 발표한 뒤, AI 동료와 질문을 나눠보세요.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const CreatePage())).then((_) => refresh()),
          icon: const Icon(Icons.add), label: const Text('새 스터디 만들기')),
      ])),
      if (demoMode) const Padding(padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
        child: Text('시연 모드 · 질문과 요약은 규칙 기반 예시입니다.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13))),
      SectionTitle('내 스터디', detail: '${studies.length}개'),
      if (studies.isEmpty) const SoftPanel(child: Text('아직 스터디가 없습니다. PDF 교안을 올려 시작해 보세요.')),
      ...studies.map((s) => Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        leading: const CircleAvatar(backgroundColor: Color(0xFFEAF1FF), child: Icon(Icons.menu_book_rounded, color: Color(0xFF2452A6))),
        title: Text(s['title'], style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 5), child: Text(s['goal'], maxLines: 2, overflow: TextOverflow.ellipsis)),
        trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => StudyPage(id: s['id']))).then((_) => refresh())))),
    ]),
  );
}

class CreatePage extends StatefulWidget {
  const CreatePage({super.key});
  @override State<CreatePage> createState() => _CreatePageState();
}
class _CreatePageState extends State<CreatePage> {
  final title = TextEditingController(), goal = TextEditingController(), weeks = TextEditingController(text: '4'),
      hours = TextEditingController(text: '3'), members = TextEditingController(text: '3');
  DateTime start = DateTime.now();
  PlatformFile? pdf;
  bool busy = false;
  @override void dispose() { for (final c in [title, goal, weeks, hours, members]) { c.dispose(); } super.dispose(); }
  Future<void> submit() async {
    if (pdf == null) { errorMessage(context, 'PDF 교안을 선택해 주세요.'); return; }
    setState(() => busy = true);
    try {
      final date = '${start.year}-${start.month.toString().padLeft(2,'0')}-${start.day.toString().padLeft(2,'0')}';
      final study = await Api.create({'title': title.text, 'goal': goal.text, 'start_date': date,
        'weeks': weeks.text, 'hours_per_week': hours.text, 'member_count': members.text}, pdf!);
      if (mounted) Navigator.pop(context, study['id']);
    } catch (e) { if (mounted) errorMessage(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('새 스터디')),
    body: PageContent(children: [
      const SectionTitle('기본 정보'),
      TextField(controller: title, decoration: const InputDecoration(labelText: '주제')),
      const SizedBox(height: 12),
      TextField(controller: goal, decoration: const InputDecoration(labelText: '학습 목표')),
      const SectionTitle('학습 일정'),
      TextField(controller: weeks, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '학습 주수 (1~26)')),
      const SizedBox(height: 12),
      TextField(controller: hours, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '주당 학습 시간')),
      const SizedBox(height: 12),
      TextField(controller: members, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'AI 스터디원 수 (1~4)')),
      const SizedBox(height: 12),
      Card(child: ListTile(title: Text('시작일  ${start.year}-${start.month}-${start.day}'), trailing: const Icon(Icons.date_range),
        onTap: () async { final d = await showDatePicker(context: context, initialDate: start,
          firstDate: DateTime(2020), lastDate: DateTime(2100)); if (d != null) setState(() => start = d); })),
      const SectionTitle('교안'),
      Card(child: ListTile(title: Text(pdf?.name ?? 'PDF 교안 선택'), trailing: const Icon(Icons.upload_file), onTap: () async {
        final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
        if (picked != null) setState(() => pdf = picked.files.single);
      })),
      const SizedBox(height: 20), FilledButton(onPressed: busy ? null : submit, child: Text(busy ? '저장 중...' : '스터디 생성')),
    ]));
}

class StudyPage extends StatefulWidget {
  final int id;
  const StudyPage({super.key, required this.id});
  @override State<StudyPage> createState() => _StudyPageState();
}
class _StudyPageState extends State<StudyPage> {
  Map<String, dynamic>? study;
  List<dynamic> minutes = [];
  bool busy = false;
  @override void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    try {
      final data = await Api.request('GET', '/studies/${widget.id}');
      final records = await Api.request('GET', '/studies/${widget.id}/minutes');
      if (mounted) setState(() { study = data; minutes = records; });
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
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(study?['title'] ?? '스터디')),
    body: study == null ? const Center(child: CircularProgressIndicator()) : PageContent(children: [
      SoftPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(study!['goal'], style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text('교안 · ${study!['pdf_name']}', style: const TextStyle(color: Color(0xFF64748B))),
      ])),
      const SectionTitle('학습 계획'),
      Wrap(spacing: 10, runSpacing: 8, children: [
        FilledButton.icon(onPressed: busy ? null : () => draft(), icon: const Icon(Icons.auto_awesome),
          label: Text(busy ? '계획 생성 중...' : 'AI 주간 계획 제안')),
        OutlinedButton(onPressed: busy ? null : () => draft(true), child: const Text('남은 일정 변경안')),
      ]),
      SectionTitle('주간 계획', detail: '${(study!['weeks'] as List).length}주'),
      ...(study!['weeks'] as List).map((w) => Card(child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        title: Text(w['title'].toString().trim() == '${w['week_no']}주차'
          ? '${w['title']}' : '${w['week_no']}주차  ${w['title']}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 7), child:
          Text('${w['scope']}\n랩미팅 ${w['meeting_date']}  ·  복습 ${(w['review'] as List).join(', ')}')),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WeekPage(studyId: widget.id, week: Map<String,dynamic>.from(w)))).then((_) => refresh()),
      ))),
      SectionTitle('회의록', detail: '${minutes.length}개'),
      if (minutes.isEmpty) const SoftPanel(child: Text('랩미팅을 마치면 회의록이 여기에 모입니다.')),
      ...minutes.map((m) => Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        title: Text('${m['week_no']}주차 회의록', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text('${m['minutes']['summary']}\n다음 확인 · ${(m['minutes']['next_checks'] as List).join(', ')}'))))),
    ]));
}

class WeekPage extends StatefulWidget {
  final int studyId;
  final Map<String, dynamic> week;
  const WeekPage({super.key, required this.studyId, required this.week});
  @override State<WeekPage> createState() => _WeekPageState();
}
class _WeekPageState extends State<WeekPage> {
  late final title = TextEditingController(text: widget.week['title']);
  late final scope = TextEditingController(text: widget.week['scope']);
  final note = TextEditingController();
  @override void dispose() { title.dispose(); scope.dispose(); note.dispose(); super.dispose(); }
  Future<void> save() async {
    try { await Api.request('PUT', '/studies/${widget.studyId}/weeks/${widget.week['week_no']}', {
      'title': title.text, 'scope': scope.text, 'meeting_date': widget.week['meeting_date'], 'status': widget.week['status']});
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장했습니다.'))); Navigator.pop(context); }
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<void> start() async {
    try { final result = await Api.request('POST', '/studies/${widget.studyId}/weeks/${widget.week['week_no']}/sessions', {'text': note.text});
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SessionPage(id: result['session_id'])));
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text('${widget.week['week_no']}주차')),
    body: PageContent(children: [
      const SectionTitle('이번 주 계획'),
      TextField(controller: title, decoration: const InputDecoration(labelText: '주차 목표')),
      const SizedBox(height: 12),
      TextField(controller: scope, decoration: const InputDecoration(labelText: '교안 범위 (예: 1~8쪽)')),
      const SizedBox(height: 12),
      SoftPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('랩미팅 · ${widget.week['meeting_date']}'),
        const SizedBox(height: 6),
        Text('이전 주 복습 · ${(widget.week['review'] as List).join(', ')}'),
      ])),
      OutlinedButton(onPressed: save, child: const Text('계획 수정 저장')),
      const SectionTitle('내 발표 준비'),
      TextField(controller: note, maxLines: 8, decoration: const InputDecoration(
        labelText: '내 학습 정리 / 발표문', hintText: '핵심 개념, 이해한 방식, 예시, 헷갈리는 점을 직접 적으세요.')),
      const SizedBox(height: 12), FilledButton(onPressed: start, child: const Text('랩미팅 시작')),
    ]));
}

class SessionPage extends StatefulWidget {
  final int id;
  const SessionPage({super.key, required this.id});
  @override State<SessionPage> createState() => _SessionPageState();
}
class _SessionPageState extends State<SessionPage> {
  Map<String, dynamic>? session;
  final answer = TextEditingController(), revised = TextEditingController();
  bool needsReview = false, busy = false;
  @override void initState() { super.initState(); refresh(); }
  @override void dispose() { answer.dispose(); revised.dispose(); super.dispose(); }
  Future<void> refresh() async {
    try { final data = await Api.request('GET', '/sessions/${widget.id}'); if (mounted) setState(() => session = data); }
    catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<void> act(String path, [Map<String, dynamic>? body]) async {
    setState(() => busy = true);
    try { final data = await Api.request('POST', '/sessions/${widget.id}/$path', body);
      if (mounted) setState(() { session = data; answer.clear(); needsReview = false; });
    } catch (e) { if (mounted) errorMessage(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) {
    final s = session;
    final messages = (s?['messages'] as List?) ?? [];
    final awaiting = messages.isNotEmpty && messages.last['role'] == 'assistant';
    return Scaffold(appBar: AppBar(title: const Text('랩미팅')),
      body: s == null ? const Center(child: CircularProgressIndicator()) : PageContent(children: [
        const SectionTitle('처음 발표'),
        SoftPanel(child: Text(s['initial_note'])),
        SectionTitle('대화', detail: '${messages.length}개 메시지'),
        if (messages.isEmpty) const SoftPanel(child: Text('AI 동료의 질문을 받아 대화를 시작하세요.')),
        ...messages.map((m) {
          final peer = m['role'] == 'assistant';
          return Align(alignment: peer ? Alignment.centerLeft : Alignment.centerRight,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 590),
              child: Card(color: peer ? Colors.white : const Color(0xFFEAF1FF),
                child: Padding(padding: const EdgeInsets.all(16), child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(peer ? '스터디원 ${m['member_no']}' : '나',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF2452A6))),
                    const SizedBox(height: 7), Text('${m['body']}'),
                    if (m['page_no'] != null) ...[const SizedBox(height: 7),
                      Text('교안 ${m['page_no']}쪽', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)))],
                  ])))));
        }),
        if (s['status'] == 'active') ...[
          if (!awaiting) ...[const SizedBox(height: 12),
            FilledButton.icon(onPressed: busy ? null : () => act('question'),
              icon: const Icon(Icons.forum_outlined), label: const Text('AI 동료 질문 받기'))],
          if (awaiting) ...[
            const SectionTitle('내 답변'),
            TextField(controller: answer, maxLines: 3, decoration: const InputDecoration(labelText: '내 답변')),
            CheckboxListTile(value: needsReview, onChanged: (v) => setState(() => needsReview = v ?? false),
              title: const Text('답하지 못했거나 다음 주 복습이 필요해요')),
            FilledButton(onPressed: busy ? null : () => act('answer', {'text': answer.text, 'needs_review': needsReview}), child: const Text('답변 보내기')),
          ],
          const SectionTitle('마무리'),
          TextField(controller: revised, maxLines: 6,
            decoration: const InputDecoration(labelText: '질문 후 다시 정리한 설명')),
          const SizedBox(height: 12),
          FilledButton(onPressed: busy ? null : () => act('finish', {'revised_note': revised.text}), child: const Text('회의록 만들고 종료')),
        ] else ...[
          const SectionTitle('회의록'),
          SoftPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((jsonDecode(s['minutes'])['summary'] ?? '').toString()),
            const SizedBox(height: 16),
            const Divider(),
            Text('다음 확인', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text((s['unanswered'] as List).isEmpty ? '없음' : (s['unanswered'] as List).join(', ')),
          ])),
        ],
      ]));
  }
}
