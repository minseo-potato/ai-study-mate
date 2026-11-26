import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';
import 'chat_room_page.dart';
import 'create_page.dart';
import 'study_page.dart';

/// 첫 화면: 메신저 채팅 목록처럼 스터디 채팅방을 모아 보여주고, 누르면 채팅방 페이지로 들어간다.
class RoomListPage extends StatefulWidget {
  /// 방을 만들거나 지우면 마이페이지 숫자도 새로 고치도록 알린다.
  final VoidCallback? onChanged;
  const RoomListPage({super.key, this.onChanged});
  @override State<RoomListPage> createState() => _RoomListPageState();
}
class _RoomListPageState extends State<RoomListPage> {
  final search = TextEditingController();
  List<dynamic> studies = [];
  bool loading = true, searching = false, showArchived = false;
  /// 편집 모드에서 고른 채팅방 id. null이면 편집 모드가 아니다.
  Set<int>? selected;
  bool get editing => selected != null;
  String? loadError;
  @override void initState() { super.initState(); refresh(); }
  @override void dispose() { search.dispose(); super.dispose(); }
  Future<void> refresh() async {
    if (studies.isEmpty) setState(() { loading = true; loadError = null; });
    try {
      final items = await Api.request('GET', '/studies') as List<dynamic>;
      if (mounted) setState(() { studies = items; loadError = null; });
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
    widget.onChanged?.call();
    await refresh();
    final room = studies.firstWhere((s) => s['id'] == id, orElse: () => null);
    if (room != null && mounted) await enterRoom(room);
  }
  Future<void> pinRoom(int id) async {
    try { await Api.request('PUT', '/studies/$id/pin'); if (mounted) await refresh(); }
    catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<void> renameRoom(dynamic room) async {
    final edit = await showProfileEditor(context, title: '채팅방 프로필', name: '${room['title']}',
      avatar: roomAvatar(room), nameMax: 120);
    if (edit == null) return;
    try { await Api.request('PUT', '/studies/${room['id']}/details', {'title': edit.name, 'avatar': edit.avatar.code});
      if (mounted) await refresh(); }
    catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<void> archiveRoom(dynamic room, bool archived) async {
    try {
      await Api.request('PUT', '/studies/${room['id']}/details', {'archived': archived});
      if (mounted) await refresh();
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  /// 편집 모드에서 고른 방들을 한꺼번에 보관하거나 되살린다.
  Future<void> archiveSelected(bool archived) async {
    final ids = selected!.toList();
    try {
      await Future.wait(ids.map((id) => Api.request('PUT', '/studies/$id/details', {'archived': archived})));
      setState(() => selected = null);
      await refresh();
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<void> deleteSelected() async {
    final ids = selected!.toList();
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text('채팅방 ${ids.length}개를 삭제할까요?'),
      content: const Text('대화와 기록이 모두 지워지고 되돌릴 수 없어요.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE03131)),
          onPressed: () => Navigator.pop(dialogContext, true), child: const Text('삭제'))],
    ));
    if (ok != true) return;
    try {
      await Future.wait(ids.map((id) => Api.request('DELETE', '/studies/$id')));
      setState(() => selected = null);
      widget.onChanged?.call();
      await refresh();
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  void toggle(int id) => setState(() {
    selected!.contains(id) ? selected!.remove(id) : selected!.add(id);
  });
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
        item('rename', Icons.edit_outlined, '프로필 바꾸기'),
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
    final id = room['id'] as int;
    final checked = selected?.contains(id) ?? false;
    return InkWell(
      onTap: editing ? () => toggle(id) : () => enterRoom(room),
      onLongPress: editing ? null : () => roomMenu(room),
      onSecondaryTap: editing ? null : () => roomMenu(room),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), child: Row(children: [
        if (editing) Padding(padding: const EdgeInsets.only(right: 14), child: Icon(
          checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          color: checked ? brand : const Color(0xFFC5C8CE))),
        Opacity(opacity: archived ? 0.5 : 1, child: ProfileAvatar(roomAvatar(room), size: 52, soft: true)),
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
        if (week != null && !editing) Padding(padding: const EdgeInsets.only(left: 12), child: Column(
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
        if (archivedRooms.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: Align(alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => setState(() => showArchived = !showArchived),
              style: TextButton.styleFrom(foregroundColor: mutedInk),
              icon: Icon(showArchived ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
              label: Text('보관함 ${archivedRooms.length}', style: const TextStyle(fontSize: 13))))),
          if (showArchived || editing) ...archivedRooms.map(roomTile),
        ],
      ]));
    }
    final chosen = studies.where((s) => selected?.contains(s['id']) ?? false).toList();
    final allArchived = chosen.isNotEmpty && chosen.every((s) => s['archived'] == 1);
    // 넓은 화면에서도 양옆이 비어 보이지 않게 바탕을 끝까지 채우고, 내용만 가운데에 둔다.
    return ColoredBox(color: Colors.white, child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: chatMaxWidth), child: Scaffold(
      backgroundColor: Colors.white,
      appBar: editing ? AppBar(
        shape: const Border(),
        leading: IconButton(tooltip: '편집 끝내기', icon: const Icon(Icons.close_rounded),
          onPressed: () => setState(() => selected = null)),
        title: Text(selected!.isEmpty ? '채팅방 선택' : '${selected!.length}개 선택',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        actions: [
          TextButton(onPressed: () => setState(() {
            final ids = studies.map((s) => s['id'] as int).toSet();
            selected = selected!.length == ids.length ? <int>{} : ids;
          }), child: Text(selected!.length == studies.length ? '선택 해제' : '전체 선택')),
          const SizedBox(width: 8),
        ],
      ) : AppBar(
        titleSpacing: 20,
        shape: const Border(),
        title: const Text('채팅', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        actions: [
          if (studies.length > 1) IconButton(tooltip: '검색', isSelected: searching,
            icon: const Icon(Icons.search_rounded), selectedIcon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() { searching = !searching; if (!searching) search.clear(); })),
          if (studies.isNotEmpty) IconButton(tooltip: '편집', icon: const Icon(Icons.checklist_rounded),
            onPressed: () => setState(() { selected = <int>{}; searching = false; search.clear(); })),
          IconButton(tooltip: '새 스터디', onPressed: createRoom, icon: const Icon(Icons.add_comment_outlined)),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
      bottomNavigationBar: !editing ? null : Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: lineColor))),
        child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 10), child: Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: chosen.isEmpty ? null : () => archiveSelected(!allArchived),
            icon: Icon(allArchived ? Icons.unarchive_outlined : Icons.archive_outlined, size: 18),
            label: Text(allArchived ? '다시 사용' : '보관'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE03131)),
            onPressed: chosen.isEmpty ? null : deleteSelected,
            icon: const Icon(Icons.delete_outline_rounded, size: 18), label: const Text('삭제'))),
        ])))),
    ))));
  }
}
