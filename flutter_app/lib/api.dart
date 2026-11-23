import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

const apiBase = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');

/// 백엔드 호출. 연결 하나를 계속 재사용하고, 오류 응답은 서버가 보낸 안내 문구로 바꿔 던진다.
class Api {
  static final _client = http.Client();
  static Uri url(String path) => Uri.parse('$apiBase$path');

  static Future<dynamic> request(String method, String path, [Map<String, dynamic>? body]) async {
    final request = http.Request(method, url(path));
    if (method != 'GET') {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body ?? {});
    }
    return _send(request);
  }

  static Future<dynamic> create(Map<String, String> fields, PlatformFile? pdf) {
    final request = http.MultipartRequest('POST', url('/studies'))..fields.addAll(fields);
    if (pdf != null) request.files.add(_pdfPart(pdf));
    return _send(request);
  }

  static Future<dynamic> uploadPdf(int studyId, PlatformFile pdf) =>
    _send(http.MultipartRequest('PUT', url('/studies/$studyId/pdf'))..files.add(_pdfPart(pdf)));

  static http.MultipartFile _pdfPart(PlatformFile pdf) =>
    http.MultipartFile.fromBytes('pdf', pdf.bytes!, filename: pdf.name);

  static Future<dynamic> _send(http.BaseRequest request) async {
    final response = await _client.send(request);
    final text = await response.stream.bytesToString();
    if (response.statusCode >= 400) {
      dynamic detail;
      try { detail = jsonDecode(text)['detail']; } catch (_) { detail = text; }
      throw Exception(detail);
    }
    return jsonDecode(text);
  }
}
