import 'dart:convert';
import 'package:file_picker/file_picker.dart';
// Flutter 3.50 still ships this API; this demo keeps compatibility with older SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static Future<dynamic> uploadPdf(int studyId, PlatformFile pdf) async {
    final request = http.MultipartRequest('PUT', url('/studies/$studyId/pdf'));
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
      scaffoldBackgroundColor: const Color(0xFFF7F6F3),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2B2A28),
        dynamicSchemeVariant: DynamicSchemeVariant.monochrome, surface: Colors.white,
        primary: const Color(0xFF2B2A28), onPrimary: Colors.white),
      dividerTheme: const DividerThemeData(color: Color(0xFFE8E5DF)),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2B2A28), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF7F6F3),
        surfaceTintColor: Colors.transparent, centerTitle: false,
        titleTextStyle: TextStyle(fontFamily: 'NotoSansKR', fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1C1B19))),
      cardTheme: CardThemeData(color: Colors.white, elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE8E5DF)))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDDD9D2))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDDD9D2)))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF2B2A28), foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    ),
    home: const RoomShell(),
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
const peerTints = [Color(0xFFF0EEE9), Color(0xFFF4ECE8), Color(0xFFECF0E9), Color(0xFFEFECF1)];
const peerAccents = [Color(0xFF5B5852), Color(0xFF9A6A58), Color(0xFF5F7458), Color(0xFF6F6480)];
String peerLabel(int number) => peerNames[(number - 1) % peerNames.length];
Color peerTint(int number) => peerTints[(number - 1) % peerTints.length];
Color peerAccent(int number) => peerAccents[(number - 1) % peerAccents.length];

class ChatBubble extends StatelessWidget {
  final String name;
  final String text;
  final bool mine;
  final String? caption;
  final VoidCallback? onCaptionTap;
  final int? peerNo;
  const ChatBubble({super.key, required this.name, required this.text, required this.mine,
    this.caption, this.onCaptionTap, this.peerNo});
  @override Widget build(BuildContext context) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: ConstrainedBox(constraints: BoxConstraints(
      maxWidth: MediaQuery.sizeOf(context).width < 600 ? MediaQuery.sizeOf(context).width * 0.86 : 560),
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
                  color: mine ? const Color(0xFF6F6A63) : peerAccent(peerNo ?? 1)))),
              DecoratedBox(decoration: BoxDecoration(
                color: mine ? const Color(0xFFE9E6E0) : peerTint(peerNo ?? 1),
                borderRadius: BorderRadius.circular(16)),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                  child: SelectableText(text, style: const TextStyle(color: Color(0xFF1F1E1C), height: 1.48)))),
              if (caption != null) TextButton.icon(onPressed: onCaptionTap,
                icon: const Icon(Icons.menu_book_outlined, size: 15),
                label: Text(caption!, style: const TextStyle(fontSize: 11))),
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

class RoomShell extends StatefulWidget {
  const RoomShell({super.key});
  @override State<RoomShell> createState() => _RoomShellState();
}
class _RoomShellState extends State<RoomShell> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final search = TextEditingController();
  List<dynamic> studies = [];
  int? selectedStudyId, sessionId;
  String roomTitle = '';
  bool loading = true, demoMode = false;
  bool showArchived = false;
  String? loadError;
  @override void initState() { super.initState(); refresh(); }
  @override void dispose() { search.dispose(); super.dispose(); }
  Future<void> refresh([int? preferredId]) async {
    setState(() { loading = true; loadError = null; });
    try {
      final health = await Api.request('GET', '/health');
      final items = await Api.request('GET', '/studies') as List<dynamic>;
      if (!mounted) return;
      setState(() { studies = items; demoMode = health['demo_mode'] == true; });
      final activeItems = items.where((s) => s['archived'] == 0).toList();
      if (activeItems.isNotEmpty) {
        final id = preferredId ?? selectedStudyId ?? activeItems.first['id'] as int;
        await openRoom(activeItems.firstWhere((s) => s['id'] == id, orElse: () => activeItems.first));
      } else { setState(() { selectedStudyId = null; sessionId = null; }); }
    } catch (e) { if (mounted) { setState(() { loadError = e is http.ClientException
      ? '서버에 연결할 수 없어요. 서버를 켜고 다시 시도해 주세요.' : '$e'; }); } }
    finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> openRoom(dynamic item) async {
    try {
      final id = item['id'] as int;
      final study = await Api.request('GET', '/studies/$id');
      final weeks = study['weeks'] as List<dynamic>;
      final week = weeks.firstWhere((w) => w['status'] != 'complete', orElse: () => weeks.last);
      final active = week['active_session_id'];
      final roomSession = active ?? (await Api.request('POST',
        '/studies/$id/weeks/${week['week_no']}/sessions', {'text': ''}))['session_id'];
      if (mounted) setState(() { selectedStudyId = id; roomTitle = item['title']; sessionId = roomSession as int; });
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<void> createRoom() async {
    scaffoldKey.currentState?.closeDrawer();
    final id = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => const CreatePage()));
    if (id != null && mounted) await refresh(id);
  }
  Future<void> pinRoom(int id) async {
    try { await Api.request('PUT', '/studies/$id/pin'); if (mounted) await refresh(id); }
    catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<void> renameRoom(dynamic room) async {
    final controller = TextEditingController(text: room['title']);
    final name = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('채팅방 이름 바꾸기'),
      content: TextField(controller: controller, autofocus: true, maxLength: 120,
        decoration: const InputDecoration(labelText: '새 이름')),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('저장'))],
    ));
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try { await Api.request('PUT', '/studies/${room['id']}/details', {'title': name});
      if (mounted) await refresh(selectedStudyId); }
    catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<void> archiveRoom(dynamic room, bool archived) async {
    try {
      await Api.request('PUT', '/studies/${room['id']}/details', {'archived': archived});
      if (selectedStudyId == room['id'] && archived) selectedStudyId = null;
      if (mounted) await refresh();
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  Widget roomTile(dynamic room) {
    final title = '${room['title']}';
    final pinned = room['pinned'] == 1;
    return ListTile(
      selected: selectedStudyId == room['id'],
      selectedTileColor: const Color(0xFFEFEDE9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: CircleAvatar(backgroundColor: const Color(0xFFE9E6E0), foregroundColor: const Color(0xFF2B2A28),
        child: Text(title.isEmpty ? '?' : title.characters.first, style: const TextStyle(fontWeight: FontWeight.w700))),
      title: Row(children: [
        Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (pinned) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.push_pin, size: 14, color: mutedInk)),
      ]),
      subtitle: room['goal'] == room['title'] ? null : Text('${room['goal']}',
        maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<String>(tooltip: '채팅방 관리', icon: const Icon(Icons.more_horiz, size: 20),
        onSelected: (value) {
          if (value == 'pin') pinRoom(room['id'] as int);
          if (value == 'rename') renameRoom(room);
          if (value == 'archive') archiveRoom(room, true);
          if (value == 'restore') archiveRoom(room, false);
        }, itemBuilder: (_) => [
          if (room['archived'] == 0 && !pinned) const PopupMenuItem(value: 'pin', child: Text('시작 방으로 고정')),
          const PopupMenuItem(value: 'rename', child: Text('이름 바꾸기')),
          PopupMenuItem(value: room['archived'] == 0 ? 'archive' : 'restore',
            child: Text(room['archived'] == 0 ? '보관하기' : '다시 사용하기')),
        ]),
      onTap: room['archived'] == 1 ? () => archiveRoom(room, false) : () {
        scaffoldKey.currentState?.closeDrawer(); openRoom(room);
      },
    );
  }
  Future<void> openPlan() async {
    scaffoldKey.currentState?.closeDrawer();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => StudyPage(id: selectedStudyId!)));
    if (mounted) refresh(selectedStudyId);
  }
  /// 주차를 마치면 같은 채팅 화면에서 다음 주차 대화로 바로 이어진다.
  Future<void> advance() async {
    if (selectedStudyId == null) return;
    await openRoom({'id': selectedStudyId, 'title': roomTitle});
  }
  Widget roomList() {
    final filtered = studies.where((s) =>
      '${s['title']} ${s['goal']}'.toLowerCase().contains(search.text.trim().toLowerCase())).toList();
    final activeRooms = filtered.where((s) => s['archived'] == 0).toList();
    final archivedRooms = filtered.where((s) => s['archived'] == 1).toList();
    return SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 14, 8, 4), child: Row(children: [
        const Expanded(child: Text('스터디', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
        if (demoMode) const Chip(label: Text('체험 모드', style: TextStyle(fontSize: 11)),
          visualDensity: VisualDensity.compact),
        IconButton(tooltip: '새 스터디', onPressed: createRoom, icon: const Icon(Icons.edit_square)),
      ])),
      if (studies.length > 4) Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: TextField(controller: search,
        onChanged: (_) => setState(() {}), decoration: const InputDecoration(isDense: true,
          prefixIcon: Icon(Icons.search, size: 20), hintText: '검색'))),
      Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 8), children: [
        ...activeRooms.map(roomTile),
        if (archivedRooms.isNotEmpty) Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: showArchived, onExpansionChanged: (value) => showArchived = value,
            title: Text('보관함 ${archivedRooms.length}', style: const TextStyle(fontSize: 13, color: mutedInk)),
            children: archivedRooms.map(roomTile).toList())),
      ])),
      if (selectedStudyId != null) Padding(padding: const EdgeInsets.all(8), child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: const Icon(Icons.calendar_month_outlined), title: const Text('전체 계획·기록'), onTap: openPlan)),
    ]));
  }
  @override Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
    final Widget content = loading ? const Center(child: CircularProgressIndicator())
      : loadError != null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(loadError!), TextButton(onPressed: refresh, child: const Text('다시 시도'))]))
      : sessionId == null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.forum_outlined, size: 48, color: Color(0xFF8A857E)),
          const SizedBox(height: 16),
          const Text('AI 스터디메이트', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: createRoom,
            icon: const Icon(Icons.add), label: const Text('스터디 시작하기')),
        ]))
      : SessionPage(key: ValueKey(sessionId), id: sessionId!, studyTitle: roomTitle,
          onMenu: wide ? null : () => scaffoldKey.currentState?.openDrawer(), onFinished: advance);
    if (wide) {
      return Scaffold(key: scaffoldKey, body: Row(children: [
        Container(width: 300, decoration: const BoxDecoration(color: Colors.white,
          border: Border(right: BorderSide(color: lineColor))), child: roomList()),
        Expanded(child: content),
      ]));
    }
    return Scaffold(key: scaffoldKey, drawer: Drawer(backgroundColor: Colors.white, child: roomList()), body: content);
  }
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
      final study = await Api.create({'title': title.text.trim(), 'goal': goal.text.trim().isEmpty ? title.text.trim() : goal.text.trim(), 'start_date': date,
        'weeks': weeks.text.trim(), 'hours_per_week': hours.text.trim(), 'member_count': members.text.trim(),
        'member_profiles': jsonEncode(profiles)}, pdf);
      if (mounted) Navigator.pop(context, study['id']);
    } catch (e) { if (mounted) errorMessage(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('새 스터디')),
    body: Form(key: formKey, child: PageContent(children: [
      const SizedBox(height: 12),
      TextFormField(controller: title, validator: requiredField, autofocus: true,
        textInputAction: TextInputAction.done, onFieldSubmitted: (_) { if (!busy) submit(); },
        decoration: const InputDecoration(prefixIcon: Icon(Icons.bookmark_outline),
          labelText: '학습 주제', hintText: '예: 신경망 기초')),
      const SizedBox(height: 12),
      Card(child: ListTile(leading: Icon(pdf == null ? Icons.upload_file_outlined : Icons.picture_as_pdf_outlined),
        title: Text(pdf?.name ?? 'PDF 교안 추가 (선택)', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: pdf == null ? null : IconButton(
          tooltip: 'PDF 빼기', icon: const Icon(Icons.close),
          onPressed: busy ? null : () => setState(() { pdf = null; pdfError = null; })),
        onTap: busy ? null : () async {
        final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
        if (picked != null && mounted) setState(() { pdf = picked.files.single; pdfError = null; });
      })),
      if (pdfError != null) Padding(padding: const EdgeInsets.fromLTRB(12, 4, 0, 0),
        child: Text(pdfError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 4),
      Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          title: const Text('세부 설정', style: TextStyle(fontSize: 14)), children: [
      TextFormField(controller: goal,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.flag_outlined),
          labelText: '학습 목표', hintText: '비워 두면 주제와 같아요')),
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
      Card(child: ListTile(leading: const Icon(Icons.event_outlined, color: Color(0xFF2B2A28)),
        title: Text('시작일  ${start.year}-${start.month}-${start.day}'), trailing: const Icon(Icons.chevron_right),
        onTap: () async { final d = await showDatePicker(context: context, initialDate: start,
          firstDate: DateTime(2020), lastDate: DateTime(2100)); if (d != null) setState(() => start = d); })),
      ])),
      const SizedBox(height: 20), FilledButton(onPressed: busy ? null : submit, child: Text(busy ? '만드는 중...' : '시작하기')),
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
        SoftPanel(color: const Color(0xFFF0EEEA), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(study!['goal'], style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text((study!['pdf_name'] as String).isEmpty ? '교안 없이 내 방식대로 공부해요' : '함께 볼 교안 · ${study!['pdf_name']}',
            style: const TextStyle(color: Color(0xFF6F6A63))),
          const SizedBox(height: 16),
          Text('$completed / ${weeks.length}주 완료', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          LinearProgressIndicator(value: completed / weeks.length, minHeight: 8,
            borderRadius: BorderRadius.circular(8), backgroundColor: const Color(0xFFE4E0D9)),
        ])),
        Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          leading: const CircleAvatar(backgroundColor: Color(0xFFEFEDE9),
            child: Icon(Icons.insights_rounded, color: Color(0xFF2B2A28))),
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
              decoration: BoxDecoration(color: selected ? const Color(0xFF2B2A28) : const Color(0xFFEFEDE9),
                borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                Text('${w['week_no']}주차', style: TextStyle(fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : const Color(0xFF2F2D2A))),
                const SizedBox(height: 3),
                Text(weekStatusLabel(w['status']), style: TextStyle(fontSize: 11,
                  color: selected ? Colors.white70 : const Color(0xFF8A857E))),
              ]))));
        }).toList())),
        if (current != null) SoftPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CircleAvatar(backgroundColor: Color(0xFFEFEDE9),
              child: Icon(Icons.menu_book_rounded, color: Color(0xFF2B2A28))),
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
            style: const TextStyle(color: Color(0xFF6F6A63), fontSize: 12)),
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
          leading: const CircleAvatar(backgroundColor: Color(0xFFEFEDE9),
            child: Icon(Icons.description_outlined, color: Color(0xFF2B2A28))),
          title: Text('${m['week_no']}주차 이야기 기록', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${m['minutes']['summary']}', maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SessionPage(id: m['session_id'])))))),
      ]));
  }
}

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
    child: Column(children: [Icon(icon, color: const Color(0xFF2B2A28), size: 20),
      const SizedBox(height: 6), Text('$value', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6F6A63))),
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
        SoftPanel(color: const Color(0xFFF0EEEA), child: Column(
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
              style: const TextStyle(color: Color(0xFF6F6A63), fontSize: 12)),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, constraints) => constraints.maxWidth >= 460
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: noteBlock('${week['baseline_label']}', '${week['baseline_text']}', const Color(0xFFF3F2EF))),
                  const SizedBox(width: 10),
                  Expanded(child: noteBlock('대화 뒤 다시 정리', '${week['revised_note']}', const Color(0xFFEDF0EA))),
                ])
              : Column(children: [
                  noteBlock('${week['baseline_label']}', '${week['baseline_text']}', const Color(0xFFF3F2EF)),
                  const SizedBox(height: 10),
                  noteBlock('대화 뒤 다시 정리', '${week['revised_note']}', const Color(0xFFEDF0EA)),
                ])),
            if ('${week['summary']}'.isNotEmpty) ...[
              const SizedBox(height: 14), Text('스터디 기록 · ${week['summary']}',
                style: const TextStyle(height: 1.5)),
            ],
          ])))),
      ]));
  }
}

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
      SoftPanel(color: const Color(0xFFF3F2EF), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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

class SessionPage extends StatefulWidget {
  final int id;
  final String? studyTitle;
  final VoidCallback? onMenu;
  final Future<void> Function()? onFinished;
  const SessionPage({super.key, required this.id, this.studyTitle, this.onMenu, this.onFinished});
  @override State<SessionPage> createState() => _SessionPageState();
}
class _SessionPageState extends State<SessionPage> {
  Map<String, dynamic>? session;
  List<Map<String, dynamic>> history = [];
  final answer = TextEditingController(), revised = TextEditingController();
  final scrollController = ScrollController();
  final answerFocus = FocusNode();
  bool needsReview = false, busy = false;
  String? busyAction, pendingText;
  /// 채팅방 모드에서는 지난 주차 대화까지 한 화면에 이어서 보여준다.
  bool get continuous => widget.onFinished != null;
  @override void initState() { super.initState(); refresh(withHistory: true); }
  @override void dispose() {
    answer.dispose(); revised.dispose(); scrollController.dispose(); answerFocus.dispose(); super.dispose();
  }
  void scrollToLatest({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;
      final end = scrollController.position.maxScrollExtent;
      animate ? scrollController.animateTo(end, duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
        : scrollController.jumpTo(end);
    });
  }
  void focusAnswer() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && session?['status'] == 'active') answerFocus.requestFocus();
  });
  Future<void> loadHistory(int studyId) async {
    final records = await Api.request('GET', '/studies/$studyId/minutes') as List<dynamic>;
    final ids = records.map((r) => r['session_id'] as int).where((id) => id != widget.id).toList()..sort();
    final items = await Future.wait(ids.map((id) => Api.request('GET', '/sessions/$id')));
    if (mounted) setState(() => history = items.map((e) => Map<String, dynamic>.from(e as Map)).toList());
  }
  Future<void> refresh({bool withHistory = false}) async {
    try {
      final data = await Api.request('GET', '/sessions/${widget.id}');
      if (withHistory && continuous) await loadHistory(data['study_id'] as int);
      if (!mounted) return;
      setState(() => session = data);
      scrollToLatest(animate: !withHistory);
      final messages = data['messages'] as List;
      if (data['status'] == 'active' && !busy &&
          (messages.isEmpty || messages.last['role'] == 'assistant_reaction' || messages.last['role'] == 'user')) {
        await act('question');
      } else { focusAnswer(); }
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<bool> act(String path, [Map<String, dynamic>? body]) async {
    setState(() { busy = true; busyAction = path; });
    scrollToLatest();
    try { final data = await Api.request('POST', '/sessions/${widget.id}/$path', body);
      if (mounted) { setState(() {
        session = data;
        if (path == 'answer') needsReview = false;
      }); scrollToLatest(); }
      return true;
    } catch (e) { if (mounted) errorMessage(context, e); return false; }
    finally {
      if (mounted) setState(() { busy = false; busyAction = null; });
      if (path == 'question' || path == 'explain') focusAnswer();
    }
  }
  Future<void> sendAnswer() async {
    if (busy) return;
    final text = answer.text.trim();
    if (text.isEmpty) { answerFocus.requestFocus(); return; }
    setState(() { pendingText = text; answer.clear(); });
    final saved = await act('answer', {'text': text, 'needs_review': needsReview});
    if (!mounted) return;
    setState(() => pendingText = null);
    if (!saved) { answer.text = text; return; }
    await act('question');
  }
  Future<void> attachPdf() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom,
      allowedExtensions: ['pdf'], withData: true);
    if (picked == null || !mounted) return;
    final file = picked.files.single;
    if (file.size > 10000000 || file.bytes == null) {
      errorMessage(context, '10MB 이하의 PDF를 선택해 주세요.'); return;
    }
    if ((session?['pdf_name'] as String? ?? '').isNotEmpty) {
      final replace = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('교안을 바꿀까요?'),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('교체'))],
      ));
      if (replace != true || !mounted) return;
    }
    setState(() => busy = true);
    try {
      await Api.uploadPdf(session!['study_id'] as int, file);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('교안 추가됨 · ${file.name}')));
        await refresh();
      }
    } catch (e) { if (mounted) errorMessage(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> showSource(int sessionId, int messageId) async {
    try {
      final source = await Api.request('GET', '/sessions/$sessionId/sources/$messageId');
      if (!mounted) return;
      await showAdaptiveSheet(context, (sheetContext) => ListView(shrinkWrap: true, children: [
        Text('${source['pdf_name']} · ${source['page_no']}쪽', style: Theme.of(sheetContext).textTheme.titleMedium),
        const SizedBox(height: 14),
        SelectableText('${source['text']}', style: const TextStyle(height: 1.5)),
      ]));
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<void> showLearningJourney() async {
    if (session == null) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) =>
      LearningJourneyPage(studyId: session!['study_id'] as int)));
    if (mounted) await refresh();
  }
  Future<void> togglePrevious(bool value) async {
    final current = session!['week'] as Map<String, dynamic>;
    try {
      await Api.request('PUT', '/studies/${session!['study_id']}/weeks/${session!['week_no']}', {
        'title': current['title'], 'scope': current['scope'],
        'meeting_date': current['meeting_date'], 'status': current['status'],
        'include_previous_questions': value,
      });
      await refresh();
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<void> showWeekInfo() async {
    final s = session;
    if (s == null) return;
    final week = s['week'] as Map<String, dynamic>;
    final review = (week['review'] as List?) ?? [];
    final finished = s['status'] != 'active';
    await showAdaptiveSheet(context, (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${s['week_no']}주차 · ${week['title']}', style: Theme.of(sheetContext).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('${week['scope']}', style: const TextStyle(height: 1.5)),
        if ((s['pdf_name'] as String).isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(children: [const Icon(Icons.picture_as_pdf_outlined, size: 16, color: mutedInk), const SizedBox(width: 6),
            Expanded(child: Text('${s['pdf_name']} · ${s['page_count']}쪽',
              style: const TextStyle(fontSize: 13, color: mutedInk)))]),
        ],
        if (review.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('복습', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          ...review.map((r) => Text('• $r', style: const TextStyle(height: 1.5))),
        ],
        if (s['week_no'] > 1 && !finished) SwitchListTile(contentPadding: EdgeInsets.zero,
          title: const Text('지난 주차 내용도 질문받기'),
          value: week['include_previous_questions'] != 0,
          onChanged: (v) { Navigator.pop(sheetContext); togglePrevious(v); }),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: () { Navigator.pop(sheetContext); showLearningJourney(); },
            icon: const Icon(Icons.insights_outlined, size: 18), label: const Text('복습·성장 기록')),
          OutlinedButton.icon(onPressed: busy ? null : () { Navigator.pop(sheetContext); attachPdf(); },
            icon: const Icon(Icons.attach_file_rounded, size: 18),
            label: Text((s['pdf_name'] as String).isEmpty ? '교안 추가' : '교안 교체')),
        ]),
      ]));
  }
  Future<void> finish() async {
    final s = session!;
    final hasNext = (s['week_no'] as int) < (s['total_weeks'] as int);
    final note = await showAdaptiveSheet<String>(context, (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${s['week_no']}주차 마치기', style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        TextField(controller: revised, autofocus: true, minLines: 3, maxLines: 6, maxLength: 12000,
          decoration: const InputDecoration(hintText: '새로 알게 된 점이나 헷갈리는 점 (선택)')),
        const SizedBox(height: 8),
        FilledButton(onPressed: () => Navigator.pop(sheetContext, revised.text.trim()),
          child: Text(continuous && hasNext ? '마치고 다음 주차로' : '마치기')),
      ]));
    if (note == null || !mounted) return;
    final saved = await act('finish', {'revised_note': note});
    if (saved && mounted && continuous && hasNext) await widget.onFinished!();
  }

  Widget weekDivider(Map<String, dynamic> s) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Row(children: [
      const Expanded(child: Divider()),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(
        '${s['week_no']}주차 · ${(s['week'] as Map)['title']}',
        style: const TextStyle(fontSize: 12, color: mutedInk, fontWeight: FontWeight.w600))),
      const Expanded(child: Divider()),
    ]));
  Widget summaryCard(Map<String, dynamic> s) {
    final raw = s['minutes'] as String? ?? '';
    final minutes = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
    final checks = (minutes['next_checks'] as List?) ?? [];
    return Container(margin: const EdgeInsets.symmetric(vertical: 10), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: lineColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.description_outlined, size: 18), const SizedBox(width: 6),
          Text('${s['week_no']}주차 정리', style: const TextStyle(fontWeight: FontWeight.w700))]),
        const SizedBox(height: 8),
        Text('${minutes['summary'] ?? ''}', style: const TextStyle(height: 1.5)),
        if (checks.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(checks.map((x) => '• $x').join('\n'), style: const TextStyle(color: mutedInk, height: 1.5)),
        ],
      ]));
  }
  List<Widget> sessionBlock(Map<String, dynamic> s) {
    final messages = (s['messages'] as List?) ?? [];
    final finished = s['status'] != 'active';
    final sid = s['id'] as int;
    return [
      weekDivider(s),
      if ((s['initial_note'] as String? ?? '').isNotEmpty) ChatBubble(name: '나', text: s['initial_note'], mine: true),
      ...messages.map((m) {
        final mine = m['role'] == 'user';
        final peer = mine ? null : m['member_no'] as int?;
        return ChatBubble(
          name: mine ? '나' : m['role'] == 'assistant_hint' ? '${peerLabel(peer ?? 1)} · 힌트'
            : m['role'] == 'assistant_plan' ? '${peerLabel(peer ?? 1)} · 계획 반영' : peerLabel(peer ?? 1),
          text: '${m['body']}', mine: mine, peerNo: peer,
          caption: m['page_no'] == null ? null : '교안 ${m['page_no']}쪽',
          onCaptionTap: m['page_no'] == null ? null : () => showSource(sid, m['id'] as int));
      }),
      if (finished) ...[
        if ((s['revised_note'] as String? ?? '').isNotEmpty) ChatBubble(name: '나', text: s['revised_note'], mine: true),
        summaryCard(s),
      ],
    ];
  }
  Widget typingBubble() {
    final messages = (session?['messages'] as List?) ?? [];
    final peer = messages.isEmpty ? 1 : (messages.last['member_no'] as int? ?? 1);
    return Align(alignment: Alignment.centerLeft, child: Padding(
      padding: const EdgeInsets.fromLTRB(44, 6, 0, 6),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: peerTint(peer), borderRadius: BorderRadius.circular(16)),
        child: const SizedBox(width: 28, height: 14, child: LinearProgressIndicator(
          minHeight: 3, backgroundColor: Colors.transparent, color: mutedInk)))));
  }
  KeyEventResult onAnswerKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter
        && !HardwareKeyboard.instance.isShiftPressed && !answer.value.composing.isValid) {
      sendAnswer();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
  Widget composer(Map<String, dynamic> s, List messages, bool awaiting, bool finished) {
    if (finished) {
      return FilledButton.icon(onPressed: widget.onFinished ?? () => Navigator.pop(context),
        icon: const Icon(Icons.refresh_rounded),
        label: Text(continuous ? '한 번 더 이야기하기' : '돌아가기'));
    }
    final canHint = awaiting && messages.last['role'] == 'assistant';
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        if (canHint) Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(
          avatar: const Icon(Icons.lightbulb_outline, size: 16), label: const Text('힌트'),
          onPressed: busy ? null : () => act('explain'))),
        if (awaiting) Padding(padding: const EdgeInsets.only(right: 8), child: FilterChip(
          avatar: needsReview ? null : const Icon(Icons.bookmark_border, size: 16),
          label: const Text('복습에 추가'), selected: needsReview,
          onSelected: busy ? null : (v) => setState(() => needsReview = v))),
        if (!awaiting && !busy) Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(
          avatar: const Icon(Icons.refresh_rounded, size: 16), label: const Text('다음 질문'),
          onPressed: () => act('question'))),
        ActionChip(avatar: const Icon(Icons.check_rounded, size: 16), label: Text('${s['week_no']}주차 마치기'),
          onPressed: busy || messages.isEmpty ? null : finish),
      ])),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Focus(onKeyEvent: onAnswerKey, child: TextField(controller: answer, focusNode: answerFocus,
          minLines: 1, maxLines: 5, keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(hintText: '답하기, 질문, 일정·계획 변경도 여기에')))),
        const SizedBox(width: 8),
        IconButton.filled(onPressed: busy ? null : sendAnswer,
          style: IconButton.styleFrom(minimumSize: const Size(50, 50)),
          icon: const Icon(Icons.arrow_upward_rounded), tooltip: '보내기'),
      ]),
    ]);
  }
  @override Widget build(BuildContext context) {
    final s = session;
    final messages = (s?['messages'] as List?) ?? [];
    final awaiting = messages.isNotEmpty &&
      (messages.last['role'] == 'assistant' || messages.last['role'] == 'assistant_hint');
    final finished = s != null && s['status'] != 'active';
    final thinking = busyAction == 'question' || busyAction == 'answer' || busyAction == 'explain'
      || (s != null && !finished && messages.isEmpty);
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
    return Scaffold(
      appBar: AppBar(
        leading: widget.onMenu == null ? null : IconButton(
          tooltip: '채팅방 목록', icon: const Icon(Icons.menu), onPressed: widget.onMenu),
        actions: [
          IconButton(tooltip: '이번 주 정보', onPressed: s == null ? null : showWeekInfo,
            icon: const Icon(Icons.info_outline_rounded)),
          const SizedBox(width: 6),
        ],
        title: InkWell(onTap: s == null ? null : showWeekInfo, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.studyTitle ?? '${s?['week_no'] ?? ''}주차', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          if (s != null) Text('${s['week_no']}/${s['total_weeks']}주차 · ${(s['week'] as Map)['title']}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: mutedInk)),
        ]))),
      body: s == null ? const Center(child: CircularProgressIndicator()) : Column(children: [
        Expanded(child: ListView(controller: scrollController,
          padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 14, vertical: 8), children: [
          Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: chatMaxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final past in history) ...sessionBlock(past),
              ...sessionBlock(s),
              if (pendingText != null) ChatBubble(name: '나', text: pendingText!, mine: true),
              if (thinking) typingBubble(),
              const SizedBox(height: 12),
            ]))),
        ])),
        Container(
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: lineColor))),
          child: SafeArea(top: false, child: Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: chatMaxWidth),
            child: Padding(padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 10, wide ? 24 : 12, 10),
              child: composer(s, messages, awaiting, finished)))))),
      ]));
  }
}

const wideBreakpoint = 900.0;
const chatMaxWidth = 760.0;
const mutedInk = Color(0xFF6F6A63);
const lineColor = Color(0xFFE8E5DF);

/// 휴대폰에서는 아래에서 올라오는 시트, 넓은 화면에서는 가운데 대화상자로 연다.
Future<T?> showAdaptiveSheet<T>(BuildContext context, WidgetBuilder builder) {
  final wide = MediaQuery.sizeOf(context).width >= 700;
  if (wide) {
    return showDialog<T>(context: context, builder: (dialogContext) => Dialog(
      backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 560,
        maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.8),
        child: Padding(padding: const EdgeInsets.all(24), child: builder(dialogContext)))));
  }
  return showModalBottomSheet<T>(context: context, isScrollControlled: true, showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 24),
      child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75),
        child: builder(sheetContext))));
}
