import 'dart:typed_data';

/// 끌어다 놓기가 없는 기기(휴대폰)에서는 아무것도 하지 않는다.
void Function() listenFileDrop({
  required void Function(bool hovering) onHover,
  required void Function(List<({String name, int size, Future<Uint8List> Function() read})> files) onDrop,
}) => () {};
