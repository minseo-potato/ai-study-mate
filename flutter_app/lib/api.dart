import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/files.dart';

/// 서버 주소. 빌드할 때 --dart-define=API_BASE_URL=...로 정한다.
/// 정하지 않았으면, 배포된 웹에서는 같은 도메인의 /api를, 내 컴퓨터에서는 localhost:8000을 쓴다.
const _apiBaseSetting = String.fromEnvironment('API_BASE_URL');
final apiBase = _apiBaseSetting.isNotEmpty ? _apiBaseSetting.replaceFirst(RegExp(r'/+$'), '') : _defaultApiBase();

String _defaultApiBase() {
  const local = 'http://localhost:8000';
  if (!kIsWeb) return local;
  final host = Uri.base.host;
  final onMyComputer = host.isEmpty || host == 'localhost' || host == '127.0.0.1' || host == '[::1]';
  return onMyComputer ? local : '${Uri.base.origin}/api';
}

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
  /// 로그인한 내 계정 정보(/me 응답). 내 프로필을 그릴 때 쓴다.
  static Map<String, dynamic>? account;
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

  static Future<dynamic> create(Map<String, String> fields, PickedFile? pdf) {
    final request = http.MultipartRequest('POST', url('/studies'))..fields.addAll(fields);
    if (pdf != null) request.files.add(_filePart('pdf', pdf));
    return _send(request);
  }

  static Future<dynamic> uploadPdf(int studyId, PickedFile file) =>
    _send(http.MultipartRequest('PUT', url('/studies/$studyId/pdf'))..files.add(_filePart('pdf', file)));

  /// 교안 파일을 하나 더 붙인다. 새 쪽은 지금 교안 뒤에 이어진다.
  static Future<dynamic> addPdf(int studyId, PickedFile file) =>
    _send(http.MultipartRequest('POST', url('/studies/$studyId/pdf'))..files.add(_filePart('pdf', file)));

  static Future<dynamic> attachFile(int sessionId, PickedFile file) =>
    _send(http.MultipartRequest('POST', url('/sessions/$sessionId/files'))..files.add(_filePart('file', file)));

  static http.MultipartFile _filePart(String field, PickedFile file) =>
    http.MultipartFile.fromBytes(field, file.bytes, filename: file.name);

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
