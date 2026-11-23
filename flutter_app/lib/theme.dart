import 'package:flutter/material.dart';

const brand = Color(0xFF7C5CFC);
const brandSoft = Color(0xFFF1EDFF);
const ink = Color(0xFF191A1C);
const subInk = Color(0xFF5B5F68);
const mutedInk = Color(0xFF8B8F97);
const lineColor = Color(0xFFE9EAEE);
const pageBg = Color(0xFFF4F5F7);

const wideBreakpoint = 900.0;
const chatMaxWidth = 760.0;

/// AI 스터디원 역할. 서버의 perspective 값과 같은 순서다.
const peerRoles = ['개념과 정의', '예시와 적용', '앞 주차와의 연결', '다른 해석'];
const peerRoleLabels = ['개념 정리', '사례 찾기', '흐름 연결', '깊이 파기'];
const peerRoleIntros = [
  '용어와 원리를 정확하게 짚어요',
  '실제 예시로 바꿔 생각해요',
  '앞에서 배운 내용과 이어 줘요',
  '왜 그런지, 다른 경우는 없는지 파고들어요',
];
const peerDefaultNames = ['지식이', '사례이', '융합이', '탐구이'];
const peerAccents = [Color(0xFFFF7A45), Color(0xFF12B886), Color(0xFFF06595), Color(0xFFF59F00)];
const peerLevels = ['기초', '중급', '심화'];

int peerRole(Map member) {
  final role = peerRoles.indexOf('${member['perspective']}');
  return role >= 0 ? role : ((member['member_no'] as int? ?? 1) - 1) % peerRoles.length;
}
Color memberAccent(Map member) => peerAccents[peerRole(member)];
String memberName(Map member) {
  final name = '${member['name'] ?? ''}'.trim();
  return name.isEmpty ? peerDefaultNames[peerRole(member)] : name;
}
String memberRoleLabel(Map member) => peerRoleLabels[peerRole(member)];

/// 2026-12-13 → 12월 13일 (토)
String friendlyDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const days = ['월', '화', '수', '목', '금', '토', '일'];
  return '${d.month}월 ${d.day}일 (${days[d.weekday - 1]})';
}
