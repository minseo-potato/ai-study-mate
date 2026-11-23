import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/common.dart';

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
