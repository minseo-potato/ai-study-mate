import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import 'my_page.dart';
import 'records_page.dart';
import 'room_list_page.dart';

/// 로그인 뒤 홈: 채팅 · 기록 · 마이 탭. 휴대폰은 아래 탭, 넓은 화면은 왼쪽 탭.
class HomeShell extends StatefulWidget {
  final Map<String, dynamic> account;
  final Future<void> Function() onSignOut;
  const HomeShell({super.key, required this.account, required this.onSignOut});
  @override State<HomeShell> createState() => _HomeShellState();
}
class _HomeShellState extends State<HomeShell> {
  late Map<String, dynamic> account = widget.account;
  int tab = 0;
  /// 탭을 다시 열 때 기록·마이 화면이 새 데이터를 받도록 바꾸는 값.
  int recordsVersion = 0, myVersion = 0;

  Future<void> refreshAccount() async {
    try {
      final data = await Api.request('GET', '/me') as Map<String, dynamic>;
      if (mounted) setState(() => account = data);
    } catch (_) {}
  }

  /// 한 번이라도 연 탭만 만든다(앱을 켤 때 안 보는 탭의 데이터를 미리 받지 않도록).
  final visited = <int>{0};

  void select(int index) {
    setState(() {
      if (index == 1 && tab != 1) recordsVersion++;
      if (index == 2 && tab != 2) myVersion++;
      visited.add(index);
      tab = index;
    });
    if (index == 2) refreshAccount();
  }

  static const destinations = [
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, '채팅'),
    (Icons.bookmarks_outlined, Icons.bookmarks_rounded, '기록'),
    (Icons.person_outline_rounded, Icons.person_rounded, '마이'),
  ];

  @override Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
    final pages = IndexedStack(index: tab, children: [
      RoomListPage(demoMode: account['demo_mode'] == true, onChanged: refreshAccount),
      if (visited.contains(1)) RecordsPage(key: ValueKey('records$recordsVersion')) else const SizedBox.shrink(),
      if (visited.contains(2)) MyPage(key: ValueKey('my$myVersion'), account: account,
        onChanged: (data) => setState(() => account = data), onSignOut: widget.onSignOut)
      else const SizedBox.shrink(),
    ]);
    if (wide) {
      return Scaffold(body: Row(children: [
        NavigationRail(
          backgroundColor: Colors.white, selectedIndex: tab, onDestinationSelected: select,
          labelType: NavigationRailLabelType.all, indicatorColor: brandSoft, minWidth: 84,
          leading: Padding(padding: const EdgeInsets.fromLTRB(0, 16, 0, 20), child: Container(width: 40, height: 40,
            decoration: BoxDecoration(color: brand, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.forum_rounded, color: Colors.white, size: 22))),
          selectedLabelTextStyle: const TextStyle(fontFamily: 'NotoSansKR', fontSize: 12, fontWeight: FontWeight.w700, color: ink),
          unselectedLabelTextStyle: const TextStyle(fontFamily: 'NotoSansKR', fontSize: 12, color: mutedInk),
          destinations: [for (final d in destinations) NavigationRailDestination(
            icon: Icon(d.$1, color: mutedInk), selectedIcon: Icon(d.$2, color: brand), label: Text(d.$3))],
        ),
        const VerticalDivider(width: 1, thickness: 1, color: lineColor),
        Expanded(child: pages),
      ]));
    }
    return Scaffold(
      body: pages,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: lineColor))),
        child: NavigationBar(selectedIndex: tab, onDestinationSelected: select,
          destinations: [for (final d in destinations) NavigationDestination(
            icon: Icon(d.$1, color: mutedInk), selectedIcon: Icon(d.$2, color: brand), label: d.$3)])),
    );
  }
}
