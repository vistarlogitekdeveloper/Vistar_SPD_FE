import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// The **full API root**, including whatever path the backend is mounted under.
///
///   local backend        http://localhost:4100/api
///   deployed             https://spd-api.vistarlogitek.com/api
///
/// Override at build time:
///   flutter build web --release --dart-define=SPD_API=https://`<host`>/api
String resolveApiRoot() {
  const fromEnv = String.fromEnvironment('SPD_API');
  if (fromEnv.isNotEmpty) return normalizeApiRoot(fromEnv);
  var isAndroidEmulator = false;
  try {
    isAndroidEmulator = !kIsWeb && Platform.isAndroid;
  } catch (_) {
    // Platform is unavailable on some targets; treat those as not-Android.
  }
  // 10.0.2.2 is the Android emulator's alias for the host machine's loopback.
  // A table tablet on the shop floor is given the real address with
  // --dart-define at build time.
  return isAndroidEmulator ? 'http://10.0.2.2:4100/api' : 'http://localhost:4100/api';
}

/// Tidies a hand-written `--dart-define`: trims trailing slashes and collapses
/// doubled ones in the path, leaving `https://` alone.
String normalizeApiRoot(String raw) {
  final trimmed = raw.trim().replaceAll(RegExp(r'/+$'), '');
  final m = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*://[^/]+)(/.*)?$').firstMatch(trimmed);
  if (m == null) return trimmed;
  final path = (m.group(2) ?? '').replaceAll(RegExp(r'/{2,}'), '/');
  return '${m.group(1)}$path';
}

/// True when a deployed web build was never told where its API is: it is being
/// served from a real origin but still points at a developer's own machine.
bool _looksUnconfigured(String apiRoot) {
  if (!kIsWeb) return false;
  final api = Uri.tryParse(apiRoot);
  final page = Uri.base;
  const local = {'localhost', '127.0.0.1'};
  return api != null && local.contains(api.host) && !local.contains(page.host);
}

/// Thrown for any non-2xx response, carrying the message the API produced so
/// the UI can show the real reason rather than "something went wrong". The SRS
/// asks for exactly that (NFR-4.2), and the server is the only place that knows
/// which row, column or quantity limit was breached.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.details});

  final String message;
  final int? statusCode;
  final dynamic details;

  bool get isOffline => statusCode == null;
  bool get isConflict => statusCode == 409;
  bool get isUnauthorized => statusCode == 401;

  /// A BR-08 duplicate-batch refusal, which the upload screen turns into the
  /// "confirm re-upload" dialog rather than a plain error.
  bool get isDuplicateBatch => statusCode == 409 && details is Map && details['duplicate'] == true;

  /// The row/column list from a rejected GRN import (FR-1.3).
  List<Map<String, dynamic>> get rowErrors =>
      details is List ? List<Map<String, dynamic>>.from(details as List) : const [];

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? baseUrl})
      : baseUrl = baseUrl == null ? resolveApiRoot() : normalizeApiRoot(baseUrl) {
    _dio = Dio(BaseOptions(
      baseUrl: this.baseUrl,
      connectTimeout: const Duration(seconds: 12),
      // NFR-1.2 allows 60 s for a 5,000-line GRN import, so the client must not
      // give up before the server has finished the job it was asked to do.
      receiveTimeout: const Duration(seconds: 90),
      sendTimeout: const Duration(seconds: 90),
      validateStatus: (s) => s != null && s < 500,
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null) options.headers['Authorization'] = 'Bearer $_token';
        handler.next(options);
      },
    ));
  }

  final String baseUrl;
  late final Dio _dio;
  String? _token;

  /// Set once at sign-in; cleared on sign-out or a 401.
  void setToken(String? token) => _token = token;
  String? get token => _token;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get(path, queryParameters: _clean(query)));

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send(() => _dio.post(path, data: body, queryParameters: _clean(query)));

  Future<dynamic> patch(String path, {Object? body}) => _send(() => _dio.patch(path, data: body));

  Future<dynamic> put(String path, {Object? body}) => _send(() => _dio.put(path, data: body));

  Future<dynamic> delete(String path) => _send(() => _dio.delete(path));

  Future<dynamic> upload(String path, FormData form) => _send(() => _dio.post(path, data: form));

  /// Binary fetch for the Excel/CSV/PDF output of FR-12.1 and FR-3.2.
  Future<Uint8List> download(String path, {Map<String, dynamic>? query}) async {
    try {
      final res = await _dio.get<List<int>>(
        path,
        queryParameters: _clean(query),
        options: Options(responseType: ResponseType.bytes),
      );
      if (res.statusCode! >= 400) {
        throw ApiException(_messageFromBytes(res.data), statusCode: res.statusCode);
      }
      return Uint8List.fromList(res.data!);
    } on DioException catch (e) {
      throw _fromDio(e);
    }
  }

  Future<dynamic> _send(Future<Response> Function() run) async {
    try {
      final res = await run();
      if (res.statusCode! >= 400) {
        final data = res.data;
        final msg = data is Map && data['error'] != null ? '${data['error']}' : 'Request failed (${res.statusCode})';
        throw ApiException(msg, statusCode: res.statusCode, details: data is Map ? data['details'] : null);
      }
      return res.data;
    } on DioException catch (e) {
      throw _fromDio(e);
    }
  }

  ApiException _fromDio(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      if (_looksUnconfigured(baseUrl)) {
        return ApiException(
          'This build was not told where the SPD API is, so it is still '
          'pointing at $baseUrl. Rebuild with --dart-define=SPD_API=https://<host>/api',
        );
      }
      return ApiException('No connection to the SPD server at $baseUrl');
    }
    final data = e.response?.data;
    final msg = data is Map && data['error'] != null ? '${data['error']}' : (e.message ?? 'Network error');
    return ApiException(msg, statusCode: e.response?.statusCode, details: data is Map ? data['details'] : null);
  }

  String _messageFromBytes(List<int>? bytes) {
    if (bytes == null) return 'Download failed';
    try {
      final text = String.fromCharCodes(bytes);
      final match = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(text);
      return match?.group(1) ?? 'Download failed';
    } catch (_) {
      return 'Download failed';
    }
  }

  Map<String, dynamic>? _clean(Map<String, dynamic>? q) {
    if (q == null) return null;
    final out = <String, dynamic>{};
    q.forEach((k, v) {
      if (v != null && v != '') out[k] = v;
    });
    return out;
  }
}
