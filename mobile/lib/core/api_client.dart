import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../demo/demo_backend.dart';

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

/// Tokens live in the platform keystore (Android Keystore-backed) for the real server.
/// In demo mode there is no real credential to protect, so plain app storage is used
/// (this also keeps the demo testable without platform plugins).
class TokenStore {
  TokenStore({this.secure = true});
  final bool secure;
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  String? accessToken;
  String? refreshToken;

  Future<String?> _read(String k) async =>
      secure ? _storage.read(key: k) : (await SharedPreferences.getInstance()).getString(k);

  Future<void> _write(String k, String v) async {
    if (secure) {
      await _storage.write(key: k, value: v);
    } else {
      await (await SharedPreferences.getInstance()).setString(k, v);
    }
  }

  Future<void> _delete(String k) async {
    if (secure) {
      await _storage.delete(key: k);
    } else {
      await (await SharedPreferences.getInstance()).remove(k);
    }
  }

  Future<void> load() async {
    accessToken = await _read('access_token');
    refreshToken = await _read('refresh_token');
  }

  Future<void> save(String access, String refresh) async {
    accessToken = access;
    refreshToken = refresh;
    await _write('access_token', access);
    await _write('refresh_token', refresh);
  }

  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    await _delete('access_token');
    await _delete('refresh_token');
  }
}

class UploadFile {
  final String field;
  final String path;
  UploadFile(this.field, this.path);
}

class ApiClient {
  ApiClient(this.tokens, {this.demo});

  final TokenStore tokens;

  /// When set, every call is answered by the in-app demo backend instead of the network.
  final DemoBackend? demo;
  bool get isDemo => demo != null;
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

  Future<dynamic> _local(String method, String path, {Map<String, dynamic>? query, Object? body, List<UploadFile> files = const [], Map<String, String> fields = const {}}) async {
    try {
      return await demo!.handle(method, path, query: query, body: body, files: files, fields: fields, token: tokens.accessToken);
    } on ApiException catch (e) {
      if (e.status == 401 && path != '/auth/login' && path != '/auth/register') onSessionExpired?.call();
      rethrow;
    }
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => isDemo
      ? _local('GET', path, query: query)
      : _send(() => _http.get(_uri(path, query), headers: _headers()));

  Future<dynamic> post(String path, [Object? body]) => isDemo
      ? _local('POST', path, body: body ?? {})
      : _send(() => _http.post(_uri(path), headers: _headers(), body: jsonEncode(body ?? {})));

  Future<dynamic> patch(String path, Object body) =>
      isDemo ? _local('PATCH', path, body: body) : _send(() => _http.patch(_uri(path), headers: _headers(), body: jsonEncode(body)));

  Future<dynamic> delete(String path) => isDemo ? _local('DELETE', path) : _send(() => _http.delete(_uri(path), headers: _headers()));

  Future<dynamic> multipart(String path, {required List<UploadFile> files, Map<String, String> fields = const {}}) {
    if (isDemo) return _local('POST', path, files: files, fields: fields);
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
