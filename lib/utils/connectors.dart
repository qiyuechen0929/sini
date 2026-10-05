import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 连接器 API + ```connector 调用块协议。
/// 走本地代理（serve_web.py）。Web 同源即可；
/// 手机 APK 必须指向电脑局域网 IP（设置 → 连接器 → 电脑服务器地址）。

class ConnectorApi {
  static const prefKey = 'connector_server_base';

  /// 手机上用户填的电脑地址，如 http://10.225.246.113:8765
  static String? _serverBase;

  static String? get serverBase => _serverBase;

  /// 从本地设置恢复服务器地址（启动/进连接器页时调一次）
  static Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = (prefs.getString(prefKey) ?? '').trim();
      _serverBase = raw.isEmpty ? null : _normalize(raw);
    } catch (_) {
      _serverBase = null;
    }
  }

  /// 保存并立即生效；传空字符串表示清掉自定义地址
  static Future<void> setServerBase(String url) async {
    final raw = url.trim();
    _serverBase = raw.isEmpty ? null : _normalize(raw);
    final prefs = await SharedPreferences.getInstance();
    if (raw.isEmpty) {
      await prefs.remove(prefKey);
    } else {
      await prefs.setString(prefKey, _serverBase!);
    }
  }

  static String _normalize(String url) {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    // 允许用户只填 http://1.2.3.4:8765 或带 /api/connector
    if (u.endsWith('/api/connector')) {
      u = u.substring(0, u.length - '/api/connector'.length);
    }
    if (u.endsWith('/api')) {
      u = u.substring(0, u.length - 4);
    }
    return u;
  }

  static Dio get _dio => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 15),
      ));

  /// 当前应使用的 API 前缀
  static String get _base {
    if (_serverBase != null && _serverBase!.isNotEmpty) {
      return '$_serverBase/api/connector';
    }
    // Web 预览：同源
    if (kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.startsWith('http')) return '$origin/api/connector';
    }
    // 原生 App：默认打本机 —— 几乎一定失败，错误信息会引导填电脑 IP
    return 'http://127.0.0.1:8765/api/connector';
  }

  static String get connectionHint {
    if (kIsWeb) return 'Web 版请确认已运行 serve_web.py';
    if (_serverBase == null) {
      return '手机端请在下方填写电脑局域网地址（电脑上运行 python serve_web.py）';
    }
    return '当前服务器：$_serverBase';
  }

  static Future<({bool ok, dynamic data, String? error})> _get(
      String path, Map<String, String> query) async {
    try {
      final res = await _dio.get<dynamic>('$_base/$path', queryParameters: query);
      final j = res.data;
      if (j is Map<String, dynamic>) {
        if (j['error'] != null) return (ok: false, data: null, error: j['error'].toString());
        return (ok: true, data: j, error: null);
      }
      return (ok: false, data: null, error: '响应格式异常');
    } on DioException catch (e) {
      final d = e.response?.data;
      final err = d is Map && d['error'] != null
          ? d['error'].toString()
          : (e.message ?? '网络错误');
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return (
          ok: false,
          data: null,
          error: '$err\n\n若在手机上：请确认电脑已运行 serve_web.py，且手机与电脑同一 Wi-Fi，并在下方填写电脑 IP。'
        );
      }
      return (ok: false, data: null, error: err);
    } catch (e) {
      return (ok: false, data: null, error: '$e');
    }
  }

  // ---- 邮件 ----
  static Future<({bool ok, String? error})> emailSendCode(String email) async {
    final r = await _get('email', {'action': 'send-code', 'email': email});
    return (ok: r.ok, error: r.error);
  }

  static Future<({bool ok, String? error})> emailVerify(
      String email, String code) async {
    final r = await _get('email', {'action': 'verify', 'email': email, 'code': code});
    return (ok: r.ok, error: r.error);
  }

  static Future<({bool ok, String? error})> emailSend({
    required String to,
    required String subject,
    required String body,
  }) async {
    final r = await _get('email', {
      'action': 'send',
      'to': to,
      'subject': subject,
      'body': body,
    });
    return (ok: r.ok, error: r.error);
  }

  // ---- GitHub ----
  static Future<({bool ok, Map<String, dynamic>? data, String? error})>
      githubDeviceStart() async {
    final r = await _get('github', {'action': 'device-start'});
    final d = r.data is Map<String, dynamic> ? r.data as Map<String, dynamic> : null;
    return (ok: r.ok, data: d, error: r.error);
  }

  /// 轮询一次授权状态：pending / ok(data 含 token) / failed / expired
  static Future<({String status, String? token, String? error})> githubPoll(
      String deviceCode) async {
    final r = await _get('github', {'action': 'device-poll', 'device_code': deviceCode});
    if (!r.ok) return (status: 'failed', token: null, error: r.error);
    final d = r.data!;
    final status = (d['status'] ?? '').toString();
    return (status: status, token: (d['token'] ?? '').toString(), error: null);
  }

  static Future<({bool ok, dynamic data, String? error})> githubOps({
    required String token,
    required String op,
  }) async {
    return _get('github', {'action': 'ops', 'token': token, 'op': op});
  }
}

/// AI 回复里的 ```connector 调用块
class ConnectorCall {
  final String type; // email | github
  final Map<String, dynamic> args;
  const ConnectorCall({required this.type, required this.args});

  static ConnectorCall? tryParse(String code) {
    final j = tryParseConnectorJson(code);
    if (j == null) return null;
    final type = (j['type'] ?? '').toString();
    if (type != 'email' && type != 'github') return null;
    return ConnectorCall(type: type, args: j);
  }
}

/// 找出正文里的连接器/自动化调用块
/// （```connector 和 ```automation 两种围栏都认——提示词里自动化用的是后者）
class ConnectorBlockMatch {
  final String full;
  final String code;
  final String lang; // connector | automation
  const ConnectorBlockMatch(this.full, this.code, this.lang);
}

List<ConnectorBlockMatch> findConnectorBlocks(String text) {
  final re =
      RegExp(r'```(connector|automation)\s*([\s\S]*?)```', caseSensitive: false);
  return re.allMatches(text).map((m) {
    return ConnectorBlockMatch(
        m.group(0)!, m.group(2) ?? '', (m.group(1) ?? '').toLowerCase());
  }).toList();
}

Map<String, dynamic>? tryParseConnectorJson(String code) {
  try {
    final src = code.trim().replaceAll(RegExp(r',\s*([}\]])'), r'$1');
    final j = jsonDecode(src);
    return j is Map<String, dynamic> ? j : null;
  } catch (_) {
    return null;
  }
}
