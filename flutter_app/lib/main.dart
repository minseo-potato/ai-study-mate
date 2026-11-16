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

class ChatBubble extends StatelessWidget {
  final String name;
  final String text;
  final bool mine;
  final String? caption;
  const ChatBubble({super.key, required this.name, required this.text, required this.mine, this.caption});
  @override Widget build(BuildContext context) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(5, 0, 5, 5),
            child: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF324452)))),
          DecoratedBox(decoration: BoxDecoration(
            color: mine ? const Color(0xFFFEE500) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 3, offset: Offset(0, 1))]),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              child: Text(text, style: const TextStyle(color: Color(0xFF1C2430), height: 1.48)))),
          if (caption != null) Padding(padding: const EdgeInsets.fromLTRB(5, 5, 5, 0),
            child: Text(caption!, style: const TextStyle(fontSize: 11, color: Color(0xFF41596C)))),
        ]))));
}

void errorMessage(BuildContext context, Object e) {
  final message = e is http.ClientException
    ? '서버에 연결할 수 없습니다. 서버가 실행 중인지 확인해 주세요.'
    : e.toString().replaceFirst(RegExp(r'^Exception: '), '');
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String weekStatusLabel(String status) => switch (status) {
  'complete' => '완료',
  'in_progress' => '진행 중',
  _ => '시작 전',
};

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  List<dynamic> studies = [];
  bool demoMode = false;
  bool loading = true;
  String? loadError;
  @override void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    if (mounted) setState(() { loading = true; loadError = null; });
    try {
      final health = await Api.request('GET', '/health');
      final items = await Api.request('GET', '/studies');
      if (mounted) setState(() { studies = items; demoMode = health['demo_mode'] == true; loading = false; });
    }
    catch (e) { if (mounted) { setState(() { loading = false; loadError = e is http.ClientException
      ? '서버에 연결할 수 없습니다. 서버를 켜고 다시 시도해 주세요.' : '$e'; }); } }
  }
  Future<void> openCreate() async {
    final id = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => const CreatePage()));
    if (!mounted) return;
    if (id != null) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => StudyPage(id: id)));
    }
    if (mounted) refresh();
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
        FilledButton.icon(onPressed: openCreate,
          icon: const Icon(Icons.add), label: const Text('새 스터디 만들기')),
      ])),
      if (demoMode) const Padding(padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
        child: Text('시연 모드 · 질문과 요약은 규칙 기반 예시입니다.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13))),
      const SectionTitle('이렇게 진행해요'),
      const SoftPanel(child: Text('① PDF 교안 등록  →  ② 주간 계획 확인  →  ③ 랩미팅에서 질문·답변')),
      if (loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      if (loadError != null) SoftPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(loadError!), const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: refresh, icon: const Icon(Icons.refresh), label: const Text('다시 시도')),
      ])),
      SectionTitle('내 스터디', detail: '${studies.length}개'),
      if (!loading && loadError == null && studies.isEmpty)
        const SoftPanel(child: Text('아직 스터디가 없습니다. PDF 교안을 올려 시작해 보세요.')),
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
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController(), goal = TextEditingController(), weeks = TextEditingController(text: '4'),
      hours = TextEditingController(text: '3'), members = TextEditingController(text: '3');
  DateTime start = DateTime.now();
  PlatformFile? pdf;
  bool busy = false;
  String? pdfError;
  @override void dispose() { for (final c in [title, goal, weeks, hours, members]) { c.dispose(); } super.dispose(); }
  String? requiredField(String? value) => (value?.trim().isEmpty ?? true) ? '내용을 입력해 주세요.' : null;
  String? numberField(String? value, num min, num max, String label) {
    final number = num.tryParse(value?.trim() ?? '');
    if (number == null || number < min || number > max) return '$label: $min~$max 사이로 입력해 주세요.';
    if (min is int && number != number.roundToDouble()) return '$label: 정수로 입력해 주세요.';
    return null;
  }
  Future<void> submit() async {
    final validFields = formKey.currentState!.validate();
    setState(() { pdfError = pdf == null ? 'PDF 교안을 선택해 주세요.'
      : pdf!.size > 10000000 ? '10MB 이하의 PDF를 선택해 주세요.' : null; });
    if (!validFields || pdfError != null) return;
    setState(() => busy = true);
    try {
      final date = '${start.year}-${start.month.toString().padLeft(2,'0')}-${start.day.toString().padLeft(2,'0')}';
      final study = await Api.create({'title': title.text.trim(), 'goal': goal.text.trim(), 'start_date': date,
        'weeks': weeks.text.trim(), 'hours_per_week': hours.text.trim(), 'member_count': members.text.trim()}, pdf!);
      if (mounted) Navigator.pop(context, study['id']);
    } catch (e) { if (mounted) errorMessage(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('새 스터디')),
    body: Form(key: formKey, child: PageContent(children: [
      const SoftPanel(child: Text('PDF 교안을 올리면 주차별 학습 범위를 자동으로 나눠드려요. 계획은 나중에 수정할 수 있습니다.')),
      const SectionTitle('기본 정보'),
      TextFormField(controller: title, validator: requiredField,
        decoration: const InputDecoration(labelText: '스터디 이름', hintText: '예: 신경망 기초 공부')),
      const SizedBox(height: 12),
      TextFormField(controller: goal, validator: requiredField,
        decoration: const InputDecoration(labelText: '학습 목표', hintText: '예: 손실 함수와 학습 과정을 설명하기')),
      const SectionTitle('학습 일정'),
      TextFormField(controller: weeks, keyboardType: TextInputType.number,
        validator: (v) => numberField(v, 1, 26, '학습 주수'),
        decoration: const InputDecoration(labelText: '학습 주수 (1~26)')),
      const SizedBox(height: 12),
      TextFormField(controller: hours, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (v) => numberField(v, 0.5, 80, '주당 학습 시간'),
        decoration: const InputDecoration(labelText: '주당 학습 시간 (0.5~80)')),
      const SizedBox(height: 12),
      TextFormField(controller: members, keyboardType: TextInputType.number,
        validator: (v) => numberField(v, 1, 4, 'AI 스터디원 수'),
        decoration: const InputDecoration(labelText: 'AI 스터디원 수 (1~4)')),
      const SizedBox(height: 12),
      Card(child: ListTile(title: Text('시작일  ${start.year}-${start.month}-${start.day}'), trailing: const Icon(Icons.date_range),
        onTap: () async { final d = await showDatePicker(context: context, initialDate: start,
          firstDate: DateTime(2020), lastDate: DateTime(2100)); if (d != null) setState(() => start = d); })),
      const SectionTitle('교안'),
      Card(child: ListTile(title: Text(pdf?.name ?? 'PDF 교안 선택'),
        subtitle: const Text('텍스트를 읽을 수 있는 PDF · 10MB 이하 · 100쪽 이하'),
        trailing: const Icon(Icons.upload_file), onTap: busy ? null : () async {
        final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
        if (picked != null && mounted) setState(() { pdf = picked.files.single; pdfError = null; });
      })),
      if (pdfError != null) Padding(padding: const EdgeInsets.fromLTRB(12, 4, 0, 0),
        child: Text(pdfError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 20), FilledButton(onPressed: busy ? null : submit, child: Text(busy ? '저장 중...' : '스터디 생성')),
    ])));
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
        const SizedBox(height: 16),
        Text('${(study!['weeks'] as List).where((w) => w['status'] == 'complete').length} / ${(study!['weeks'] as List).length}주 완료'),
        const SizedBox(height: 7),
        LinearProgressIndicator(value: (study!['weeks'] as List).where((w) => w['status'] == 'complete').length /
          (study!['weeks'] as List).length, minHeight: 7, borderRadius: BorderRadius.circular(8)),
      ])),
      const SectionTitle('학습 계획'),
      Wrap(spacing: 10, runSpacing: 8, children: [
        FilledButton.icon(onPressed: busy ? null : () => draft(), icon: const Icon(Icons.auto_awesome),
          label: Text(busy ? '계획 생성 중...' : 'AI 주간 계획 제안')),
        OutlinedButton(onPressed: busy ? null : () => draft(true), child: const Text('남은 일정 변경안')),
      ]),
      SectionTitle('주간 계획', detail: '주차를 눌러 발표를 시작하세요'),
      ...(study!['weeks'] as List).map((w) => Card(child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        title: Text(w['title'].toString().trim() == '${w['week_no']}주차'
          ? '${w['title']}' : '${w['week_no']}주차  ${w['title']}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 7), child:
          Text('${weekStatusLabel(w['status'])} · ${w['scope']}\n랩미팅 ${w['meeting_date']}${(w['review'] as List).isEmpty ? '' : ' · 복습 ${(w['review'] as List).join(', ')}'}')),
        isThreeLine: true,
        trailing: Icon(w['active_session_id'] == null ? Icons.chevron_right : Icons.play_circle_outline),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WeekPage(studyId: widget.id, week: Map<String,dynamic>.from(w)))).then((_) => refresh()),
      ))),
      SectionTitle('회의록', detail: '${minutes.length}개'),
      if (minutes.isEmpty) const SoftPanel(child: Text('랩미팅을 마치면 회의록이 여기에 모입니다.')),
      ...minutes.map((m) => Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        title: Text('${m['week_no']}주차 회의록', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 6), child:
          Text('${m['minutes']['summary']}', maxLines: 2, overflow: TextOverflow.ellipsis)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SessionPage(id: m['session_id'])))))),
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
  bool busy = false;
  @override void dispose() { title.dispose(); scope.dispose(); note.dispose(); super.dispose(); }
  Future<void> save() async {
    if (title.text.trim().isEmpty || scope.text.trim().isEmpty) {
      errorMessage(context, '주차 목표와 교안 범위를 입력해 주세요.'); return;
    }
    setState(() => busy = true);
    try { await Api.request('PUT', '/studies/${widget.studyId}/weeks/${widget.week['week_no']}', {
      'title': title.text.trim(), 'scope': scope.text.trim(), 'meeting_date': widget.week['meeting_date'], 'status': widget.week['status']});
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장했습니다.'))); Navigator.pop(context); }
    } catch (e) { if (mounted) errorMessage(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> start() async {
    if (note.text.trim().length < 10) {
      errorMessage(context, '발표문을 10자 이상 적어 주세요.'); return;
    }
    setState(() => busy = true);
    try { final result = await Api.request('POST', '/studies/${widget.studyId}/weeks/${widget.week['week_no']}/sessions', {'text': note.text.trim()});
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SessionPage(id: result['session_id'])));
    } catch (e) { if (mounted) errorMessage(context, e); }
    finally { if (mounted) setState(() => busy = false); }
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
        if ((widget.week['review'] as List).isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('이전 주 복습 · ${(widget.week['review'] as List).join(', ')}'),
        ],
      ])),
      OutlinedButton(onPressed: busy ? null : save, child: const Text('계획 수정 저장')),
      if (widget.week['active_session_id'] != null) ...[
        const SectionTitle('진행 중인 랩미팅'),
        const SoftPanel(child: Text('이전에 시작한 대화가 있어요. 이어서 질문하고 답변할 수 있습니다.')),
        FilledButton.icon(onPressed: () => Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => SessionPage(id: widget.week['active_session_id']))),
          icon: const Icon(Icons.chat_bubble_outline), label: const Text('대화 이어하기')),
      ] else ...[
        SectionTitle(widget.week['status'] == 'complete' ? '다시 발표하기' : '내 발표 준비'),
        const SoftPanel(child: Text('공부한 내용을 먼저 내 말로 설명해 보세요. AI 스터디원이 질문하며 함께 정리해 줍니다.')),
        TextField(controller: note, maxLines: 8, maxLength: 12000, decoration: const InputDecoration(
          labelText: '내 학습 정리 / 발표문', hintText: '핵심 개념, 이해한 방식, 예시, 헷갈리는 점을 적어 보세요.')),
        const SizedBox(height: 12), FilledButton.icon(onPressed: busy ? null : start,
          icon: const Icon(Icons.chat_bubble_outline), label: Text(busy ? '시작 중...' : '대화 시작하기')),
      ],
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
  final scrollController = ScrollController();
  bool needsReview = false, busy = false;
  @override void initState() { super.initState(); refresh(); }
  @override void dispose() { answer.dispose(); revised.dispose(); scrollController.dispose(); super.dispose(); }
  void scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scrollController.hasClients) {
        scrollController.animateTo(scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }
  Future<void> refresh() async {
    try { final data = await Api.request('GET', '/sessions/${widget.id}');
      if (mounted) { setState(() => session = data); scrollToLatest(); } }
    catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<void> act(String path, [Map<String, dynamic>? body]) async {
    setState(() => busy = true);
    try { final data = await Api.request('POST', '/sessions/${widget.id}/$path', body);
      if (mounted) { setState(() { session = data; answer.clear(); needsReview = false; }); scrollToLatest(); }
    } catch (e) { if (mounted) errorMessage(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> sendAnswer() async {
    if (answer.text.trim().isEmpty) { errorMessage(context, '답변을 적어 주세요.'); return; }
    await act('answer', {'text': answer.text.trim(), 'needs_review': needsReview});
  }
  Future<void> finish() async {
    final note = await showModalBottomSheet<String>(context: context, isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(builder: (sheetContext, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 650), child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('대화 정리하기', style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('질문을 나눈 뒤 이해한 내용을 다시 설명해 보세요. 10자 이상 적으면 회의록을 만들 수 있어요.'),
            const SizedBox(height: 16),
            TextField(controller: revised, autofocus: true, minLines: 3, maxLines: 6, maxLength: 12000,
              onChanged: (_) => setSheetState(() {}),
              decoration: const InputDecoration(hintText: '처음 발표에서 바뀐 점이나 새로 이해한 내용을 적어 보세요.')),
            const SizedBox(height: 8),
            FilledButton(onPressed: revised.text.trim().length < 10 ? null
              : () => Navigator.pop(sheetContext, revised.text.trim()), child: const Text('회의록 만들기')),
          ])))));
    if (note != null && mounted) await act('finish', {'revised_note': note});
  }
  @override Widget build(BuildContext context) {
    final s = session;
    final messages = (s?['messages'] as List?) ?? [];
    final awaiting = messages.isNotEmpty && messages.last['role'] == 'assistant';
    final finished = s != null && s['status'] != 'active';
    final minutes = finished ? jsonDecode(s['minutes'] as String) as Map<String, dynamic> : null;
    final checks = (minutes?['next_checks'] as List?) ?? [];
    return Scaffold(
      backgroundColor: const Color(0xFFB7C9D7),
      appBar: AppBar(backgroundColor: const Color(0xFFB7C9D7),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${s?['week_no'] ?? ''}주차 랩미팅', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text(finished ? '대화가 끝났어요' : 'AI 스터디원과 함께 공부 중',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
        ])),
      body: s == null ? const Center(child: CircularProgressIndicator()) : Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: Column(children: [
          Expanded(child: ListView(controller: scrollController,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 28), children: [
            Center(child: Padding(padding: const EdgeInsets.only(bottom: 16),
              child: Text('내 발표에서 시작된 대화예요',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)))),
            ChatBubble(name: '나 · 첫 발표', text: s['initial_note'], mine: true),
            ...messages.map((m) => ChatBubble(
              name: m['role'] == 'assistant' ? 'AI 스터디원 ${m['member_no']}' : '나',
              text: '${m['body']}', mine: m['role'] != 'assistant',
              caption: m['page_no'] == null ? null : '교안 ${m['page_no']}쪽 참고')),
            if (messages.isEmpty) const Center(child: Padding(
              padding: EdgeInsets.all(18), child: Text('아래에서 질문을 받아 대화를 시작해 보세요.'))),
            if (finished) ...[
              ChatBubble(name: '나 · 다시 정리한 설명', text: s['revised_note'], mine: true),
              const SizedBox(height: 14),
              Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.description_outlined, size: 21), SizedBox(width: 7),
                    Text('오늘의 회의록', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                  ]),
                  const SizedBox(height: 12), Text('${minutes?['summary'] ?? ''}'),
                  const Divider(height: 30),
                  const Text('다음에 확인할 내용', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(checks.isEmpty ? '없음' : checks.map((x) => '• $x').join('\n')),
                ]))),
            ],
          ])),
          if (busy) const LinearProgressIndicator(minHeight: 3),
          SafeArea(top: false, child: Container(color: const Color(0xFFF8FAFC),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12), child: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (finished) FilledButton(onPressed: () => Navigator.pop(context),
                  child: const Text('스터디로 돌아가기'))
                else if (awaiting) ...[
                  Row(children: [
                    Expanded(child: TextField(controller: answer, minLines: 1, maxLines: 3,
                      decoration: const InputDecoration(hintText: '여기에 답변을 적어 보세요.'))),
                    const SizedBox(width: 8),
                    IconButton.filled(onPressed: busy ? null : sendAnswer,
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFFEE500),
                        foregroundColor: const Color(0xFF191919)),
                      icon: const Icon(Icons.send_rounded), tooltip: '답변 보내기'),
                  ]),
                  Row(children: [
                    Checkbox(value: needsReview, onChanged: busy ? null : (v) => setState(() => needsReview = v ?? false)),
                    const Expanded(child: Text('어려웠던 질문으로 표시하고 다음 주에 다시 볼래요', style: TextStyle(fontSize: 12))),
                  ]),
                ] else ...[
                  FilledButton.icon(onPressed: busy ? null : () => act('question'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFEE500),
                      foregroundColor: const Color(0xFF191919)),
                    icon: const Icon(Icons.chat_bubble_outline), label: const Text('질문 받아보기')),
                  TextButton(onPressed: busy ? null : finish, child: const Text('대화 정리하고 회의록 만들기')),
                ],
              ]))),
        ]))));
  }
}
