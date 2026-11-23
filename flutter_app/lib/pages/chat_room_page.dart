import 'package:flutter/material.dart';
import '../api.dart';
import 'session_page.dart';

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
