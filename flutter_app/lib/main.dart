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
  static Future<dynamic> create(Map<String, String> fields, PlatformFile? pdf) async {
    final request = http.MultipartRequest('POST', url('/studies'))..fields.addAll(fields);
    if (pdf != null) request.files.add(http.MultipartFile.fromBytes('pdf', pdf.bytes!, filename: pdf.name));
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
      scaffoldBackgroundColor: const Color(0xFFF8FAFF),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F7FF3), surface: Colors.white),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF8FAFF),
        surfaceTintColor: Colors.transparent, centerTitle: false,
        titleTextStyle: TextStyle(fontFamily: 'NotoSansKR', fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF0B1B43))),
      cardTheme: CardThemeData(color: Colors.white, elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE6ECF6)))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDCE4EF))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDCE4EF)))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF3F7FF3), foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
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
    constraints: const BoxConstraints(maxWidth: 640),
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
  final Color? color;
  const SoftPanel({super.key, required this.child, this.color});
  @override Widget build(BuildContext context) => Card(color: color,
    child: Padding(padding: const EdgeInsets.all(18), child: child));
}

const peerNames = ['지식이', '사례이', '융합이', '탐구이'];
const peerTints = [Color(0xFFEAF2FF), Color(0xFFFFEDF4), Color(0xFFE8F8F0), Color(0xFFF2ECFF)];
const peerAccents = [Color(0xFF3F7FF3), Color(0xFFEF6B9A), Color(0xFF37B77D), Color(0xFF9069DA)];
String peerLabel(int number) => peerNames[(number - 1) % peerNames.length];
Color peerTint(int number) => peerTints[(number - 1) % peerTints.length];
Color peerAccent(int number) => peerAccents[(number - 1) % peerAccents.length];

class ChatBubble extends StatelessWidget {
  final String name;
  final String text;
  final bool mine;
  final String? caption;
  final int? peerNo;
  const ChatBubble({super.key, required this.name, required this.text, required this.mine, this.caption, this.peerNo});
  @override Widget build(BuildContext context) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 510),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!mine) ...[
            CircleAvatar(radius: 18, backgroundColor: peerTint(peerNo ?? 1),
              child: Icon(Icons.smart_toy_rounded, size: 20, color: peerAccent(peerNo ?? 1))),
            const SizedBox(width: 8),
          ],
          Flexible(child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(5, 0, 5, 5),
                child: Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: mine ? const Color(0xFF536887) : peerAccent(peerNo ?? 1)))),
              DecoratedBox(decoration: BoxDecoration(
                color: mine ? const Color(0xFFDDEBFF) : peerTint(peerNo ?? 1),
                borderRadius: BorderRadius.circular(16)),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                  child: Text(text, style: const TextStyle(color: Color(0xFF1C2430), height: 1.48)))),
              if (caption != null) Padding(padding: const EdgeInsets.fromLTRB(5, 5, 5, 0),
                child: Text(caption!, style: const TextStyle(fontSize: 11, color: Color(0xFF536887)))),
            ])),
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
      SoftPanel(color: const Color(0xFFEAF3FF), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CircleAvatar(radius: 28, backgroundColor: Color(0xFFD4E6FF),
          child: Icon(Icons.smart_toy_rounded, size: 30, color: Color(0xFF3F7FF3))),
        const SizedBox(height: 14),
        Text('오늘도 같이 공부해요!',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF0B1B43))),
        const SizedBox(height: 8),
        const Text('공부할 주제만 정해 주세요. AI 친구들이 옆에서 함께할게요.',
          style: TextStyle(color: Color(0xFF536887))),
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: openCreate,
          icon: const Icon(Icons.add), label: const Text('새 스터디 만들기')),
      ])),
      if (demoMode) const Padding(padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
        child: Text('지금은 체험 모드예요. 질문과 정리는 예시로 보여드려요.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13))),
      const SectionTitle('이렇게 진행해요'),
      const SoftPanel(child: Text('① 주제 고르기  →  ② 이번 주 공부하기  →  ③ AI 친구들과 이야기하기')),
      if (loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      if (loadError != null) SoftPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(loadError!), const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: refresh, icon: const Icon(Icons.refresh), label: const Text('다시 시도')),
      ])),
      SectionTitle('내 스터디', detail: '${studies.length}개'),
      if (!loading && loadError == null && studies.isEmpty)
        const SoftPanel(child: Text('아직 스터디가 없네요. 공부하고 싶은 주제로 하나 만들어 볼까요?')),
      ...studies.map((s) => Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        leading: const CircleAvatar(backgroundColor: Color(0xFFEAF2FF),
          child: Icon(Icons.smart_toy_rounded, color: Color(0xFF3F7FF3))),
        title: Text(s['title'], style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 5), child: Text(s['goal'], maxLines: 2, overflow: TextOverflow.ellipsis)),
        trailing: const Icon(Icons.chevron_right_rounded), onTap: () => Navigator.push(context,
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
  final peerUnderstanding = [
    TextEditingController(text: '핵심 용어는 조금 알지만 정의와 원리를 다시 확인하고 싶다.'),
    TextEditingController(text: '개념은 들었지만 실제 사례에 적용하는 방법이 아직 헷갈린다.'),
    TextEditingController(text: '기본 원리를 알고 있어 이전 내용과의 연결을 궁금해한다.'),
    TextEditingController(text: '여러 설명을 비교할 수 있지만 다른 해석의 근거를 확인하고 싶다.'),
  ];
  final peerLevels = ['기초', '중급', '심화', '중급'];
  PlatformFile? pdf;
  bool busy = false;
  String? pdfError;
  @override void dispose() { for (final c in [title, goal, weeks, hours, members, ...peerUnderstanding]) { c.dispose(); } super.dispose(); }
  String? requiredField(String? value) => (value?.trim().isEmpty ?? true) ? '내용을 입력해 주세요.' : null;
  String? numberField(String? value, num min, num max, String label) {
    final number = num.tryParse(value?.trim() ?? '');
    if (number == null || number < min || number > max) return '$label: $min~$max 사이로 입력해 주세요.';
    if (min is int && number != number.roundToDouble()) return '$label: 정수로 입력해 주세요.';
    return null;
  }
  Future<void> submit() async {
    final validFields = formKey.currentState!.validate();
    setState(() { pdfError = pdf != null && pdf!.size > 10000000 ? '10MB 이하의 PDF를 선택해 주세요.' : null; });
    if (!validFields || pdfError != null) return;
    setState(() => busy = true);
    try {
      final date = '${start.year}-${start.month.toString().padLeft(2,'0')}-${start.day.toString().padLeft(2,'0')}';
      final memberCount = int.parse(members.text.trim());
      final profiles = List.generate(memberCount, (i) => {
        'level': peerLevels[i], 'understanding': peerUnderstanding[i].text.trim(),
      });
      final study = await Api.create({'title': title.text.trim(), 'goal': goal.text.trim(), 'start_date': date,
        'weeks': weeks.text.trim(), 'hours_per_week': hours.text.trim(), 'member_count': members.text.trim(),
        'member_profiles': jsonEncode(profiles)}, pdf);
      if (mounted) Navigator.pop(context, study['id']);
    } catch (e) { if (mounted) errorMessage(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('새 스터디')),
    body: Form(key: formKey, child: PageContent(children: [
      const SoftPanel(color: Color(0xFFEAF3FF), child: Row(children: [
        CircleAvatar(radius: 25, backgroundColor: Color(0xFFD4E6FF),
          child: Icon(Icons.auto_stories_rounded, color: Color(0xFF3F7FF3))),
        SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('어떤 걸 함께 공부할까요?', style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text('주제와 목표를 적으면 AI 친구들이 기다리고 있을게요.',
            style: TextStyle(fontSize: 12, color: Color(0xFF536887))),
        ])),
      ])),
      const SectionTitle('기본 정보'),
      TextFormField(controller: title, validator: requiredField,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.bookmark_outline),
          labelText: '학습 주제', hintText: '예: 신경망 기초 공부')),
      const SizedBox(height: 12),
      TextFormField(controller: goal, validator: requiredField,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.flag_outlined),
          labelText: '학습 목표', hintText: '예: 손실 함수와 학습 과정을 설명하기')),
      const SectionTitle('학습 일정'),
      TextFormField(controller: weeks, keyboardType: TextInputType.number,
        validator: (v) => numberField(v, 1, 26, '학습 주수'),
        decoration: const InputDecoration(prefixIcon: Icon(Icons.calendar_today_outlined),
          labelText: '학습 주수 (1~26)')),
      const SizedBox(height: 12),
      TextFormField(controller: hours, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (v) => numberField(v, 0.5, 80, '주당 학습 시간'),
        decoration: const InputDecoration(prefixIcon: Icon(Icons.schedule_outlined),
          labelText: '주당 학습 시간 (0.5~80)')),
      const SizedBox(height: 12),
      TextFormField(controller: members, keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        validator: (v) => numberField(v, 1, 4, 'AI 스터디원 수'),
        decoration: const InputDecoration(prefixIcon: Icon(Icons.groups_outlined),
          labelText: 'AI 스터디원 수 (1~4)')),
      const SectionTitle('함께할 AI 친구들'),
      ...List.generate((int.tryParse(members.text.trim()) ?? 3).clamp(1, 4), (i) =>
        SoftPanel(color: peerTint(i + 1), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.smart_toy_rounded, color: peerAccent(i + 1))),
            const SizedBox(width: 10),
            Expanded(child: Text(peerLabel(i + 1), style: const TextStyle(fontWeight: FontWeight.w700))),
            DropdownButton<String>(value: peerLevels[i], underline: const SizedBox.shrink(),
              items: ['기초', '중급', '심화'].map((level) => DropdownMenuItem(value: level, child: Text(level))).toList(),
              onChanged: (value) => setState(() => peerLevels[i] = value ?? peerLevels[i])),
          ]),
          const SizedBox(height: 8),
          TextFormField(controller: peerUnderstanding[i], maxLength: 500,
            decoration: const InputDecoration(labelText: '지금 이해한 내용이나 헷갈리는 부분')),
        ]))),
      const SizedBox(height: 12),
      Card(child: ListTile(leading: const Icon(Icons.event_outlined, color: Color(0xFF3F7FF3)),
        title: Text('시작일  ${start.year}-${start.month}-${start.day}'), trailing: const Icon(Icons.chevron_right),
        onTap: () async { final d = await showDatePicker(context: context, initialDate: start,
          firstDate: DateTime(2020), lastDate: DateTime(2100)); if (d != null) setState(() => start = d); })),
      const SectionTitle('PDF 교안 · 선택사항'),
      Card(child: ListTile(title: Text(pdf?.name ?? '교안 없이 시작하기'),
        subtitle: Text(pdf == null ? '파일이 있다면 눌러서 추가하세요.' : '다른 PDF를 고르려면 눌러 주세요.'),
        trailing: pdf == null ? const Icon(Icons.add_circle_outline) : IconButton(
          tooltip: 'PDF 빼기', icon: const Icon(Icons.close),
          onPressed: busy ? null : () => setState(() { pdf = null; pdfError = null; })),
        onTap: busy ? null : () async {
        final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
        if (picked != null && mounted) setState(() { pdf = picked.files.single; pdfError = null; });
      })),
      const Padding(padding: EdgeInsets.fromLTRB(8, 4, 8, 0),
        child: Text('PDF는 10MB·100쪽 이하, 텍스트를 읽을 수 있는 파일만 지원해요.',
          style: TextStyle(color: Color(0xFF777777), fontSize: 12))),
      if (pdfError != null) Padding(padding: const EdgeInsets.fromLTRB(12, 4, 0, 0),
        child: Text(pdfError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 20), FilledButton(onPressed: busy ? null : submit, child: Text(busy ? '만드는 중...' : '스터디 만들기')),
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
        SoftPanel(color: const Color(0xFFEAF3FF), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(study!['goal'], style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text((study!['pdf_name'] as String).isEmpty ? '교안 없이 내 방식대로 공부해요' : '함께 볼 교안 · ${study!['pdf_name']}',
            style: const TextStyle(color: Color(0xFF536887))),
          const SizedBox(height: 16),
          Text('$completed / ${weeks.length}주 완료', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          LinearProgressIndicator(value: completed / weeks.length, minHeight: 8,
            borderRadius: BorderRadius.circular(8), backgroundColor: const Color(0xFFD9E5F7)),
        ])),
        const SectionTitle('주간 학습'),
        SizedBox(height: 64, child: ListView(scrollDirection: Axis.horizontal, children: weeks.map((w) {
          final selected = w['week_no'] == selectedWeek;
          return Padding(padding: const EdgeInsets.only(right: 8), child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => selectedWeek = w['week_no']),
            child: Container(width: 92, padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(color: selected ? const Color(0xFF3F7FF3) : const Color(0xFFEFF4FC),
                borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                Text('${w['week_no']}주차', style: TextStyle(fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : const Color(0xFF273957))),
                const SizedBox(height: 3),
                Text(weekStatusLabel(w['status']), style: TextStyle(fontSize: 11,
                  color: selected ? Colors.white70 : const Color(0xFF7585A0))),
              ]))));
        }).toList())),
        if (current != null) SoftPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CircleAvatar(backgroundColor: Color(0xFFEAF2FF),
              child: Icon(Icons.menu_book_rounded, color: Color(0xFF3F7FF3))),
            const SizedBox(width: 12),
            Expanded(child: Text('${current['title']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 18),
          const Text('이번 주에는 이걸 공부해요', style: TextStyle(color: Color(0xFF536887), fontSize: 12)),
          const SizedBox(height: 5), Text('${current['scope']}'),
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
            style: const TextStyle(color: Color(0xFF536887), fontSize: 12)),
          if ((current['review'] as List).isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(width: double.infinity, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF5E5), borderRadius: BorderRadius.circular(12)),
              child: Text('지난주 복습 · ${(current['review'] as List).join(', ')}')),
          ],
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WeekPage(
              studyId: widget.id, week: Map<String,dynamic>.from(current)))).then((_) => refresh()),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(current['active_session_id'] == null ? '이번 주 공부 시작하기' : '친구들과 대화 이어하기'))),
        ])),
        const SectionTitle('계획을 바꾸고 싶다면'),
        Wrap(spacing: 10, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: busy ? null : () => draft(), icon: const Icon(Icons.auto_awesome),
            label: Text(busy ? '계획 만드는 중...' : 'AI에게 계획 부탁하기')),
          OutlinedButton(onPressed: busy ? null : () => draft(true), child: const Text('남은 일정 다시 짜 보기')),
        ]),
        SectionTitle('함께 공부한 기록', detail: '${minutes.length}개'),
        if (minutes.isEmpty) const SoftPanel(child: Text('AI 친구들과 이야기를 마치면 기록이 여기에 쌓여요.')),
        ...minutes.map((m) => Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          leading: const CircleAvatar(backgroundColor: Color(0xFFEAF2FF),
            child: Icon(Icons.description_outlined, color: Color(0xFF3F7FF3))),
          title: Text('${m['week_no']}주차 이야기 기록', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${m['minutes']['summary']}', maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SessionPage(id: m['session_id'])))))),
      ]));
  }
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
  late final remainingScope = TextEditingController(text: widget.week['remaining_scope'] ?? '');
  late double progress = (widget.week['progress_percent'] as int? ?? 0).toDouble();
  late DateTime meetingDate = DateTime.parse(widget.week['meeting_date']);
  final note = TextEditingController();
  bool busy = false;
  @override void dispose() { title.dispose(); scope.dispose(); remainingScope.dispose(); note.dispose(); super.dispose(); }
  Future<void> save() async {
    if (title.text.trim().isEmpty || scope.text.trim().isEmpty) {
      errorMessage(context, '주차 목표와 교안 범위를 입력해 주세요.'); return;
    }
    setState(() => busy = true);
    try { await Api.request('PUT', '/studies/${widget.studyId}/weeks/${widget.week['week_no']}', {
      'title': title.text.trim(), 'scope': scope.text.trim(),
      'meeting_date': '${meetingDate.year}-${meetingDate.month.toString().padLeft(2, '0')}-${meetingDate.day.toString().padLeft(2, '0')}',
      'status': widget.week['status'], 'progress_percent': progress.round(),
      'remaining_scope': remainingScope.text.trim()});
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('계획을 저장했어요!'))); Navigator.pop(context); }
    } catch (e) { if (mounted) errorMessage(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> start() async {
    if (note.text.trim().length < 10) {
      errorMessage(context, '공부한 내용을 조금만 더 적어 주세요. 10자 이상이면 시작할 수 있어요.'); return;
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
      SoftPanel(color: const Color(0xFFF1F7FF), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
      OutlinedButton(onPressed: busy ? null : save, child: const Text('바꾼 계획 저장하기')),
      if (widget.week['active_session_id'] != null) ...[
        const SectionTitle('이야기하던 친구들이 기다려요'),
        const SoftPanel(child: Text('지난 대화부터 바로 이어서 이야기할 수 있어요.')),
        FilledButton.icon(onPressed: () => Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => SessionPage(id: widget.week['active_session_id']))),
          icon: const Icon(Icons.chat_bubble_outline), label: const Text('대화 이어하기')),
      ] else ...[
        SectionTitle(widget.week['status'] == 'complete' ? '다시 이야기해 볼까요?' : '공부한 걸 이야기해 주세요'),
        const SoftPanel(color: Color(0xFFEAF3FF), child: Text('완벽하게 쓸 필요 없어요. 지금 이해한 만큼만 적으면 AI 친구들이 궁금한 걸 물어볼 거예요.')),
        const Wrap(spacing: 6, runSpacing: 4, children: [
          Chip(label: Text('핵심 개념')),
          Chip(label: Text('작동 방식')),
          Chip(label: Text('내가 생각한 예시')),
          Chip(label: Text('헷갈리는 부분')),
        ]),
        const SizedBox(height: 8),
        TextField(controller: note, maxLines: 8, maxLength: 12000, decoration: const InputDecoration(
          labelText: '내가 이해한 내용', hintText: '오늘 배운 걸 친구에게 설명하듯 적어 주세요.')),
        const SizedBox(height: 12), FilledButton.icon(onPressed: busy ? null : start,
          icon: const Icon(Icons.chat_bubble_outline), label: Text(busy ? '친구들 부르는 중...' : 'AI 친구들과 이야기하기')),
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
      if (mounted) { setState(() {
        session = data;
        if (path == 'answer') { answer.clear(); needsReview = false; }
      }); scrollToLatest(); }
    } catch (e) { if (mounted) errorMessage(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> sendAnswer() async {
    if (answer.text.trim().isEmpty) { errorMessage(context, '생각나는 만큼만 적어 주세요.'); return; }
    await act('answer', {'text': answer.text.trim(), 'needs_review': needsReview});
  }
  Future<void> finish() async {
    final note = await showModalBottomSheet<String>(context: context, isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(builder: (sheetContext, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 650), child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('오늘 이야기, 다시 정리해 볼까요?', style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('처음에 쓴 내용과 달라진 생각이 있나요? 지금 이해한 걸 내 말로 적어 주세요.'),
            const SizedBox(height: 16),
            TextField(controller: revised, autofocus: true, minLines: 3, maxLines: 6, maxLength: 12000,
              onChanged: (_) => setSheetState(() {}),
              decoration: const InputDecoration(hintText: '새로 알게 된 점이나 아직 헷갈리는 걸 적어 주세요.')),
            const SizedBox(height: 8),
            FilledButton(onPressed: revised.text.trim().length < 10 ? null
              : () => Navigator.pop(sheetContext, revised.text.trim()), child: const Text('오늘의 기록 저장하기')),
          ])))));
    if (note != null && mounted) await act('finish', {'revised_note': note});
  }
  @override Widget build(BuildContext context) {
    final s = session;
    final messages = (s?['messages'] as List?) ?? [];
    final members = (s?['members'] as List?) ?? [];
    final awaiting = messages.isNotEmpty &&
      (messages.last['role'] == 'assistant' || messages.last['role'] == 'assistant_hint');
    final finished = s != null && s['status'] != 'active';
    final minutes = finished ? jsonDecode(s['minutes'] as String) as Map<String, dynamic> : null;
    final checks = (minutes?['next_checks'] as List?) ?? [];
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(backgroundColor: const Color(0xFFF8FAFF),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${s?['week_no'] ?? ''}주차 스터디방', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text(finished ? '오늘의 이야기를 마쳤어요' : 'AI 친구들이 함께 있어요',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
        ])),
      body: s == null ? const Center(child: CircularProgressIndicator()) : Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: Column(children: [
          Expanded(child: ListView(controller: scrollController,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 28), children: [
            if (members.isNotEmpty) ...[
              const Text('함께 공부하는 AI 친구들', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              SizedBox(height: 105, child: ListView(scrollDirection: Axis.horizontal, children: members.map((m) {
                final number = m['member_no'] as int;
                return Container(width: 128, margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: peerTint(number), borderRadius: BorderRadius.circular(18)),
                  child: Column(children: [
                    CircleAvatar(radius: 20, backgroundColor: Colors.white,
                      child: Icon(Icons.smart_toy_rounded, color: peerAccent(number))),
                    const SizedBox(height: 5),
                    Text(peerLabel(number), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    Text('${m['perspective']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: Color(0xFF536887))),
                  ]));
              }).toList())),
              const SizedBox(height: 18),
            ],
            Center(child: Padding(padding: const EdgeInsets.only(bottom: 16),
              child: Text('내가 적은 내용부터 함께 이야기해요',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)))),
            ChatBubble(name: '나 · 처음 생각', text: s['initial_note'], mine: true),
            ...messages.map((m) => ChatBubble(
              name: m['role'] == 'assistant_hint' ? '${peerLabel(m['member_no'] as int)} · 힌트'
                : m['role'] == 'assistant' ? peerLabel(m['member_no'] as int) : '나',
              text: '${m['body']}', mine: m['role'] == 'user',
              peerNo: m['role'] == 'user' ? null : m['member_no'] as int,
              caption: m['page_no'] == null ? null : '교안 ${m['page_no']}쪽 참고')),
            if (messages.isEmpty) const Center(child: Padding(
              padding: EdgeInsets.all(18), child: Text('아래에서 질문을 받아 대화를 시작해 보세요.'))),
            if (finished) ...[
              ChatBubble(name: '나 · 다시 정리한 생각', text: s['revised_note'], mine: true),
              const SizedBox(height: 14),
              Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.description_outlined, size: 21), SizedBox(width: 7),
                    Text('오늘의 스터디 기록', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                  ]),
                  const SizedBox(height: 12), Text('${minutes?['summary'] ?? ''}'),
                  const Divider(height: 30),
                  const Text('다음에 다시 볼 것', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(checks.isEmpty ? '오늘은 다 확인했어요!' : checks.map((x) => '• $x').join('\n')),
                ]))),
            ],
          ])),
          if (busy) const LinearProgressIndicator(minHeight: 3),
          SafeArea(top: false, child: Container(color: Colors.white,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12), child: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (finished) FilledButton(onPressed: () => Navigator.pop(context),
                  child: const Text('스터디로 돌아가기'))
                else if (awaiting) ...[
                  if (messages.last['role'] == 'assistant')
                    Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                      onPressed: busy ? null : () => act('explain'),
                      icon: const Icon(Icons.lightbulb_outline), label: const Text('힌트 좀 줄래?'))),
                  Row(children: [
                    Expanded(child: TextField(controller: answer, minLines: 1, maxLines: 3,
                      decoration: const InputDecoration(hintText: '내 생각을 적어 볼까요?'))),
                    const SizedBox(width: 8),
                    IconButton.filled(onPressed: busy ? null : sendAnswer,
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFF3F7FF3),
                        foregroundColor: Colors.white),
                      icon: const Icon(Icons.send_rounded), tooltip: '답변 보내기'),
                  ]),
                  Row(children: [
                    Checkbox(value: needsReview, onChanged: busy ? null : (v) => setState(() => needsReview = v ?? false)),
                    const Expanded(child: Text('이 질문은 다음 주에 다시 보고 싶어요', style: TextStyle(fontSize: 12))),
                  ]),
                ] else ...[
                  FilledButton.icon(onPressed: busy ? null : () => act('question'),
                    icon: const Icon(Icons.chat_bubble_outline), label: const Text('친구들은 뭐가 궁금할까?')),
                  TextButton(onPressed: busy ? null : finish, child: const Text('오늘 이야기 정리하기')),
                ],
              ]))),
        ]))));
  }
}
