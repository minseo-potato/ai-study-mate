import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// 브라우저 창에 파일을 끌어다 놓는 동작을 알려 준다. 돌려준 함수를 부르면 그만 듣는다.
void Function() listenFileDrop({
  required void Function(bool hovering) onHover,
  required void Function(List<({String name, int size, Future<Uint8List> Function() read})> files) onDrop,
}) {
  bool hasFiles(web.DragEvent e) => e.dataTransfer?.types.toDart.any((t) => t.toDart == 'Files') ?? false;
  var hovering = false;
  Timer? leave;
  void hover(bool value) {
    leave?.cancel();
    if (hovering != value) { hovering = value; onHover(value); }
  }
  void over(web.DragEvent e) {
    if (!hasFiles(e)) return;
    e.preventDefault();
    hover(true);
  }
  void left(web.DragEvent e) {
    // 화면 안의 다른 요소로 넘어갈 때도 불리므로, 곧바로 dragover가 다시 오면 취소된다.
    leave?.cancel();
    leave = Timer(const Duration(milliseconds: 120), () => hover(false));
  }
  void drop(web.DragEvent e) {
    if (!hasFiles(e)) return;
    e.preventDefault();
    hover(false);
    final list = e.dataTransfer!.files;
    final out = <({String name, int size, Future<Uint8List> Function() read})>[];
    for (var i = 0; i < list.length; i++) {
      final file = list.item(i)!;
      out.add((name: file.name, size: file.size,
        read: () async => (await file.arrayBuffer().toDart).toDart.asUint8List()));
    }
    if (out.isNotEmpty) onDrop(out);
  }
  final handlers = {'dragenter': over.toJS, 'dragover': over.toJS, 'dragleave': left.toJS, 'drop': drop.toJS};
  handlers.forEach((type, f) => web.window.addEventListener(type, f));
  return () {
    leave?.cancel();
    handlers.forEach((type, f) => web.window.removeEventListener(type, f));
  };
}
