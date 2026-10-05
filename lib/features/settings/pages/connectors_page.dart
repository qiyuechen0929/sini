import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_state.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_button.dart';
import '../../../core/widgets/sini_scaffold.dart';
import '../../../theme.dart';
import '../../../utils/connectors.dart' show ConnectorApi;
import '../../../utils/web_bridge.dart' show openExternalUrl;

/// 连接器面板：把 TA 接进真实生活。
/// - 邮件提醒（QQ 邮箱代发）：用户填自己邮箱 + 验证码，一次绑定
/// - GitHub：设备授权流，点连接 → 输码授权 → 自动完成
class ConnectorsPage extends StatefulWidget {
  const ConnectorsPage({super.key});

  @override
  State<ConnectorsPage> createState() => _ConnectorsPageState();
}

class _ConnectorsPageState extends State<ConnectorsPage> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _ghTokenCtrl = TextEditingController();
  final _serverCtrl = TextEditingController();
  bool _ghVerifying = false;
  bool _codeSent = false;
  bool _busy = false;
  String? _emailMsg;
  String? _serverMsg;

  // github 绑定进行中
  bool _ghBinding = false;
  String? _ghUserCode;
  String? _ghVerifyUrl;
  String? _ghDeviceCode;
  Timer? _ghPollTimer;
  String? _ghMsg;

  @override
  void initState() {
    super.initState();
    _bootstrapServer();
  }

  Future<void> _bootstrapServer() async {
    await ConnectorApi.loadFromPrefs();
    if (!mounted) return;
    _serverCtrl.text = ConnectorApi.serverBase ?? '';
    setState(() {});
  }

  Future<void> _saveServer() async {
    final url = _serverCtrl.text.trim();
    if (url.isEmpty) {
      await ConnectorApi.setServerBase('');
      setState(() => _serverMsg = '已清除自定义地址');
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => _serverMsg = '地址要以 http:// 或 https:// 开头');
      return;
    }
    await ConnectorApi.setServerBase(url);
    // 试一次连通
    final probe = await ConnectorApi.githubDeviceStart();
    if (!mounted) return;
    if (probe.ok) {
      setState(() => _serverMsg = '已保存，连接电脑成功');
    } else if (probe.error != null && probe.error!.contains('尚未配置')) {
      setState(() => _serverMsg = '已保存，电脑服务在线（GitHub 未配置属正常）');
    } else {
      setState(() => _serverMsg = '已保存，但探测失败：${probe.error ?? "网络不通"}\n请确认电脑在跑 serve_web.py，且手机同 Wi-Fi');
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _ghTokenCtrl.dispose();
    _serverCtrl.dispose();
    _ghPollTimer?.cancel();
    super.dispose();
  }

  /// 令牌粘贴连接：验证 profile → 存 token
  Future<void> _connectWithToken() async {
    final token = _ghTokenCtrl.text.trim();
    if (token.isEmpty) return;
    setState(() {
      _ghVerifying = true;
      _ghMsg = null;
    });
    final u = await ConnectorApi.githubOps(token: token, op: 'profile');
    if (!mounted) return;
    if (u.ok && u.data is Map) {
      final d = u.data['data'];
      final login = d is Map && d['login'] != null ? d['login'].toString() : 'github用户';
      await AppStateScope.of(context).setGithub(token, login);
      setState(() => _ghVerifying = false);
    } else {
      setState(() {
        _ghVerifying = false;
        _ghMsg = '令牌无效：${u.error ?? "请检查是否复制完整"}';
      });
    }
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _emailMsg = null;
    });
    final r = await ConnectorApi.emailSendCode(_emailCtrl.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _codeSent = r.ok;
      _emailMsg = r.ok ? '验证码已发送，去邮箱看看（10 分钟内有效）' : r.error;
    });
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _emailMsg = null;
    });
    final r = await ConnectorApi.emailVerify(
        _emailCtrl.text.trim(), _codeCtrl.text.trim());
    if (!mounted) return;
    if (r.ok) {
      await AppStateScope.of(context)
          .setEmailBinding(_emailCtrl.text.trim(), enabled: true);
      setState(() => _busy = false);
    } else {
      setState(() {
        _busy = false;
        _emailMsg = r.error;
      });
    }
  }

  Future<void> _startGithub() async {
    setState(() {
      _ghBinding = true;
      _ghMsg = null;
    });
    final r = await ConnectorApi.githubDeviceStart();
    if (!r.ok || r.data == null) {
      setState(() {
        _ghBinding = false;
        _ghMsg = r.error;
      });
      return;
    }
    final d = r.data!;
    setState(() {
      _ghUserCode = (d['user_code'] ?? '').toString();
      _ghVerifyUrl = (d['verification_uri'] ?? 'https://github.com/login/device')
          .toString();
      _ghDeviceCode = (d['device_code'] ?? '').toString();
    });
    // 用户去授权，本地每 5 秒轮询一次
    _ghPollTimer?.cancel();
    _ghPollTimer = Timer.periodic(const Duration(seconds: 5), (t) async {
      if (_ghDeviceCode == null) return;
      final pr = await ConnectorApi.githubPoll(_ghDeviceCode!);
      if (pr.status == 'ok' && pr.token != null && mounted) {
        t.cancel();
        // 拿到 token 后查一下账号名
        final u = await ConnectorApi.githubOps(token: pr.token!, op: 'profile');
        String login = 'github用户';
        if (u.ok && u.data is Map) {
          final d2 = u.data['data'];
          if (d2 is Map && d2['login'] != null) login = d2['login'].toString();
        }
        await AppStateScope.of(context).setGithub(pr.token!, login);
        setState(() {
          _ghBinding = false;
          _ghUserCode = null;
        });
      } else if ((pr.status == 'failed' || pr.status == 'expired') && mounted) {
        t.cancel();
        setState(() {
          _ghBinding = false;
          _ghUserCode = null;
          _ghMsg = pr.status == 'expired' ? '授权超时了，再点一次连接' : '授权失败：${pr.error ?? ''}';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final state = AppStateScope.of(context);
    return SiniScaffold(
      title: '连接器',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.md, Spacing.lg, Spacing.xxl),
        children: [
          Text('把 TA 接进你的真实生活。凭证只保存在本机，AI 拿不到原文。',
              style: TextStyle(fontSize: SiniText.bodySm, color: p.textSecondary)),
          const SizedBox(height: Spacing.lg),

          // ── 电脑服务器（手机端必填）──
          _card(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.dns_outlined, size: 20, color: p.textPrimary),
                const SizedBox(width: 8),
                Text('电脑服务器',
                    style: TextStyle(
                        fontSize: SiniText.titleSm,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary)),
              ]),
              const SizedBox(height: 6),
              Text(
                '验证码和 GitHub 都由电脑上的 serve_web.py 代理发出。手机必须能访问这台电脑。\n'
                '电脑上执行：python serve_web.py build/web 8765\n'
                '然后把「http://电脑局域网IP:8765」填在下面（与手机同一 Wi-Fi）。',
                style: TextStyle(fontSize: SiniText.bodySm, color: p.textSecondary, height: 1.55),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: _serverCtrl,
                keyboardType: TextInputType.url,
                style: TextStyle(fontSize: 13.5, color: p.textPrimary),
                decoration: InputDecoration(
                  hintText: 'http://10.0.0.2:8765',
                  hintStyle: TextStyle(fontSize: 12.5, color: p.textTertiary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              SiniButton(
                label: '保存并测试连接',
                style: SiniButtonStyle.secondary,
                onTap: _saveServer,
                height: 44,
                expand: true,
              ),
              if (_serverMsg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_serverMsg!,
                      style: TextStyle(fontSize: 11.5, color: p.textTertiary)),
                ),
            ],
          )),
          const SizedBox(height: Spacing.lg),

          // ── 邮件提醒 ──
          _card(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.mail_outline_rounded, size: 20, color: p.textPrimary),
                const SizedBox(width: 8),
                Text('邮件提醒',
                    style: TextStyle(
                        fontSize: SiniText.titleSm,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary)),
                const Spacer(),
                if (state.emailBound)
                  Switch(
                      value: state.emailConnectorReady,
                      onChanged: (v) =>
                          AppStateScope.of(context).setEmailEnabled(v)),
              ]),
              const SizedBox(height: 4),
              Text(
                state.emailBound
                    ? '已绑定 ${state.emailAddress} · TA 的信会寄到这里'
                    : '绑定你的邮箱后，可以让 TA「把总结发我邮箱」，TA 的主动消息也能寄信',
                style: TextStyle(fontSize: SiniText.bodySm, color: p.textSecondary),
              ),
              if (!state.emailBound) ...[
                const SizedBox(height: Spacing.md),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(fontSize: 13.5, color: p.textPrimary),
                  decoration: InputDecoration(
                    hintText: '你的邮箱地址（QQ/163/Gmail 都行）',
                    hintStyle: TextStyle(fontSize: 12.5, color: p.textTertiary),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                if (_codeSent) ...[
                  TextField(
                    controller: _codeCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(fontSize: 13.5, color: p.textPrimary),
                    decoration: InputDecoration(
                      hintText: '6 位验证码',
                      hintStyle:
                          TextStyle(fontSize: 12.5, color: p.textTertiary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  SiniButton(
                    label: _busy ? '验证中…' : '验证并开启',
                    onTap: _busy ? null : _verify,
                    height: 44,
                    expand: true,
                  ),
                ] else
                  SiniButton(
                    label: _busy ? '发送中…' : '发送验证码',
                    leadingIcon: Icons.mark_email_read_outlined,
                    style: SiniButtonStyle.secondary,
                    onTap: _busy ? null : _sendCode,
                    height: 44,
                    expand: true,
                  ),
              ] else
                Center(
                  child: TextButton(
                    onPressed: () => AppStateScope.of(context)
                        .setEmailBinding('', enabled: false),
                    child: Text('解除绑定',
                        style: TextStyle(
                            fontSize: 12, color: p.textTertiary)),
                  ),
                ),
              if (_emailMsg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_emailMsg!,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: _emailMsg!.startsWith('验证码已发送')
                              ? const Color(0xFF10A37F)
                              : const Color(0xFFB42318))),
                ),
            ],
          )),
          const SizedBox(height: Spacing.lg),

          // ── GitHub ──
          _card(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.code_rounded, size: 20, color: p.textPrimary),
                const SizedBox(width: 8),
                Text('GitHub',
                    style: TextStyle(
                        fontSize: SiniText.titleSm,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary)),
              ]),
              const SizedBox(height: 4),
              Text(
                state.githubReady
                    ? '已连接账号 ${state.githubLogin} · 可以让 TA「看看我的仓库」「我的 Issue」'
                    : '连接后可以问 TA：我仓库最近怎么样、我有哪些待处理的 Issue',
                style: TextStyle(fontSize: SiniText.bodySm, color: p.textSecondary),
              ),
              const SizedBox(height: Spacing.md),
              if (state.githubReady)
                Center(
                  child: TextButton(
                    onPressed: () =>
                        AppStateScope.of(context).disconnectGithub(),
                    child: Text('断开连接',
                        style: TextStyle(
                            fontSize: 12, color: p.textTertiary)),
                  ),
                )
              else if (_ghBinding) ...[
                Container(
                  padding: const EdgeInsets.all(Spacing.md),
                  decoration: BoxDecoration(
                    color: p.itemHover,
                    borderRadius: BorderRadius.circular(Radii.lg),
                  ),
                  child: Column(children: [
                    const Text('1. 打开授权页，输入这个码：',
                        style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 6),
                    Text(_ghUserCode ?? '...',
                        style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3,
                            color: Color(0xFF10A37F))),
                    const SizedBox(height: 8),
                    SiniButton(
                      label: '打开 GitHub 授权页',
                      leadingIcon: Icons.open_in_new_rounded,
                      style: SiniButtonStyle.secondary,
                      onTap: () =>
                          openExternalUrl(_ghVerifyUrl ?? 'https://github.com/login/device'),
                      height: 40,
                      expand: true,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 8),
                        Text('等待你在 GitHub 点下授权…',
                            style: TextStyle(
                                fontSize: 11, color: p.textTertiary)),
                      ],
                    ),
                  ]),
                ),
              ] else ...[
                TextField(
                  controller: _ghTokenCtrl,
                  obscureText: true,
                  style: TextStyle(fontSize: 13, color: p.textPrimary),
                  decoration: InputDecoration(
                    hintText: '粘贴 GitHub 令牌（ghp_ / github_pat_ 开头）',
                    hintStyle: TextStyle(fontSize: 12.5, color: p.textTertiary),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                SiniButton(
                  label: _ghVerifying ? '验证中…' : '使用令牌连接',
                  leadingIcon: Icons.link_rounded,
                  onTap: _ghVerifying ? null : _connectWithToken,
                  height: 44,
                  expand: true,
                ),
                const SizedBox(height: Spacing.xs),
                Center(
                  child: Text('没有令牌？去 GitHub → Settings → Developer settings → '
                      'Personal access tokens → Tokens (classic) → Generate new token，'
                      '勾选 repo 和 notifications 后复制',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 10.5, color: p.textTertiary)),
                ),
              ],
              if (_ghMsg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_ghMsg!,
                      style: const TextStyle(
                          fontSize: 11.5, color: Color(0xFFB42318))),
                ),
            ],
          )),
          const SizedBox(height: Spacing.lg),
          Center(
            child: Text('更多连接器（钉钉提醒等）规划中',
                style: TextStyle(fontSize: 10.5, color: p.textTertiary)),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: child,
    );
  }
}
