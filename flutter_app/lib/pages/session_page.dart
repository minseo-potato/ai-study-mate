import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/avatar.dart';
import '../widgets/chat.dart';
import '../widgets/files.dart';
import 'study_page.dart';
import 'learning_journey_page.dart';

class SessionPage extends StatefulWidget {
  final int id;
  final String? studyTitle;
  /// 채팅방 모드: 지난 주차 대화까지 한 화면에 이어 보여 주고, 마치면 다음 주차로 이어 간다.
  final bool continuous;
  /// 채팅방에서 이미 받아 온 대화가 있으면 다시 요청하지 않고 바로 그린다.
  final Map<String, dynamic>? initial;
  final List<Map<String, dynamic>>? initialHistory;
  const SessionPage({super.key, required this.id, this.studyTitle, this.continuous = false,
    this.initial, this.initialHistory});
  @override State<SessionPage> createState() => _SessionPageState();
}
class _SessionPageState extends State<SessionPage> {
  Map<String, dynamic>? session;
  List<Map<String, dynamic>> history = [];
  final answer = TextEditingController();
  final scrollController = ScrollController();
  final answerFocus = FocusNode();
  bool needsReview = false, busy = false;
  String? busyAction;
  /// 보냈지만 아직 서버에 전하지 못한 말, 아직 펼치지 않은 친구들의 말 수.
  final pending = <String>[];
  bool pumping = false;
  int actToken = 0, hidden = 0;
  bool composing = false;
  Timer? revealTimer;
  /// 올리는 중인 파일과 방금 마친 주차.
  final uploads = <PickedFile>[];
  bool draining = false;
  int? freshId;
  int get id => session?['id'] as int? ?? widget.id;
  bool infoOpen = true;
  final sessionScaffoldKey = GlobalKey<ScaffoldState>();
  bool get continuous => widget.continuous;
  bool get presenting => session?['presentation'] == true && session?['evaluated'] != true;
  /// 첨부 기록을 뺀 마지막 말.
  Map? get lastTalk => ((session?['messages'] as List?) ?? []).cast<Map?>()
    .lastWhere((m) => m?['role'] != 'user_file', orElse: () => null);
  List get members => (session?['members'] as List?) ?? [];
  Map? memberOf(int? no) => no == null ? null
    : members.cast<Map?>().firstWhere((m) => m?['member_no'] == no, orElse: () => null);
  Map? get typingMember {
    final messages = (session?['messages'] as List?) ?? [];
    final no = messages.isEmpty ? null : messages.last['member_no'] as int?;
    return memberOf(no) ?? (members.isEmpty ? null : members.first as Map);
  }
  @override void initState() {
    super.initState();
    if (widget.initial != null) {
      history = widget.initialHistory ?? [];
      WidgetsBinding.instance.addPostFrameCallback((_) => show(widget.initial!, jump: true));
    } else {
      refresh(withHistory: true);
    }
  }
  @override void dispose() {
    revealTimer?.cancel(); answer.dispose(); scrollController.dispose(); answerFocus.dispose(); super.dispose();
  }
  void scrollToLatest({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;
      animate ? scrollController.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
        : scrollController.jumpTo(0);
    });
  }
  void focusAnswer() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && session?['status'] == 'active') answerFocus.requestFocus();
  });
  Future<void> refresh({bool withHistory = false}) async {
    try {
      // 지난 대화가 필요하면 지금 대화와 동시에 요청한다.
      final known = session?['study_id'];
      final sessionRequest = Api.request('GET', '/sessions/$id');
      final historyRequest = withHistory && continuous && known != null
        ? Api.request('GET', '/studies/$known/history') : null;
      final data = await sessionRequest as Map<String, dynamic>;
      if (withHistory && continuous) {
        final items = await (historyRequest ?? Api.request('GET', '/studies/${data['study_id']}/history')) as List;
        history = items.map((e) => Map<String, dynamic>.from(e as Map)).where((e) => e['id'] != data['id']).toList();
      }
      await show(data, jump: withHistory);
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  /// 받은 대화를 그리고, 스터디원이 말할 차례면 다음 질문을 받아 온다.
  Future<void> show(Map<String, dynamic> data, {bool jump = false}) async {
    if (!mounted) return;
    setState(() => session = data);
    scrollToLatest(animate: !jump);
    final last = lastTalk?['role'];
    if (data['status'] == 'active' && data['kind'] != 'review' && !busy && (last == null ||
        (data['presentation'] != true && last == 'user'))) {
      await act('question');
    } else {
      focusAnswer();
      if (data['more'] == true && !busy) unawaited(followUp());
    }
  }
  /// 새로 온 말을 한 줄씩 보여 준다. 사용자가 말을 꺼내면 남은 줄을 바로 펼친다.
  void reveal(int before) {
    final messages = (session?['messages'] as List?) ?? [];
    revealTimer?.cancel();
    // 새로 온 친구들의 말 가운데 첫 줄만 바로 보여 준다.
    var fresh = 0;
    for (var i = messages.length - 1; i >= before; i--) {
      final role = '${messages[i]['role']}';
      if (!role.startsWith('assistant') && role != 'evaluation') break;
      fresh++;
    }
    hidden = (fresh - 1).clamp(0, 5).toInt();
    revealNext();
  }
  /// 앞사람 말을 읽을 틈을 두고, 다음 친구가 글자 수만큼 입력하는 시간을 보여 준 뒤 한 줄씩 펼친다.
  void revealNext() {
    composing = false;
    if (hidden <= 0) return;
    final messages = session!['messages'] as List;
    final at = messages.length - hidden;
    final read = 500 + (at > 0 ? '${messages[at - 1]['body']}'.length * 14 : 0);
    final write = 900 + '${messages[at]['body']}'.length * 26;
    revealTimer = Timer(Duration(milliseconds: read.clamp(700, 1600).toInt()), () {
      if (!mounted) return;
      setState(() => composing = true);
      scrollToLatest();
      revealTimer = Timer(Duration(milliseconds: write.clamp(1200, 3000).toInt()), () {
        if (!mounted) return;
        setState(() { hidden--; revealNext(); });
        scrollToLatest();
      });
    });
  }
  void revealAll() { revealTimer?.cancel(); hidden = 0; composing = false; }
  /// 정해진 다음 친구를 한 명씩 불러 이어 말하게 한다. 사용자가 말을 꺼내면 바로 멈춘다.
  Future<void> followUp() async {
    final token = actToken;
    bool alive() => mounted && token == actToken;
    while (alive() && session?['more'] == true && session?['status'] == 'active') {
      final messages = session!['messages'] as List;
      final read = messages.isEmpty ? 0 : '${messages.last['body']}'.length * 14;
      await Future<void>.delayed(Duration(milliseconds: (600 + read).clamp(800, 1700).toInt()));
      if (!alive()) return;
      setState(() => composing = true);
      scrollToLatest();
      final started = DateTime.now();
      Map<String, dynamic>? data;
      try { data = await Api.request('POST', '/sessions/$id/continue') as Map<String, dynamic>; } catch (_) {}
      // 너무 빨리 나오면 입력하는 시간만큼 더 기다린다.
      final wait = 1300 - DateTime.now().difference(started).inMilliseconds;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      if (!alive()) return;
      setState(() { composing = false; if (data != null) session = data; });
      scrollToLatest();
      if (data == null) return;
    }
  }
  bool get following => hidden > 0 || (session?['more'] == true && session?['status'] == 'active');
  Future<bool> act(String path, [Map<String, dynamic>? body]) async {
    final token = ++actToken;
    final before = ((session?['messages'] as List?) ?? []).length;
    setState(() { revealAll(); busy = true; busyAction = path; });
    scrollToLatest();
    try { final data = await Api.request('POST', '/sessions/$id/$path', body) as Map<String, dynamic>;
      // 기다리는 사이 사용자가 말을 꺼냈으면 늦게 온 응답은 버린다.
      if (mounted && token == actToken) { setState(() {
        session = data;
        if (path == 'answer') needsReview = false;
        if (path == 'question' || path == 'answer' || path == 'evaluate') reveal(before);
      }); scrollToLatest(); }
      return true;
    } catch (e) { if (mounted && token == actToken) errorMessage(context, e); return false; }
    finally {
      if (mounted && token == actToken) {
        setState(() { busy = false; busyAction = null; });
        if (path == 'question' || path == 'explain') focusAnswer();
        if (session?['more'] == true) unawaited(followUp());
      }
    }
  }
  /// 친구가 말하는 중에도 보낼 수 있다. 정리·평가·올리기처럼 멈출 수 없는 일만 기다린다.
  bool get canSend => !busy || const ['question', 'answer', 'explain', 'file-reply'].contains(busyAction);
  void sendAnswer() {
    final text = answer.text.trim();
    if (text.isEmpty || !canSend || session?['status'] != 'active') { answerFocus.requestFocus(); return; }
    setState(() { actToken += busy ? 0 : 1; pending.add(text); answer.clear(); revealAll(); });
    scrollToLatest();
    answerFocus.requestFocus();
    if (!pumping) pump();
  }
  /// 보낸 말을 차례로 전한다. 대답을 기다리는 동안 더 보낸 말은 모아서 한 번에 전한다.
  Future<void> pump() async {
    pumping = true;
    while (mounted && pending.isNotEmpty) {
      while (mounted && busy && busyAction != 'question') { await Future<void>.delayed(const Duration(milliseconds: 100)); }
      if (!mounted) return;
      final count = pending.length;
      final text = pending.join('\n');
      final saved = await act('answer', {'text': text, 'needs_review': needsReview});
      if (!mounted) return;
      setState(() => pending.removeRange(0, count));
      if (!saved) {
        final rest = [text, ...pending, if (answer.text.isNotEmpty) answer.text].join('\n');
        setState(() { pending.clear(); answer.text = rest; });
        break;
      }
      // 발표 중이거나 복습을 이어 가는 중이면 새 이야기를 꺼내지 않는다.
      final last = lastTalk?['role'];
      if (pending.isEmpty && session?['presentation'] != true && session?['kind'] != 'review' && last != 'assistant' && session?['turn_done'] != true) {
        unawaited(act('question'));
      }
    }
    pumping = false;
  }
  /// 파일을 차례로 올린다. 친구가 말하는 중이면 끝난 뒤에 올린다.
  Future<void> attachFiles(List<PickedFile> files) async {
    if (session == null || session!['status'] != 'active') return;
    setState(() { uploads.addAll(files); revealAll(); });
    scrollToLatest();
    if (draining) return;
    draining = true;
    var sent = false;
    while (mounted && uploads.isNotEmpty) {
      while (mounted && busy) { await Future<void>.delayed(const Duration(milliseconds: 150)); }
      if (!mounted) return;
      final file = uploads.first;
      setState(() => busy = true);
      try {
        final data = await Api.attachFile(id, file) as Map<String, dynamic>;
        sent = true;
        if (mounted) setState(() => session = data);
      } catch (e) { if (mounted) errorMessage(context, e); }
      if (mounted) setState(() { uploads.remove(file); busy = false; });
      scrollToLatest();
    }
    draining = false;
    if (mounted && sent && !presenting && pending.isEmpty) await act('file-reply');
    focusAnswer();
  }
  Future<void> showFile(int sessionId, Map file) async {
    try {
      final data = await Api.request('GET', '/sessions/$sessionId/files/${file['id']}');
      if (!mounted) return;
      await showAdaptiveSheet(context, (sheetContext) => ListView(shrinkWrap: true, children: [
        Text('${data['name']}', style: Theme.of(sheetContext).textTheme.titleMedium),
        const SizedBox(height: 14),
        SelectableText('${data['text']}', style: const TextStyle(height: 1.5)),
      ]));
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  /// 교안을 추가하거나 바꾼다.
  Future<void> attachPdf() async {
    final files = await pickFiles(context, multiple: false);
    if (files.isEmpty || !mounted) return;
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
      await Api.uploadPdf(session!['study_id'] as int, files.first);
      if (mounted) { setState(() => busy = false); await refresh(); }
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
      LearningJourneyPage(studyId: session!['study_id'] as int, onReview: openReview)));
    if (mounted && !busy) await refresh();
  }
  /// AI 스터디원 프로필(이름·학습 단계·모양) 바꾸기.
  Future<void> editMember(Map member) async {
    final role = peerRole(member);
    final edit = await showProfileEditor(context, title: memberName(member),
      subtitle: peerRoleLabels[role],
      name: memberName(member), avatar: memberAvatar(member), nameMax: 12, level: '${member['level']}');
    if (edit == null || !mounted) return;
    try {
      await Api.request('PUT', '/studies/${session!['study_id']}/members/${member['member_no']}',
        {'name': edit.name, 'level': edit.level, 'avatar': edit.avatar.code});
      await refresh();
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  /// 채팅으로 정한 진행 방식(예: 예시 위주, 짧게).
  List get preferences => (session?['preferences'] as List?) ?? [];
  Future<void> removePreference(String item) async {
    try {
      await Api.request('PUT', '/studies/${session!['study_id']}/preferences',
        {'items': [for (final p in preferences) if ('$p' != item) '$p']});
      await refresh();
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  Future<void> editRoom() async {
    final s = session!;
    final edit = await showProfileEditor(context, title: '채팅방 프로필', name: roomTitle,
      avatar: roomAvatar({'id': s['study_id'], 'avatar': s['study_avatar']}), nameMax: 120);
    if (edit == null || !mounted) return;
    try {
      await Api.request('PUT', '/studies/${s['study_id']}/details', {'title': edit.name, 'avatar': edit.avatar.code});
      await refresh();
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  String get roomTitle => '${session?['study_title'] ?? widget.studyTitle ?? ''}';
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
  void applyRoom(Map<String, dynamic> data) {
    session = Map<String, dynamic>.from(data['session'] as Map);
    history = [for (final h in data['history'] as List) Map<String, dynamic>.from(h as Map)];
  }
  /// 다시 볼 내용을 이 채팅방의 질문으로 이어 간다.
  Future<void> openReview(int reviewId) async {
    while (mounted && busy) { await Future<void>.delayed(const Duration(milliseconds: 150)); }
    if (!mounted) return;
    try {
      final data = await Api.request('POST', '/studies/${session!['study_id']}/reviews/$reviewId/chat') as Map<String, dynamic>;
      if (mounted) { setState(() => applyRoom(data)); scrollToLatest(); focusAnswer(); }
    } catch (e) { if (mounted) errorMessage(context, e); }
  }
  /// 이번 주를 마친다: 채팅 안에 정리가 올라오고, 화면을 바꾸지 않고 다음 주차로 이어 간다.
  Future<void> finish() async {
    final s = session!;
    final review = s['kind'] == 'review';
    final hasNext = !review && (s['week_no'] as int) < (s['total_weeks'] as int);
    if (!review) {
      final talk = s['messages'] as List;
      int count(String role) => talk.where((m) => m['role'] == role).length;
      final ok = await showAdaptiveSheet<bool>(context, (sheetContext) => FinishSheet(session: s,
        said: count('user') - count('assistant_plan'), files: count('user_file'),
        reviews: ((s['unanswered'] as List?) ?? []).length));
      if (ok != true || !mounted || busy) return;
    }
    freshId = id;
    final saved = await act('finish', {'revised_note': ''});
    if (!saved || !mounted || !continuous || !(hasNext || review)) return;
    // 정리를 읽을 틈을 두고 다음 주차를 이어 붙인다.
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (mounted) await openRoom();
  }
  Future<void> openRoom({bool restart = false}) async {
    setState(() => busy = true);
    Map<String, dynamic>? data;
    try {
      data = await Api.request('POST', '/studies/${session!['study_id']}/room${restart ? '?restart=true' : ''}') as Map<String, dynamic>;
    } catch (e) { if (mounted) errorMessage(context, e); }
    if (!mounted) return;
    setState(() { busy = false; if (data != null) { applyRoom(data); } else { freshId = null; } });
    if (data != null) await show(session!);
  }

  List<Widget> sessionBlock(Map<String, dynamic> s) {
    final messages = (s['messages'] as List?) ?? [];
    final finished = s['status'] != 'active';
    final sid = s['id'] as int;
    final out = <Widget>[if (s['kind'] != 'review') WeekDivider(session: s)];
    String? lastSpeaker;
    void add(String speaker, Widget Function(bool grouped) build) {
      out.add(build(lastSpeaker == speaker));
      lastSpeaker = speaker;
    }
    if ((s['initial_note'] as String? ?? '').isNotEmpty) {
      add('me', (g) => ChatBubble(name: '나', text: s['initial_note'], mine: true, grouped: g));
    }
    final shown = sid == session?['id'] ? messages.take(messages.length - hidden) : messages;
    for (final m in shown) {
      if (m['role'] == 'user_file') {
        final file = m['file'] as Map?;
        out.add(FileBubble(name: '${file?['name'] ?? m['body']}', size: file?['size'] as int? ?? 0,
          onTap: file == null ? null : () => showFile(sid, file)));
        lastSpeaker = null;
        continue;
      }
      if (m['role'] == 'evaluation') {
        out.add(EvaluationCard(summary: '${m['body']}', data: (m['data'] as Map?) ?? {}));
        lastSpeaker = null;
        continue;
      }
      final mine = m['role'] == 'user';
      final peer = mine ? null : memberOf(m['member_no'] as int?);
      final tag = m['role'] == 'assistant_hint' ? ' · 힌트' : m['role'] == 'assistant_plan' && (m['data'] as Map?)?['aside'] != true ? ' · 계획 반영' : '';
      add(mine ? 'me' : 'peer${m['member_no']}$tag', (g) => ChatBubble(
        name: mine ? '나' : '${peer == null ? 'AI 친구' : memberName(peer)}$tag',
        text: '${m['body']}', mine: mine, member: peer, grouped: g,
        lead: m['review_id'] != null && m['role'] == 'assistant' ? '다시 볼 내용' : null,
        note: (m['data'] as Map?)?['review_done'] == true ? '복습 완료' : null,
        caption: m['page_no'] == null ? null : '교안 ${m['page_no']}쪽',
        onCaptionTap: m['page_no'] == null ? null : () => showSource(sid, m['id'] as int)));
    }
    if (finished) {
      if ((s['revised_note'] as String? ?? '').isNotEmpty) {
        add('me', (g) => ChatBubble(name: '나', text: s['revised_note'], mine: true, grouped: g));
      }
      out.add(StudySummaryCard(key: ValueKey('summary$sid'), session: s, fresh: sid == freshId));
    }
    return out;
  }
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
        InkWell(onTap: busy ? null : () { close(); editRoom(); }, child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 16, 4), child: Row(children: [
            ProfileAvatar(roomAvatar({'id': s['study_id'], 'avatar': s['study_avatar']}), size: 52, soft: true),
            const SizedBox(width: 14),
            Expanded(child: Text(roomTitle, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            const Icon(Icons.edit_outlined, size: 18, color: mutedInk),
          ]))),
        InfoSection(title: '이번 주', children: [
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: brandSoft, borderRadius: BorderRadius.circular(8)),
              child: Text('${s['week_no']}/${s['total_weeks']}주차',
                style: const TextStyle(fontSize: 12, color: brand, fontWeight: FontWeight.w700))),
            const SizedBox(width: 8),
            Expanded(child: Text('${week['title']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          ]),
          if ('${week['scope']}'.trim() != '${week['title']}'.trim()) ...[
            const SizedBox(height: 8),
            Text('${week['scope']}', style: const TextStyle(height: 1.5, color: subInk)),
          ],
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.event_outlined, size: 16, color: mutedInk), const SizedBox(width: 6),
            Text('모임 ${friendlyDate('${week['meeting_date']}')}', style: const TextStyle(fontSize: 13, color: mutedInk)),
          ]),
        ]),
        InfoSection(title: '스터디원 ${members.length + 1}', children: [
          for (final m in members) InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: busy ? null : () => editMember(m as Map),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
              PeerAvatar(m as Map, size: 38), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(memberName(m), style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${memberRoleLabel(m)} · ${m['level']}', style: const TextStyle(fontSize: 12.5, color: mutedInk)),
              ])),
              const Icon(Icons.edit_outlined, size: 18, color: mutedInk),
            ]))),
          Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
            const MyAvatar(size: 38), const SizedBox(width: 12),
            Flexible(child: Text('${(Api.account?['user'] as Map?)?['name'] ?? ''} (나)', overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600))),
          ])),
        ]),
        if (preferences.isNotEmpty) InfoSection(title: '진행 방식', children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in preferences) InputChip(
              label: Text('$p', style: const TextStyle(fontSize: 12.5)),
              backgroundColor: brandSoft, side: BorderSide.none,
              deleteIcon: const Icon(Icons.close_rounded, size: 16), deleteButtonTooltipMessage: '지우기',
              onDeleted: busy ? null : () => removePreference('$p')),
          ]),
        ]),
        InfoSection(title: '교안', children: [
          InkWell(onTap: busy ? null : () { close(); attachPdf(); }, borderRadius: BorderRadius.circular(12),
            child: Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: lineColor), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(hasPdf ? Icons.description_rounded : Icons.upload_file_rounded,
                  color: hasPdf ? brand : mutedInk),
                const SizedBox(width: 10),
                Expanded(child: Text(hasPdf ? '${s['pdf_name']} · ${s['page_count']}쪽' : '교안 추가',
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(hasPdf ? '교체' : '추가', style: const TextStyle(color: brand, fontWeight: FontWeight.w600, fontSize: 13)),
              ]))),
        ]),
        if (review.isNotEmpty) InfoSection(title: '복습할 내용', children: [
          ...review.map((r) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 3), child: Icon(Icons.bookmark_rounded, size: 14, color: brand)),
              const SizedBox(width: 6),
              Expanded(child: Text('$r', style: const TextStyle(height: 1.45, fontSize: 13.5))),
            ]))),
        ]),
        InfoSection(title: '설정', children: [
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
  /// Enter는 전송, Shift+Enter는 줄바꿈. 한글 조합 중의 Enter는 [enterToSend]가 처리한다.
  DateTime? shiftEnterAt;
  KeyEventResult onAnswerKey(FocusNode node, KeyEvent event) {
    final enter = event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!enter || event is KeyUpEvent) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) {
      shiftEnterAt = DateTime.now();
      return KeyEventResult.ignored; // 줄바꿈은 입력창에 맡긴다.
    }
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (event is! KeyDownEvent || answer.value.composing.isValid) return KeyEventResult.ignored;
    sendAnswer();
    return KeyEventResult.handled;
  }
  /// 한글 조합이 Enter로 끝나면 키 이벤트 없이 줄바꿈만 들어오므로, 그 줄바꿈을 전송으로 바꾼다.
  /// Shift 키가 없는 휴대폰에서는 줄바꿈을 그대로 둔다.
  late final enterToSend = TextInputFormatter.withFunction((before, after) {
    final phone = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
    final at = after.selection.baseOffset - 1;
    final shifted = shiftEnterAt != null && DateTime.now().difference(shiftEnterAt!).inMilliseconds < 500;
    if (phone || shifted || HardwareKeyboard.instance.isShiftPressed || at < 0 || after.text[at] != '\n') return after;
    final text = after.text.replaceRange(at, at + 1, '');
    if (text != before.text) return after; // 붙여넣기처럼 줄바꿈 하나만 늘어난 것이 아니면 그대로 둔다.
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) sendAnswer(); });
    WidgetsBinding.instance.ensureVisualUpdate();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: at));
  });
  Widget composer(Map<String, dynamic> s, List messages, bool awaiting, bool finished) {
    if (finished) {
      if (busy || busyAction != null || (continuous && freshId == id && (s['week_no'] as int) < (s['total_weeks'] as int))) {
        return const SizedBox(height: 48);
      }
      return FilledButton(onPressed: continuous ? () => openRoom(restart: s['kind'] != 'review') : () => Navigator.pop(context),
        child: Text(!continuous ? '돌아가기' : s['presentation'] == true ? '다시 발표하기' : '이어서 이야기하기'));
    }
    final review = s['kind'] == 'review';
    final canHint = awaiting && !review && lastTalk?['role'] == 'assistant' && lastTalk?['review_id'] == null;
    final spoke = messages.any((m) => '${m['role']}'.startsWith('user'));
    final canFinish = !(busy || following || pending.isNotEmpty || uploads.isNotEmpty || (presenting ? !spoke : messages.isEmpty));
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        if (canHint) Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(
          avatar: const Icon(Icons.lightbulb_outline, size: 16), label: const Text('힌트'),
          onPressed: busy ? null : () => act('explain'))),
        if (awaiting && lastTalk?['review_id'] == null) Padding(padding: const EdgeInsets.only(right: 8), child: FilterChip(
          avatar: needsReview ? null : const Icon(Icons.bookmark_border, size: 16),
          label: const Text('복습에 추가'), selected: needsReview,
          onSelected: busy ? null : (v) => setState(() => needsReview = v))),
        if (!awaiting && !busy && !following && !review && s['presentation'] != true) Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(
          avatar: const Icon(Icons.refresh_rounded, size: 16), label: const Text('이야기 이어가기'),
          onPressed: () => act('question'))),
      ]))),
        const SizedBox(width: 8),
        FinishButton(
          label: review ? '복습 마치기' : presenting ? '피드백 받기' : s['presentation'] == true ? '스터디 마치기' : '${s['week_no']}주차 마치기',
          icon: presenting && !review ? Icons.campaign_rounded : Icons.flag_rounded,
          onPressed: !canFinish ? null : presenting && !review ? () => act('evaluate') : finish),
      ]),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.fromLTRB(4, 4, 5, 4),
        decoration: BoxDecoration(color: const Color(0xFFF4F5F7), borderRadius: BorderRadius.circular(26)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Padding(padding: const EdgeInsets.only(bottom: 2), child: IconButton(tooltip: '파일 첨부',
            icon: const Icon(Icons.attach_file_rounded, size: 21, color: subInk),
            onPressed: () async { final files = await pickFiles(context); if (files.isNotEmpty && mounted) attachFiles(files); })),
          Expanded(child: Focus(onKeyEvent: onAnswerKey, child: TextField(controller: answer, focusNode: answerFocus,
            inputFormatters: [enterToSend], minLines: 1, maxLines: 5, keyboardType: TextInputType.multiline,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(hintText: presenting ? '발표 내용 쓰기' : '메시지 보내기', filled: false, isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none)))),
          const SizedBox(width: 6),
          Padding(padding: const EdgeInsets.only(bottom: 2), child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: answer, builder: (context, value, _) => IconButton.filled(
            onPressed: !canSend || value.text.trim().isEmpty ? null : sendAnswer,
            style: IconButton.styleFrom(backgroundColor: brand, foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFD9DBE0), disabledForegroundColor: Colors.white,
              minimumSize: const Size(40, 40)),
            icon: const Icon(Icons.arrow_upward_rounded, size: 20), tooltip: '보내기'))),
        ])),
    ]);
  }
  /// 최근 말부터 거꾸로 그리는 목록. 보이는 말풍선만 만들어 대화가 길어져도 끊기지 않는다.
  Widget chatList(Map<String, dynamic> s, bool wide, bool typing) {
    final items = <Widget>[
      for (final past in history) ...sessionBlock(past),
      ...sessionBlock(s),
      for (final text in pending) ChatBubble(name: '나', text: text, mine: true),
      for (final f in uploads) FileBubble(name: f.name, size: f.bytes.length, uploading: true),
      if (typing) TypingBubble(member: hidden > 0
        ? memberOf((s['messages'] as List)[(s['messages'] as List).length - hidden]['member_no'] as int?) : composing ? memberOf(s['next_speaker'] as int?) : typingMember),
      if (busyAction == 'finish' && s['kind'] != 'review') SummarySkeleton(weekNo: s['week_no'] as int),
      if (busyAction == 'evaluate') const WorkingNote('발표를 되짚어 보고 있어요'),
      const SizedBox(height: 16),
    ];
    return Align(alignment: Alignment.topCenter, child: ListView.builder(
      controller: scrollController, reverse: true, itemCount: items.length,
      padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 14, vertical: 8),
      itemBuilder: (context, i) => Center(heightFactor: 1, child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: chatMaxWidth),
        child: SizedBox(width: double.infinity, child: items[items.length - 1 - i])))));
  }
  @override Widget build(BuildContext context) {
    final s = session;
    final messages = (s?['messages'] as List?) ?? [];
    final awaiting = hidden == 0 && (lastTalk?['role'] == 'assistant' || lastTalk?['role'] == 'assistant_hint');
    final finished = s != null && s['status'] != 'active';
    final thinking = busyAction == 'question' || busyAction == 'answer' || busyAction == 'explain'
      || busyAction == 'file-reply' || (s != null && !finished && messages.isEmpty);
    // 발표 중에는 내 말을 저장만 하므로 친구가 쓰는 중 표시를 띄우지 않는다.
    final typing = hidden > 0 || composing ? composing : thinking && !(presenting && busyAction == 'answer' && messages.isNotEmpty);
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
    final chat = s == null ? const Center(child: CircularProgressIndicator()) : Column(children: [
        Expanded(child: chatList(s, wide, typing)),
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
          if (s != null) ...[MemberStack(members: (s['members'] as List?) ?? []), const SizedBox(width: 10)],
          Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(roomTitle.isEmpty ? '${s?['week_no'] ?? ''}주차' : roomTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          if (s != null) Text('${s['week_no']}/${s['total_weeks']}주차 · ${(s['week'] as Map)['title']}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: mutedInk)),
        ]))]))),
      body: FileDropArea(enabled: s != null && !finished, onFiles: attachFiles, child: Row(children: [
        Expanded(child: chat),
        if (sideOpen) Container(width: 320,
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: lineColor))),
          child: roomInfoPanel(asDrawer: false)),
      ])));
  }
}
