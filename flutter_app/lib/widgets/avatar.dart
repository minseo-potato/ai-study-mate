import 'package:flutter/material.dart';
import '../theme.dart';
import 'common.dart';

/// 프로필에 쓸 수 있는 아이콘. 서버에는 "키:색번호"(예: "book:3")로 저장한다.
const avatarIcons = <String, IconData>{
  'smile': Icons.sentiment_satisfied_alt_rounded,
  'idea': Icons.lightbulb_rounded,
  'puzzle': Icons.extension_rounded,
  'link': Icons.hub_rounded,
  'search': Icons.travel_explore_rounded,
  'book': Icons.menu_book_rounded,
  'school': Icons.school_rounded,
  'brain': Icons.psychology_rounded,
  'star': Icons.star_rounded,
  'heart': Icons.favorite_rounded,
  'bolt': Icons.bolt_rounded,
  'rocket': Icons.rocket_launch_rounded,
  'leaf': Icons.eco_rounded,
  'flower': Icons.local_florist_rounded,
  'sun': Icons.wb_sunny_rounded,
  'moon': Icons.nightlight_round,
  'music': Icons.music_note_rounded,
  'palette': Icons.palette_rounded,
  'pet': Icons.pets_rounded,
  'coffee': Icons.local_cafe_rounded,
};
const avatarColors = [
  brand, Color(0xFFFF7A45), Color(0xFF12B886), Color(0xFFF06595),
  Color(0xFFF59F00), Color(0xFF339AF0), Color(0xFF15AABF), Color(0xFF495057),
];

class AvatarSpec {
  final String icon;
  final int color;
  const AvatarSpec(this.icon, this.color);
  /// 저장된 값이 비었거나 잘못됐으면 기본 모양을 쓴다.
  factory AvatarSpec.parse(Object? raw, AvatarSpec fallback) {
    final parts = '${raw ?? ''}'.split(':');
    if (parts.length != 2 || !avatarIcons.containsKey(parts[0])) return fallback;
    final color = int.tryParse(parts[1]);
    if (color == null || color < 0 || color >= avatarColors.length) return fallback;
    return AvatarSpec(parts[0], color);
  }
  String get code => '$icon:$color';
  Color get tone => avatarColors[color];
  IconData get glyph => avatarIcons[icon] ?? Icons.circle;
  AvatarSpec copyWith({String? icon, int? color}) => AvatarSpec(icon ?? this.icon, color ?? this.color);
}

const _roleIcons = ['idea', 'puzzle', 'link', 'search'];
AvatarSpec memberAvatar(Map member) {
  final role = peerRole(member);
  return AvatarSpec.parse(member['avatar'], AvatarSpec(_roleIcons[role], role + 1));
}
AvatarSpec roomAvatar(Map room) =>
  AvatarSpec.parse(room['avatar'], AvatarSpec('book', (room['id'] as int? ?? 0) % avatarColors.length));
AvatarSpec userAvatar(Map? user) => AvatarSpec.parse(user?['avatar'], const AvatarSpec('smile', 0));

/// 단순한 프로필: 색 동그라미에 흰 아이콘. soft는 연한 바탕의 둥근 사각형(채팅방 목록용).
class ProfileAvatar extends StatelessWidget {
  final AvatarSpec spec;
  final double size;
  final bool soft;
  const ProfileAvatar(this.spec, {super.key, this.size = 36, this.soft = false});
  @override Widget build(BuildContext context) {
    final tone = spec.tone;
    return Container(width: size, height: size, alignment: Alignment.center,
      decoration: soft
        ? BoxDecoration(color: tone.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(size * 0.36))
        : BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color.lerp(tone, Colors.white, 0.18)!, tone])),
      child: Icon(spec.glyph, size: size * (soft ? 0.5 : 0.54), color: soft ? tone : Colors.white));
  }
}

/// 색과 아이콘을 고르는 판.
class AvatarPicker extends StatelessWidget {
  final AvatarSpec value;
  final ValueChanged<AvatarSpec> onChanged;
  const AvatarPicker({super.key, required this.value, required this.onChanged});
  @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Wrap(spacing: 10, runSpacing: 10, children: [
      for (var i = 0; i < avatarColors.length; i++) GestureDetector(
        onTap: () => onChanged(value.copyWith(color: i)),
        child: Container(width: 30, height: 30,
          decoration: BoxDecoration(shape: BoxShape.circle, color: avatarColors[i],
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: value.color == i ? avatarColors[i] : Colors.transparent, spreadRadius: 2)]),
          child: value.color == i ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null)),
    ]),
    const SizedBox(height: 16),
    Wrap(spacing: 8, runSpacing: 8, children: [
      for (final entry in avatarIcons.entries) InkWell(
        onTap: () => onChanged(value.copyWith(icon: entry.key)),
        borderRadius: BorderRadius.circular(12),
        child: Container(width: 44, height: 44, alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
            color: value.icon == entry.key ? value.tone.withValues(alpha: 0.14) : pageBg,
            border: Border.all(color: value.icon == entry.key ? value.tone : Colors.transparent, width: 1.5)),
          child: Icon(entry.value, size: 22, color: value.icon == entry.key ? value.tone : subInk))),
    ]),
  ]);
}

class ProfileEdit {
  final String name;
  final AvatarSpec avatar;
  final String? level;
  const ProfileEdit(this.name, this.avatar, this.level);
}

/// 이름·프로필 모양(·학습 단계)을 한 시트에서 고친다. 취소하면 null.
Future<ProfileEdit?> showProfileEditor(BuildContext context, {
  required String title, required String name, required AvatarSpec avatar,
  int nameMax = 20, int nameMin = 1, String? subtitle, String? level,
}) async {
  final controller = TextEditingController(text: name);
  var spec = avatar;
  var chosenLevel = level;
  final result = await showAdaptiveSheet<ProfileEdit>(context, (sheetContext) => StatefulBuilder(
    builder: (sheetContext, setSheet) {
      final valid = controller.text.trim().length >= nameMin;
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Flexible(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4),
            child: Text(subtitle, style: const TextStyle(fontSize: 13, color: mutedInk))),
          const SizedBox(height: 16),
          Center(child: ProfileAvatar(spec, size: 64)),
          const SizedBox(height: 16),
          TextField(controller: controller, maxLength: nameMax, onChanged: (_) => setSheet(() {}),
            decoration: const InputDecoration(labelText: '이름')),
          if (chosenLevel != null) ...[
            const SizedBox(height: 4),
            const Text('학습 단계', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: subInk)),
            const SizedBox(height: 8),
            LevelPicker(value: chosenLevel!, onChanged: (v) => setSheet(() => chosenLevel = v)),
          ],
          const SizedBox(height: 18),
          const Text('프로필', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: subInk)),
          const SizedBox(height: 10),
          AvatarPicker(value: spec, onChanged: (v) => setSheet(() => spec = v)),
        ]))),
        // 저장 버튼은 내용이 길어도 항상 보이도록 스크롤 밖에 둔다.
        const SizedBox(height: 16),
        FilledButton(onPressed: valid
          ? () => Navigator.pop(sheetContext, ProfileEdit(controller.text.trim(), spec, chosenLevel)) : null,
          child: const Text('저장')),
      ]);
    }));
  controller.dispose();
  return result;
}
