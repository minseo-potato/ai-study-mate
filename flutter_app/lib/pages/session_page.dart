import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/chat.dart';
import 'study_page.dart';
import 'learning_journey_page.dart';

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
  int get typingPeer {
    final messages = (session?['messages'] as List?) ?? [];
    return messages.isEmpty ? 1 : (messages.last['member_no'] as int? ?? 1);
  }
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
    final items = await Api.request('GET', '/studies/$studyId/history') as List<dynamic>;
    if (mounted) {
      setState(() => history = items.map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) => e['id'] != widget.id).toList());
    }
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

  List<Widget> sessionBlock(Map<String, dynamic> s) {
    final messages = (s['messages'] as List?) ?? [];
    final finished = s['status'] != 'active';
    final sid = s['id'] as int;
    final out = <Widget>[WeekDivider(session: s)];
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
      out.add(StudySummaryCard(session: s));
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
        InfoSection(title: '이번 주', children: [
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
        InfoSection(title: '스터디원 ${members.length + 1}', children: [
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
        InfoSection(title: '교안', children: [
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
            style: const TextStyle(fontSize: 15),
            decoration: const InputDecoration(hintText: '메시지 보내기', filled: false, isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
              border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none)))),
          const SizedBox(width: 6),
          Padding(padding: const EdgeInsets.only(bottom: 2), child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: answer, builder: (context, value, _) => IconButton.filled(
            onPressed: busy || value.text.trim().isEmpty ? null : sendAnswer,
            style: IconButton.styleFrom(backgroundColor: brand, foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFD9DBE0), disabledForegroundColor: Colors.white,
              minimumSize: const Size(40, 40)),
            icon: const Icon(Icons.arrow_upward_rounded, size: 20), tooltip: '보내기'))),
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
              if (thinking) TypingBubble(peer: typingPeer),
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
          if (s != null) ...[MemberStack(members: (s['members'] as List?) ?? []), const SizedBox(width: 10)],
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
