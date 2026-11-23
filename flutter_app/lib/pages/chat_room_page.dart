import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import 'session_page.dart';

/// 채팅방 페이지. 요청 한 번(POST /studies/{id}/room)으로 지금 대화와 지난 대화를 받아 연다.
/// 주차가 끝나면 같은 화면에서 다음 주차 대화로 바로 이어진다.
class ChatRoomPage extends StatefulWidget {
  final int studyId;
  final String title;
  const ChatRoomPage({super.key, required this.studyId, required this.title});
  @override State<ChatRoomPage> createState() => _ChatRoomPageState();
}
class _ChatRoomPageState extends State<ChatRoomPage> {
  Map<String, dynamic>? room;
  String? error;
  @override void initState() { super.initState(); open(); }
  Future<void> open() async {
    try {
      final data = await Api.request('POST', '/studies/${widget.studyId}/room') as Map<String, dynamic>;
      if (mounted) setState(() { room = data; error = null; });
    } catch (e) { if (mounted) setState(() => error = '$e'); }
  }
  @override Widget build(BuildContext context) {
    final data = room;
    if (data != null) {
      final session = Map<String, dynamic>.from(data['session'] as Map);
      return SessionPage(key: ValueKey(session['id']), id: session['id'] as int, studyTitle: widget.title,
        initial: session,
        initialHistory: [for (final h in data['history'] as List) Map<String, dynamic>.from(h as Map)],
        onFinished: open);
    }
    return Scaffold(backgroundColor: pageBg, appBar: AppBar(title: Text(widget.title)),
      body: Center(child: error == null ? const CircularProgressIndicator()
        : Column(mainAxisSize: MainAxisSize.min, children: [
            Text(error!), TextButton(onPressed: open, child: const Text('다시 시도'))])));
  }
}
