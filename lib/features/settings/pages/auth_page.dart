import 'package:flutter/material.dart';

import '../../../app_state.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_button.dart';
import '../../../core/widgets/sini_scaffold.dart';
import '../../../core/widgets/sini_text_field.dart';
import '../../../theme.dart';

/// 登录 / 注册（纯前端：账号存在本机，不做真实鉴权）
class AuthPage extends StatefulWidget {
  /// true = 打开就显示注册
  final bool startWithRegister;
  const AuthPage({super.key, this.startWithRegister = false});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _loginEmail = TextEditingController();
  final _loginPwd = TextEditingController();
  final _regName = TextEditingController();
  final _regEmail = TextEditingController();
  final _regPwd = TextEditingController();
  final _regPwd2 = TextEditingController();

  bool _loginObscure = true;
  bool _regObscure = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.startWithRegister ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    _loginEmail.dispose();
    _loginPwd.dispose();
    _regName.dispose();
    _regEmail.dispose();
    _regPwd.dispose();
    _regPwd2.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1600)),
    );
  }

  Future<void> _doLogin() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final err = await AppStateScope.of(context).login(
      email: _loginEmail.text,
      password: _loginPwd.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _toast(err);
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _doRegister() async {
    FocusScope.of(context).unfocus();
    if (_regPwd.text != _regPwd2.text) {
      _toast('两次输入的密码不一致');
      return;
    }
    setState(() => _busy = true);
    final err = await AppStateScope.of(context).register(
      name: _regName.text,
      email: _regEmail.text,
      password: _regPwd.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _toast(err);
      return;
    }
    _toast('注册成功，已自动登录');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return SiniScaffold(
      title: '登录 / 注册',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, 0),
            child: Container(
              height: 38,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: p.itemHover,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: TabBar(
                controller: _tab,
                indicator: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: p.textPrimary,
                unselectedLabelColor: p.textSecondary,
                labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                tabs: const [Tab(text: '登录'), Tab(text: '注册')],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _loginForm(p),
                _registerForm(p),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginForm(AppPalette p) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xxxl),
      children: [
        SiniTextField(
          controller: _loginEmail,
          label: '邮箱',
          hintText: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: Spacing.md),
        SiniTextField(
          controller: _loginPwd,
          label: '密码',
          hintText: '请输入密码',
          obscureText: _loginObscure,
          suffixIcon: IconButton(
            icon: Icon(
              _loginObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 18,
              color: p.textTertiary,
            ),
            onPressed: () => setState(() => _loginObscure = !_loginObscure),
          ),
        ),
        const SizedBox(height: Spacing.xl),
        SiniButton(
          label: _busy ? '正在登录…' : '登录',
          onTap: _busy ? null : _doLogin,
          style: SiniButtonStyle.primary,
          expand: true,
          height: 48,
        ),
        const SizedBox(height: Spacing.md),
        Center(
          child: Text(
            '还没有账号？点上方「注册」',
            style: TextStyle(fontSize: SiniText.labelMd, color: p.textTertiary),
          ),
        ),
      ],
    );
  }

  Widget _registerForm(AppPalette p) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xxxl),
      children: [
        SiniTextField(
          controller: _regName,
          label: '昵称',
          hintText: '别人怎么称呼你',
        ),
        const SizedBox(height: Spacing.md),
        SiniTextField(
          controller: _regEmail,
          label: '邮箱',
          hintText: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: Spacing.md),
        SiniTextField(
          controller: _regPwd,
          label: '密码',
          hintText: '至少 6 位',
          obscureText: _regObscure,
          suffixIcon: IconButton(
            icon: Icon(
              _regObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 18,
              color: p.textTertiary,
            ),
            onPressed: () => setState(() => _regObscure = !_regObscure),
          ),
        ),
        const SizedBox(height: Spacing.md),
        SiniTextField(
          controller: _regPwd2,
          label: '确认密码',
          hintText: '再输入一次',
          obscureText: _regObscure,
        ),
        const SizedBox(height: Spacing.xl),
        SiniButton(
          label: _busy ? '正在注册…' : '注册并登录',
          onTap: _busy ? null : _doRegister,
          style: SiniButtonStyle.primary,
          expand: true,
          height: 48,
        ),
        const SizedBox(height: Spacing.md),
        Text(
          '演示阶段账号只保存在这台设备上，不会上传服务器。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: SiniText.labelSm, color: p.textTertiary, height: 1.5),
        ),
      ],
    );
  }
}
