import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import 'common.dart';
import 'drop_stub.dart' if (dart.library.js_interop) 'drop_web.dart';

const fileTypes = ['pdf', 'docx', 'pptx', 'txt', 'md', 'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'];
const maxFileSize = 50 * 1024 * 1024;

/// 올릴 파일. 고르기와 끌어다 놓기가 같은 모양을 쓴다.
class PickedFile {
  final String name;
  final Uint8List bytes;
  const PickedFile(this.name, this.bytes);
}

String fileSizeLabel(int bytes) => bytes <= 0 ? ''
  : bytes < 1024 * 1024 ? '${(bytes / 1024).ceil()}KB' : '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';

String? fileProblem(String name, int size) {
  if (!fileTypes.contains(name.split('.').last.toLowerCase())) return 'PDF, DOCX, PPTX, TXT, MD, 이미지 파일을 올려 주세요.';
  if (size > maxFileSize) return '50MB 이하 파일만 올릴 수 있어요.';
  return null;
}

Future<List<PickedFile>> pickFiles(BuildContext context, {bool multiple = true}) async {
  final picked = await FilePicker.platform.pickFiles(type: FileType.custom,
    allowedExtensions: fileTypes, allowMultiple: multiple, withData: true);
  final out = <PickedFile>[];
  for (final f in picked?.files ?? const <PlatformFile>[]) {
    final problem = f.bytes == null ? '파일을 읽지 못했어요.' : fileProblem(f.name, f.size);
    if (problem == null) { out.add(PickedFile(f.name, f.bytes!)); }
    else if (context.mounted) { errorMessage(context, problem); }
  }
  return out;
}

/// 화면 어디에든 파일을 끌어다 놓을 수 있게 한다.
class FileDropArea extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final ValueChanged<List<PickedFile>> onFiles;
  const FileDropArea({super.key, required this.child, required this.onFiles, this.enabled = true});
  @override State<FileDropArea> createState() => _FileDropAreaState();
}
class _FileDropAreaState extends State<FileDropArea> {
  bool hovering = false;
  late final void Function() stop;
  /// 위에 다른 화면이나 대화상자가 떠 있으면 받지 않는다.
  bool get active => mounted && widget.enabled && (ModalRoute.of(context)?.isCurrent ?? true);
  @override void initState() {
    super.initState();
    stop = listenFileDrop(
      onHover: (value) { if (mounted) setState(() => hovering = value && active); },
      onDrop: receive);
  }
  @override void dispose() { stop(); super.dispose(); }
  Future<void> receive(List<({String name, int size, Future<Uint8List> Function() read})> files) async {
    if (!active) return;
    final out = <PickedFile>[];
    for (final f in files) {
      final problem = fileProblem(f.name, f.size);
      if (problem != null) { if (mounted) errorMessage(context, problem); continue; }
      try { out.add(PickedFile(f.name, await f.read())); }
      catch (_) { if (mounted) errorMessage(context, '파일을 읽지 못했어요.'); }
    }
    if (mounted && out.isNotEmpty) widget.onFiles(out);
  }
  @override Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        widget.child,
        if (hovering) IgnorePointer(child: Container(
          margin: const EdgeInsets.all(12), alignment: Alignment.center,
          decoration: BoxDecoration(color: brandSoft.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(18), border: Border.all(color: brand, width: 2)),
          child: const Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.upload_file_rounded, size: 40, color: brand),
            SizedBox(height: 10),
            Text('여기에 놓기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: brand)),
          ]))),
      ]);
}

/// 채팅에 남는 파일 첨부 기록.
class FileBubble extends StatelessWidget {
  final String name;
  final int size;
  final bool uploading;
  final VoidCallback? onTap;
  const FileBubble({super.key, required this.name, this.size = 0, this.uploading = false, this.onTap});
  @override Widget build(BuildContext context) {
    final kind = name.split('.').last.toUpperCase();
    return Align(alignment: Alignment.centerRight, child: Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(color: Colors.white, borderRadius: BorderRadius.circular(16), child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(16),
        child: Container(width: 260, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: lineColor)),
          child: Row(children: [
            Container(width: 42, height: 42, alignment: Alignment.center,
              decoration: BoxDecoration(color: brandSoft, borderRadius: BorderRadius.circular(12)),
              child: uploading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.description_rounded, color: brand, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink)),
              const SizedBox(height: 2),
              Text([kind, fileSizeLabel(size)].where((x) => x.isNotEmpty).join('  '),
                style: const TextStyle(fontSize: 12, color: mutedInk)),
            ])),
          ]))))));
  }
}
