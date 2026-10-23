import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  ApiException(this.status, this.code, this.message);

  bool get isNetwork => status == 0;

  @override
  String toString() => message;
}

/// Tokens live in the platform keystore (Android Keystore-backed), never in plain prefs.
class TokenStore {
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  String? accessToken;
  String? refreshToken;

  Future<void> load() async {
    accessToken = await _storage.read(key: 'access_token');
    refreshToken = await _storage.read(key: 'refresh_token');
  }

  Future<void> save(String access, String refresh) async {
    accessToken = access;
    refreshToken = refresh;
    await _storage.write(key: 'access_token', value: access);
    await _storage.write(key: 'refresh_token', value: refresh);
  }

  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }
}

class UploadFile {
  final String field;
  final String path;
  UploadFile(this.field, this.path);
}

class ApiClient {
  ApiClient(this.tokens);

  final TokenStore tokens;
  final http.Client _http = http.Client();
  Completer<bool>? _refreshing;

  /// Called when the session can't be refreshed (forces the app back to login).
  void Function()? onSessionExpired;

  static const _timeout = Duration(seconds: 20);

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && v.toString().isNotEmpty) q[k] = v.toString();
    });
    return Uri.parse('${AppConfig.apiRoot}$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (tokens.accessToken != null) 'Authorization': 'Bearer ${tokens.accessToken}',
      };

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _http.get(_uri(path, query), headers: _headers()));

  Future<dynamic> post(String path, [Object? body]) =>
      _send(() => _http.post(_uri(path), headers: _headers(), body: jsonEncode(body ?? {})));

  Future<dynamic> patch(String path, Object body) =>
      _send(() => _http.patch(_uri(path), headers: _headers(), body: jsonEncode(body)));

  Future<dynamic> delete(String path) => _send(() => _http.delete(_uri(path), headers: _headers()));

  Future<dynamic> multipart(String path, {required List<UploadFile> files, Map<String, String> fields = const {}}) {
    return _send(() async {
      final req = http.MultipartRequest('POST', _uri(path))
        ..headers.addAll(_headers(json: false))
        ..fields.addAll(fields);
      for (final f in files) {
        req.files.add(await http.MultipartFile.fromPath(f.field, f.path));
      }
      final streamed = await _http.send(req).timeout(const Duration(seconds: 60));
      return http.Response.fromStream(streamed);
    });
  }

  Future<dynamic> _send(Future<http.Response> Function() request, {bool retried = false}) async {
    http.Response res;
    try {
      res = await request().timeout(_timeout);
    } on SocketException {
      throw ApiException(0, 'network', 'Cannot reach the DeviceTrust server. Check your connection.');
    } on TimeoutException {
      throw ApiException(0, 'timeout', 'The server took too long to respond. Try again.');
    } on http.ClientException {
      throw ApiException(0, 'network', 'Cannot reach the DeviceTrust server. Check your connection.');
    }

    if (res.statusCode == 401 && !retried && tokens.refreshToken != null) {
      if (await _refresh()) return _send(request, retried: true);
      onSessionExpired?.call();
    }
    if (res.statusCode == 204 || res.body.isEmpty) return null;

    dynamic data;
    try {
      data = jsonDecode(res.body);
    } catch (_) {
      throw ApiException(res.statusCode, 'bad_response', 'Unexpected server response (${res.statusCode}).');
    }
    if (res.statusCode >= 400) {
      final err = data is Map ? data['error'] : null;
      throw ApiException(
        res.statusCode,
        (err is Map ? err['code'] : null)?.toString() ?? 'error',
        (err is Map ? err['message'] : null)?.toString() ?? 'Request failed (${res.statusCode})',
      );
    }
    return data;
  }

  /// Single-flight refresh: concurrent 401s share one refresh call.
  Future<bool> _refresh() async {
    if (_refreshing != null) return _refreshing!.future;
    final completer = Completer<bool>();
    _refreshing = completer;
    try {
      final res = await _http
          .post(_uri('/auth/refresh'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refreshToken': tokens.refreshToken}))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        await tokens.save(data['accessToken'] as String, data['refreshToken'] as String);
        completer.complete(true);
      } else {
        await tokens.clear();
        completer.complete(false);
      }
    } catch (_) {
      completer.complete(false);
    } finally {
      _refreshing = null;
    }
    return completer.future;
  }
}
