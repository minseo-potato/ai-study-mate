import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/chat.dart';
import '../widgets/common.dart';

/// 새 스터디 만들기. 주제만 적으면 바로 시작할 수 있고, 나머지는 눌러서 고르는 값만 둔다.
class CreatePage extends StatefulWidget {
  const CreatePage({super.key});
  @override State<CreatePage> createState() => _CreatePageState();
}

class _Friend {
  final int role;
  String name;
  String level;
  bool joined;
  String avatar = '';
  _Friend(this.role, this.level, {this.joined = true}) : name = peerDefaultNames[role];
  Map<String, dynamic> get asMember =>
    {'perspective': peerRoles[role], 'name': name, 'member_no': role + 1, 'avatar': avatar};
}

class _CreatePageState extends State<CreatePage> {
  final title = TextEditingController();
  final friends = [_Friend(0, '기초'), _Friend(1, '중급'), _Friend(2, '심화'), _Friend(3, '중급', joined: false)];
  static const weekChoices = [2, 4, 6, 8, 12];
  int weeks = 4;
  DateTime start = DateTime.now();
  PlatformFile? pdf;
  bool busy = false;
  @override void dispose() { title.dispose(); super.dispose(); }

  bool get canSubmit => title.text.trim().isNotEmpty && friends.any((f) => f.joined) && !busy;

  Future<void> pickPdf() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (picked == null || !mounted) return;
    final file = picked.files.single;
    if (file.size > 10000000) { errorMessage(context, '10MB 이하의 PDF를 선택해 주세요.'); return; }
    setState(() => pdf = file);
  }

  Future<void> pickStart() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: start,
      firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 2));
    if (d != null) setState(() => start = d);
  }

  Future<void> rename(_Friend friend) async {
    final edit = await showProfileEditor(context, title: 'AI 친구 프로필',
      subtitle: '${peerRoleLabels[friend.role]} · ${peerRoleIntros[friend.role]}',
      name: friend.name, avatar: memberAvatar(friend.asMember), nameMax: 12);
    if (edit != null) setState(() { friend.name = edit.name; friend.avatar = edit.avatar.code; });
  }

  Future<void> submit() async {
    if (!canSubmit) return;
    setState(() => busy = true);
    try {
      final joined = friends.where((f) => f.joined).toList();
      final date = '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
      final study = await Api.create({
        'title': title.text.trim(), 'start_date': date, 'weeks': '$weeks',
        'member_count': '${joined.length}',
        'member_profiles': jsonEncode([for (final f in joined) {'role': f.role, 'name': f.name, 'level': f.level, 'avatar': f.avatar}]),
      }, pdf);
      if (mounted) Navigator.pop(context, study['id']);
    } catch (e) { if (mounted) errorMessage(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Widget label(String text) => Padding(padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
    child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: subInk)));

  Widget friendCard(_Friend f) => AnimatedContainer(
    duration: const Duration(milliseconds: 150),
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: f.joined ? memberAccent(f.asMember).withValues(alpha: 0.5) : lineColor)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        GestureDetector(onTap: () => rename(f),
          child: Opacity(opacity: f.joined ? 1 : 0.4, child: PeerAvatar(f.asMember, size: 42))),
        const SizedBox(width: 12),
        Expanded(child: InkWell(onTap: () => rename(f), borderRadius: BorderRadius.circular(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: f.joined ? ink : mutedInk))),
              const SizedBox(width: 4),
              const Icon(Icons.edit_outlined, size: 14, color: mutedInk),
              const SizedBox(width: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: memberAccent(f.asMember).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6)),
                child: Text(peerRoleLabels[f.role], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: memberAccent(f.asMember)))),
            ]),
            const SizedBox(height: 3),
            Text(peerRoleIntros[f.role], maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: mutedInk)),
          ]))),
        Switch(value: f.joined, onChanged: (v) => setState(() => f.joined = v)),
      ]),
      if (f.joined) Padding(padding: const EdgeInsets.fromLTRB(0, 10, 6, 0),
        child: LevelPicker(value: f.level, onChanged: (v) => setState(() => f.level = v))),
    ]));

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('새 스터디')),
    body: Column(children: [
      Expanded(child: PageContent(children: [
        const Padding(padding: EdgeInsets.fromLTRB(4, 12, 4, 14),
          child: Text('무엇을 함께 공부할까요?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: ink))),
        TextField(controller: title, autofocus: true, maxLength: 120,
          textInputAction: TextInputAction.done, onChanged: (_) => setState(() {}),
          onSubmitted: (_) => submit(),
          decoration: const InputDecoration(hintText: '예: 신경망 기초, 토익 문법, 운영체제', counterText: '')),
        const SizedBox(height: 10),
        Material(color: Colors.white, borderRadius: BorderRadius.circular(14), child: InkWell(
          onTap: busy ? null : pickPdf, borderRadius: BorderRadius.circular(14),
          child: Container(padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE1E3E8))),
            child: Row(children: [
              Icon(pdf == null ? Icons.upload_file_rounded : Icons.picture_as_pdf_rounded,
                color: pdf == null ? mutedInk : const Color(0xFFE03131)),
              const SizedBox(width: 12),
              Expanded(child: Text(pdf?.name ?? '교안 PDF 올리기 (선택)', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: pdf == null ? mutedInk : ink))),
              if (pdf != null) IconButton(tooltip: 'PDF 빼기', icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: busy ? null : () => setState(() => pdf = null))
              else const SizedBox(height: 24),
            ])))),
        label('기간'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final w in weekChoices) ChoiceChip(
            label: Text('$w주'), selected: weeks == w, showCheckmark: false,
            labelStyle: TextStyle(fontFamily: 'NotoSansKR', fontSize: 14,
              fontWeight: weeks == w ? FontWeight.w700 : FontWeight.w500, color: weeks == w ? brand : subInk),
            side: BorderSide(color: weeks == w ? brand : const Color(0xFFE1E3E8)),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            onSelected: (_) => setState(() => weeks = w)),
        ]),
        const SizedBox(height: 12),
        Material(color: Colors.white, borderRadius: BorderRadius.circular(14), child: InkWell(
          onTap: pickStart, borderRadius: BorderRadius.circular(14),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE1E3E8))),
            child: Row(children: [
              const Icon(Icons.event_outlined, color: mutedInk), const SizedBox(width: 12),
              const Text('시작일', style: TextStyle(color: subInk)),
              const Spacer(),
              Text(friendlyDate(start.toIso8601String().substring(0, 10)),
                style: const TextStyle(fontWeight: FontWeight.w600, color: ink)),
              const SizedBox(width: 4), const Icon(Icons.chevron_right_rounded, color: mutedInk),
            ])))),
        label('함께할 AI 친구'),
        ...friends.map(friendCard),
      ])),
      Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: lineColor))),
        child: SafeArea(top: false, child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: SizedBox(width: double.infinity, child: FilledButton(onPressed: canSubmit ? submit : null,
              child: Text(busy ? '만드는 중...' : '시작하기')))))))),
    ]),
  );
}
