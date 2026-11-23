import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const apiBase = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');

/// 로그인이 풀렸을 때(서버가 401을 돌려줄 때) 던지는 오류.
class SignedOut implements Exception {
  final String message;
  SignedOut(this.message);
  @override String toString() => message;
}

/// 백엔드 호출. 연결 하나를 계속 재사용하고, 로그인 토큰을 자동으로 붙인다.
class Api {
  static final _client = http.Client();
  static const _tokenKey = 'auth_token';
  static String? token;
  /// 토큰이 만료되면 앱이 로그인 화면으로 돌아가도록 알린다.
  static void Function()? onSignedOut;

  static Uri url(String path) => Uri.parse('$apiBase$path');

  static Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_tokenKey);
  }
  static Future<void> saveToken(String? value) async {
    token = value;
    final prefs = await SharedPreferences.getInstance();
    value == null ? await prefs.remove(_tokenKey) : await prefs.setString(_tokenKey, value);
  }

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
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    final response = await _client.send(request);
    final text = await response.stream.bytesToString();
    if (response.statusCode >= 400) {
      dynamic detail;
      try { detail = jsonDecode(text)['detail']; } catch (_) { detail = text; }
      if (response.statusCode == 401 && !request.url.path.startsWith('/auth/')) {
        await saveToken(null);
        onSignedOut?.call();
        throw SignedOut('$detail');
      }
      throw Exception(detail is List ? '입력한 내용을 다시 확인해 주세요.' : detail);
    }
    return jsonDecode(text);
  }
}
