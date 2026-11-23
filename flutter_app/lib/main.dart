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
      scaffoldBackgroundColor: const Color(0xFFF4F5F7),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C5CFC),
        surface: Colors.white,
        primary: const Color(0xFF7C5CFC), onPrimary: Colors.white),
      dividerTheme: const DividerThemeData(color: Color(0xFFE9EAEE)),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF191A1C), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      appBarTheme: const AppBarTheme(backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: Color(0xFFE9EAEE))),
        surfaceTintColor: Colors.transparent, centerTitle: false,
        titleTextStyle: TextStyle(fontFamily: 'NotoSansKR', fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF191A1C))),
      cardTheme: CardThemeData(color: Colors.white, elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE9EAEE)))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE1E3E8))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE1E3E8)))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF7C5CFC), foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16), textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
      chipTheme: ChipThemeData(backgroundColor: Colors.white, selectedColor: const Color(0xFFF1EDFF),
        side: const BorderSide(color: Color(0xFFE1E3E8)), labelStyle: const TextStyle(fontFamily: 'NotoSansKR', fontSize: 13, color: Color(0xFF3A3D44)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      listTileTheme: const ListTileThemeData(selectedColor: Color(0xFF191A1C)),
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
const brand = Color(0xFF7C5CFC);
const brandSoft = Color(0xFFF1EDFF);
const ink = Color(0xFF191A1C);
const peerTints = [Color(0xFFFFEDE4), Color(0xFFE3F7EF), Color(0xFFFDE8F0), Color(0xFFFFF4D6)];
const peerAccents = [Color(0xFFFF7A45), Color(0xFF12B886), Color(0xFFF06595), Color(0xFFF59F00)];
String peerLabel(int number) => peerNames[(number - 1) % peerNames.length];
Color peerTint(int number) => peerTints[(number - 1) % peerTints.length];
Color peerAccent(int number) => peerAccents[(number - 1) % peerAccents.length];

class PeerAvatar extends StatelessWidget {
  final int number;
  final double size;
  const PeerAvatar(this.number, {super.key, this.size = 36});
  @override Widget build(BuildContext context) => Container(width: size, height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(shape: BoxShape.circle, color: peerAccent(number)),
    child: Text(peerLabel(number).characters.first, style: TextStyle(color: Colors.white,
      fontWeight: FontWeight.w700, fontSize: size * 0.42)));
}

class ChatBubble extends StatelessWidget {
  final String name;
  final String text;
  final bool mine;
  final String? caption;
  final VoidCallback? onCaptionTap;
  final int? peerNo;
  /// 같은 사람이 이어서 말하면 이름과 프로필을 한 번만 보여준다.
  final bool grouped;
  const ChatBubble({super.key, required this.name, required this.text, required this.mine,
    this.caption, this.onCaptionTap, this.peerNo, this.grouped = false});
  @override Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(!mine && !grouped ? 4 : 18), topRight: Radius.circular(mine && !grouped ? 4 : 18),
      bottomLeft: const Radius.circular(18), bottomRight: const Radius.circular(18));
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: mine ? brand : Colors.white, borderRadius: radius,
        boxShadow: mine ? null : const [BoxShadow(color: Color(0x0F000000), blurRadius: 3, offset: Offset(0, 1))]),
      child: SelectableText(text, style: TextStyle(color: mine ? Colors.white : ink, height: 1.5, fontSize: 15)));
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width < 600 ? width * 0.84 : 560),
        child: Padding(padding: EdgeInsets.only(top: grouped ? 3 : 12), child: Row(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!mine) ...[
              grouped ? const SizedBox(width: 36) : PeerAvatar(peerNo ?? 1),
              const SizedBox(width: 8),
            ],
            Flexible(child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!mine && !grouped) Padding(padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
                  child: Text(name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF3A3D44)))),
                bubble,
                if (caption != null) Padding(padding: const EdgeInsets.only(top: 4), child: InkWell(
                  onTap: onCaptionTap, borderRadius: BorderRadius.circular(12),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: brandSoft, borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.menu_book_outlined, size: 14, color: brand), const SizedBox(width: 4),
                      Text(caption!, style: const TextStyle(fontSize: 12, color: brand, fontWeight: FontWeight.w600)),
                    ])))),
              ])),
          ]))));
  }
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

/// 첫 화면: 메신저 채팅 목록처럼 스터디 채팅방을 모아 보여주고, 누르면 채팅방 페이지로 들어간다.
class RoomShell extends StatefulWidget {
  const RoomShell({super.key});
  @override State<RoomShell> createState() => _RoomShellState();
}
class _RoomShellState extends State<RoomShell> {
  final search = TextEditingController();
  List<dynamic> studies = [];
  bool loading = true, demoMode = false, searching = false, showArchived = false;
  String? loadError;
  @override void initState() { super.initState(); refresh(); }
  @override void dispose() { search.dispose(); super.dispose(); }
  Future<void> refresh() async {
    if (studies.isEmpty) setState(() { loading = true; loadError = null; });
    try {
      final health = await Api.request('GET', '/health');
      final items = await Api.request('GET', '/studies') as List<dynamic>;
      if (mounted) setState(() { studies = items; demoMode = health['demo_mode'] == true; loadError = null; });
    } catch (e) { if (mounted) { setState(() { loadError = e is http.ClientException
      ? '서버에 연결할 수 없어요. 서버를 켜고 다시 시도해 주세요.' : '$e'; }); } }
    finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> enterRoom(dynamic room) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChatRoomPage(studyId: room['id'] as int, title: '${room['title']}')));
    if (mounted) refresh();
  }
  Future<void> createRoom() async {
    final id = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => const CreatePage()));
    if (id == null || !mounted) return;
    await refresh();
    final room = studies.firstWhere((s) => s['id'] == id, orElse: () => null);
    if (room != null && mounted) await enterRoom(room);
  }
  Future<void> pinRoom(int id) async {
    try { await Api.request('PUT', '/studies/$id/pin'); if (mounted) await refresh(); }
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
      if (mounted) await refresh(); }
    catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<void> archiveRoom(dynamic room, bool archived) async {
    try {
      await Api.request('PUT', '/studies/${room['id']}/details', {'archived': archived});
      if (mounted) await refresh();
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<void> openPlan(dynamic room) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => StudyPage(id: room['id'] as int)));
    if (mounted) refresh();
  }
  /// 길게 누르거나(휴대폰) 오른쪽 클릭하면(컴퓨터) 채팅방 관리 메뉴를 연다.
  Future<void> roomMenu(dynamic room) async {
    final archived = room['archived'] == 1;
    final pinned = room['pinned'] == 1;
    final action = await showAdaptiveSheet<String>(context, (sheetContext) {
      Widget item(String value, IconData icon, String label) => ListTile(
        leading: Icon(icon), title: Text(label), onTap: () => Navigator.pop(sheetContext, value));
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('${room['title']}',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
        if (!archived && !pinned) item('pin', Icons.push_pin_outlined, '맨 위에 고정'),
        item('rename', Icons.edit_outlined, '이름 바꾸기'),
        item('plan', Icons.calendar_month_outlined, '전체 계획·일정'),
        item(archived ? 'restore' : 'archive', archived ? Icons.unarchive_outlined : Icons.archive_outlined,
          archived ? '다시 사용하기' : '보관하기'),
      ]);
    });
    if (action == 'pin') pinRoom(room['id'] as int);
    if (action == 'rename') renameRoom(room);
    if (action == 'plan') openPlan(room);
    if (action == 'archive') archiveRoom(room, true);
    if (action == 'restore') archiveRoom(room, false);
  }
  String preview(dynamic room) {
    final last = room['last_message'];
    if (last == null) return '대화를 시작해 보세요';
    final body = '${last['body']}'.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (last['mine'] == true) return body;
    final name = '${last['name']}';
    return name.isEmpty ? body : '$name: $body';
  }
  String shortDate(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? '' : '${d.month}월 ${d.day}일';
  }
  Widget roomTile(dynamic room) {
    final title = '${room['title']}';
    final pinned = room['pinned'] == 1;
    final archived = room['archived'] == 1;
    final week = room['current_week'];
    final accent = peerAccents[(room['id'] as int) % peerAccents.length];
    return InkWell(
      onTap: () => enterRoom(room),
      onLongPress: () => roomMenu(room),
      onSecondaryTap: () => roomMenu(room),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), child: Row(children: [
        Opacity(opacity: archived ? 0.5 : 1, child: Container(width: 52, height: 52, alignment: Alignment.center,
          decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(19)),
          child: Text(title.isEmpty ? '?' : title.characters.first,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: accent)))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700))),
            Padding(padding: const EdgeInsets.only(left: 6), child: Text('${(room['member_count'] as int) + 1}',
              style: const TextStyle(fontSize: 13, color: mutedInk))),
            if (pinned) const Padding(padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.push_pin_rounded, size: 14, color: mutedInk)),
          ]),
          const SizedBox(height: 4),
          Text(preview(room), maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF6B6F77))),
        ])),
        if (week != null) Padding(padding: const EdgeInsets.only(left: 12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(shortDate('${week['meeting_date']}'), style: const TextStyle(fontSize: 12, color: mutedInk)),
          const SizedBox(height: 6),
          Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: archived ? const Color(0xFFEDEEF1) : brandSoft,
              borderRadius: BorderRadius.circular(10)),
            child: Text('${week['week_no']}/${room['weeks']}주차', style: TextStyle(fontSize: 11,
              fontWeight: FontWeight.w600, color: archived ? mutedInk : brand))),
        ])),
      ])),
    );
  }
  @override Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final filtered = studies.where((s) => '${s['title']} ${s['goal']}'.toLowerCase().contains(query)).toList();
    final activeRooms = filtered.where((s) => s['archived'] == 0).toList();
    final archivedRooms = filtered.where((s) => s['archived'] == 1).toList();
    final Widget body;
    if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (loadError != null) {
      body = Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(loadError!), TextButton(onPressed: refresh, child: const Text('다시 시도'))]));
    } else if (studies.isEmpty) {
      body = Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.forum_outlined, size: 48, color: mutedInk),
        const SizedBox(height: 16),
        const Text('아직 스터디가 없어요', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: createRoom, icon: const Icon(Icons.add), label: const Text('스터디 시작하기')),
      ]));
    } else {
      body = RefreshIndicator(onRefresh: refresh, child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        if (searching) Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: TextField(
          controller: search, autofocus: true, onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 20),
            hintText: '채팅방 이름 검색'))),
        ...activeRooms.map(roomTile),
        if (activeRooms.isEmpty && query.isNotEmpty) const Padding(padding: EdgeInsets.all(32),
          child: Center(child: Text('찾는 채팅방이 없어요', style: TextStyle(color: mutedInk)))),
        if (archivedRooms.isNotEmpty) Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: showArchived, onExpansionChanged: (value) => showArchived = value,
            tilePadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Text('보관함 ${archivedRooms.length}', style: const TextStyle(fontSize: 13, color: mutedInk)),
            children: archivedRooms.map(roomTile).toList())),
      ]));
    }
    return ColoredBox(color: const Color(0xFFF4F5F7), child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: chatMaxWidth), child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 20,
        shape: const Border(),
        title: Row(children: [
          const Text('채팅', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          if (demoMode) Container(margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: brandSoft, borderRadius: BorderRadius.circular(8)),
            child: const Text('체험 모드', style: TextStyle(fontSize: 11, color: brand, fontWeight: FontWeight.w600))),
        ]),
        actions: [
          if (studies.length > 1) IconButton(tooltip: '검색', isSelected: searching,
            icon: const Icon(Icons.search_rounded), selectedIcon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() { searching = !searching; if (!searching) search.clear(); })),
          IconButton(tooltip: '새 스터디', onPressed: createRoom, icon: const Icon(Icons.add_comment_outlined)),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
    ))));
  }
}

/// 채팅방 페이지. 주차가 끝나면 같은 화면에서 다음 주차 대화로 바로 이어진다.
class ChatRoomPage extends StatefulWidget {
  final int studyId;
  final String title;
  const ChatRoomPage({super.key, required this.studyId, required this.title});
  @override State<ChatRoomPage> createState() => _ChatRoomPageState();
}
class _ChatRoomPageState extends State<ChatRoomPage> {
  int? sessionId;
  String? error;
  @override void initState() { super.initState(); resolve(); }
  Future<void> resolve() async {
    try {
      final study = await Api.request('GET', '/studies/${widget.studyId}');
      final weeks = study['weeks'] as List<dynamic>;
      final week = weeks.firstWhere((w) => w['status'] != 'complete', orElse: () => weeks.last);
      final active = week['active_session_id'];
      final id = active ?? (await Api.request('POST',
        '/studies/${widget.studyId}/weeks/${week['week_no']}/sessions', {'text': ''}))['session_id'];
      if (mounted) setState(() { sessionId = id as int; error = null; });
    } catch (e) { if (mounted) setState(() => error = '$e'); }
  }
  @override Widget build(BuildContext context) {
    if (sessionId != null) {
      return SessionPage(key: ValueKey(sessionId), id: sessionId!, studyTitle: widget.title, onFinished: resolve);
    }
    return Scaffold(backgroundColor: const Color(0xFFF4F5F7), appBar: AppBar(title: Text(widget.title)),
      body: Center(child: error == null ? const CircularProgressIndicator()
        : Column(mainAxisSize: MainAxisSize.min, children: [
            Text(error!), TextButton(onPressed: resolve, child: const Text('다시 시도'))])));
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
      Card(child: ListTile(leading: const Icon(Icons.event_outlined, color: Color(0xFF7C5CFC)),
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

class SessionPage extends StatefulWidget {
  final int id;
  final String? studyTitle;
  final Future<void> Function()? onFinished;
  const SessionPage({super.key, required this.id, this.studyTitle, this.onFinished});
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
  bool infoOpen = true;
  final sessionScaffoldKey = GlobalKey<ScaffoldState>();
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
    padding: const EdgeInsets.only(top: 22, bottom: 6),
    child: Center(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: const Color(0xFFE6E8EC), borderRadius: BorderRadius.circular(20)),
      child: Text('${s['week_no']}주차 · ${(s['week'] as Map)['title']}',
        style: const TextStyle(fontSize: 12, color: Color(0xFF5B5F68), fontWeight: FontWeight.w600)))));
  Widget summaryCard(Map<String, dynamic> s) {
    final raw = s['minutes'] as String? ?? '';
    final minutes = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
    final checks = (minutes['next_checks'] as List?) ?? [];
    return Center(child: Container(margin: const EdgeInsets.only(top: 16), constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2))]),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(color: brandSoft, padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), child: Row(children: [
          const Icon(Icons.auto_awesome_rounded, size: 18, color: brand), const SizedBox(width: 8),
          Text('${s['week_no']}주차 스터디 정리', style: const TextStyle(fontWeight: FontWeight.w700, color: ink)),
        ])),
        Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${minutes['summary'] ?? ''}', style: const TextStyle(height: 1.55, color: ink)),
          if (checks.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('다음에 다시 볼 것', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: mutedInk)),
            ...checks.map((x) => Padding(padding: const EdgeInsets.only(top: 6), child: Row(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 3), child: Icon(Icons.bookmark_rounded, size: 14, color: brand)),
                const SizedBox(width: 6),
                Expanded(child: Text('$x', style: const TextStyle(height: 1.45, fontSize: 13.5))),
              ]))),
          ],
        ])),
      ])));
  }
  List<Widget> sessionBlock(Map<String, dynamic> s) {
    final messages = (s['messages'] as List?) ?? [];
    final finished = s['status'] != 'active';
    final sid = s['id'] as int;
    final out = <Widget>[weekDivider(s)];
    String? lastSpeaker;
    void add(String speaker, Widget Function(bool grouped) build) {
      out.add(build(lastSpeaker == speaker));
      lastSpeaker = speaker;
    }
    if ((s['initial_note'] as String? ?? '').isNotEmpty) {
      add('me', (g) => ChatBubble(name: '나', text: s['initial_note'], mine: true, grouped: g));
    }
    for (final m in messages) {
      final mine = m['role'] == 'user';
      final peer = mine ? null : m['member_no'] as int?;
      final tag = m['role'] == 'assistant_hint' ? ' · 힌트' : m['role'] == 'assistant_plan' ? ' · 계획 반영' : '';
      add(mine ? 'me' : 'peer$peer$tag', (g) => ChatBubble(
        name: mine ? '나' : '${peerLabel(peer ?? 1)}$tag',
        text: '${m['body']}', mine: mine, peerNo: peer, grouped: g,
        caption: m['page_no'] == null ? null : '교안 ${m['page_no']}쪽',
        onCaptionTap: m['page_no'] == null ? null : () => showSource(sid, m['id'] as int)));
    }
    if (finished) {
      if ((s['revised_note'] as String? ?? '').isNotEmpty) {
        add('me', (g) => ChatBubble(name: '나', text: s['revised_note'], mine: true, grouped: g));
      }
      out.add(summaryCard(s));
    }
    return out;
  }
  Widget typingBubble() {
    final messages = (session?['messages'] as List?) ?? [];
    final peer = messages.isEmpty ? 1 : (messages.last['member_no'] as int? ?? 1);
    return Align(alignment: Alignment.centerLeft, child: Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        PeerAvatar(peer), const SizedBox(width: 8),
        Container(padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(18)),
            boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 3, offset: Offset(0, 1))]),
          child: const TypingDots()),
      ])));
  }
  Widget memberStack(List members) {
    final shown = members.take(3).toList();
    return SizedBox(width: 22.0 * shown.length + 14, height: 36, child: Stack(children: [
      for (var i = 0; i < shown.length; i++) Positioned(left: 22.0 * i, top: 0, child: Container(
        padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: PeerAvatar(shown[i]['member_no'] as int, size: 32))),
    ]));
  }
  Widget infoSection(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: mutedInk)),
      const SizedBox(height: 10),
      ...children,
    ]));
  /// 오른쪽에서 여는 채팅방 정보: 이번 주 계획, 스터디원, 교안, 복습, 설정.
  Widget roomInfoPanel({required bool asDrawer}) {
    final s = session!;
    final week = s['week'] as Map<String, dynamic>;
    final review = (week['review'] as List?) ?? [];
    final members = (s['members'] as List?) ?? [];
    final finished = s['status'] != 'active';
    final hasPdf = (s['pdf_name'] as String).isNotEmpty;
    void close() { if (asDrawer) Navigator.of(context).maybePop(); }
    return Material(color: Colors.white, child: SafeArea(child: Column(children: [
      Container(height: 56, padding: const EdgeInsets.only(left: 20, right: 8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: lineColor))),
        child: Row(children: [
          const Expanded(child: Text('채팅방 정보', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          IconButton(tooltip: '닫기', icon: const Icon(Icons.close_rounded),
            onPressed: asDrawer ? close : () => setState(() => infoOpen = false)),
        ])),
      Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        infoSection('이번 주', [
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: brandSoft, borderRadius: BorderRadius.circular(8)),
              child: Text('${s['week_no']}/${s['total_weeks']}주차',
                style: const TextStyle(fontSize: 12, color: brand, fontWeight: FontWeight.w700))),
            const SizedBox(width: 8),
            Expanded(child: Text('${week['title']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          ]),
          const SizedBox(height: 8),
          Text('${week['scope']}', style: const TextStyle(height: 1.5, color: Color(0xFF3A3D44))),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.event_outlined, size: 16, color: mutedInk), const SizedBox(width: 6),
            Text('모임 ${week['meeting_date']}', style: const TextStyle(fontSize: 13, color: mutedInk)),
          ]),
        ]),
        infoSection('스터디원 ${members.length + 1}', [
          for (final m in members) Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [
            PeerAvatar(m['member_no'] as int, size: 38), const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(peerLabel(m['member_no'] as int), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${m['perspective']} · ${m['level']}', style: const TextStyle(fontSize: 12.5, color: mutedInk)),
            ])),
          ])),
          Row(children: [
            Container(width: 38, height: 38, alignment: Alignment.center,
              decoration: const BoxDecoration(color: brand, shape: BoxShape.circle),
              child: const Text('나', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            const SizedBox(width: 12),
            const Text('나', style: TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ]),
        infoSection('교안', [
          InkWell(onTap: busy ? null : () { close(); attachPdf(); }, borderRadius: BorderRadius.circular(12),
            child: Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: lineColor), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(hasPdf ? Icons.picture_as_pdf_rounded : Icons.upload_file_rounded,
                  color: hasPdf ? const Color(0xFFE03131) : mutedInk),
                const SizedBox(width: 10),
                Expanded(child: Text(hasPdf ? '${s['pdf_name']} · ${s['page_count']}쪽' : 'PDF 교안 추가',
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(hasPdf ? '교체' : '추가', style: const TextStyle(color: brand, fontWeight: FontWeight.w600, fontSize: 13)),
              ]))),
        ]),
        if (review.isNotEmpty) infoSection('복습할 내용', [
          ...review.map((r) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 3), child: Icon(Icons.bookmark_rounded, size: 14, color: brand)),
              const SizedBox(width: 6),
              Expanded(child: Text('$r', style: const TextStyle(height: 1.45, fontSize: 13.5))),
            ]))),
        ]),
        infoSection('설정', [
          if (s['week_no'] > 1 && !finished) SwitchListTile(contentPadding: EdgeInsets.zero, dense: true,
            title: const Text('지난 주차 내용도 질문받기', style: TextStyle(fontSize: 14)),
            value: week['include_previous_questions'] != 0,
            onChanged: busy ? null : togglePrevious),
          ListTile(contentPadding: EdgeInsets.zero, dense: true,
            leading: const Icon(Icons.insights_rounded, color: brand),
            title: const Text('복습·성장 기록', style: TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () { close(); showLearningJourney(); }),
          ListTile(contentPadding: EdgeInsets.zero, dense: true,
            leading: const Icon(Icons.calendar_month_outlined, color: brand),
            title: const Text('전체 계획·일정', style: TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              close();
              await Navigator.push(context, MaterialPageRoute(builder: (_) => StudyPage(id: s['study_id'] as int)));
              if (mounted) refresh();
            }),
        ]),
      ])),
    ])));
  }
  void openInfo(bool wide) {
    if (wide) {
      setState(() => infoOpen = !infoOpen);
    } else {
      sessionScaffoldKey.currentState?.openEndDrawer();
    }
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
      Container(
        padding: const EdgeInsets.fromLTRB(16, 4, 5, 4),
        decoration: BoxDecoration(color: const Color(0xFFF4F5F7), borderRadius: BorderRadius.circular(26)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Focus(onKeyEvent: onAnswerKey, child: TextField(controller: answer, focusNode: answerFocus,
            minLines: 1, maxLines: 5, keyboardType: TextInputType.multiline,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 15),
            decoration: const InputDecoration(hintText: '메시지 보내기', filled: false, isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
              border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none)))),
          const SizedBox(width: 6),
          Padding(padding: const EdgeInsets.only(bottom: 2), child: IconButton.filled(
            onPressed: busy || answer.text.trim().isEmpty ? null : sendAnswer,
            style: IconButton.styleFrom(backgroundColor: brand, foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFD9DBE0), disabledForegroundColor: Colors.white,
              minimumSize: const Size(40, 40)),
            icon: const Icon(Icons.arrow_upward_rounded, size: 20), tooltip: '보내기')),
        ])),
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
    final chat = s == null ? const Center(child: CircularProgressIndicator()) : Column(children: [
        Expanded(child: ListView(controller: scrollController,
          padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 14, vertical: 8), children: [
          Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: chatMaxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final past in history) ...sessionBlock(past),
              ...sessionBlock(s),
              if (pendingText != null) ChatBubble(name: '나', text: pendingText!, mine: true),
              if (thinking) typingBubble(),
              const SizedBox(height: 16),
            ]))),
        ])),
        Container(
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: lineColor))),
          child: SafeArea(top: false, child: Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: chatMaxWidth),
            child: Padding(padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 10, wide ? 24 : 12, 10),
              child: composer(s, messages, awaiting, finished)))))),
      ]);
    final sideOpen = wide && infoOpen && s != null;
    return Scaffold(key: sessionScaffoldKey,
      backgroundColor: const Color(0xFFF4F5F7),
      endDrawer: !wide && s != null ? Drawer(width: 320, backgroundColor: Colors.white,
        child: roomInfoPanel(asDrawer: true)) : null,
      appBar: AppBar(
        actions: [
          IconButton(tooltip: '채팅방 정보', onPressed: s == null ? null : () => openInfo(wide),
            isSelected: sideOpen, selectedIcon: const Icon(Icons.view_sidebar_rounded, color: brand),
            icon: const Icon(Icons.view_sidebar_outlined)),
          const SizedBox(width: 6),
        ],
        title: InkWell(onTap: s == null ? null : () => openInfo(wide), child: Row(children: [
          if (s != null) ...[memberStack((s['members'] as List?) ?? []), const SizedBox(width: 10)],
          Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.studyTitle ?? '${s?['week_no'] ?? ''}주차', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          if (s != null) Text('${s['week_no']}/${s['total_weeks']}주차 · ${(s['week'] as Map)['title']}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: mutedInk)),
        ]))]))),
      body: Row(children: [
        Expanded(child: chat),
        if (sideOpen) Container(width: 320,
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: lineColor))),
          child: roomInfoPanel(asDrawer: false)),
      ]));
  }
}

const wideBreakpoint = 900.0;
const chatMaxWidth = 760.0;
const mutedInk = Color(0xFF8B8F97);
const lineColor = Color(0xFFE9EAEE);

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

class TypingDots extends StatefulWidget {
  const TypingDots({super.key});
  @override State<TypingDots> createState() => _TypingDotsState();
}
class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  @override void dispose() { controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: controller, builder: (context, child) =>
    Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
      final t = ((controller.value * 3) - i).clamp(0.0, 1.0);
      final lift = t < 0.5 ? t * 2 : (1 - t) * 2;
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Transform.translate(
        offset: Offset(0, -3 * lift), child: Container(width: 7, height: 7, decoration: BoxDecoration(
          shape: BoxShape.circle, color: Color.lerp(const Color(0xFFC4C7CE), mutedInk, lift)))));
    })));
}
