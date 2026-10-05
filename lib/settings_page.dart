import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'core/widgets/sini_sheet.dart';
import 'core/widgets/sini_status_pill.dart';
import 'theme.dart';
import 'utils/export_file.dart'
    show downloadTextFile, saveAndNotify;
import 'utils/mobile_share.dart' show fallbackExportDir, exportTextToPickedDir;
import 'utils/web_search.dart'
    show kSearchProviders, searchProviderLabel, webSearch;

/// 设置页：账号、主题、数据、授权等
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final state = AppStateScope.of(context);
    return Scaffold(
      backgroundColor: p.mainBg,
      appBar: AppBar(
        backgroundColor: p.mainBg,
        elevation: 0,
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _section('功能', p),
          _tile(
            context: context,
            title: '数字人格',
            subtitle: '查看 / 创建 / 编辑人物',
            icon: Icons.people_alt_outlined,
            p: p,
            onTap: () => Navigator.of(context).pushNamed('/personas'),
          ),
          _tile(
            context: context,
            title: '长期记忆',
            subtitle: '管理 AI 记住的事情',
            icon: Icons.psychology_outlined,
            p: p,
            onTap: () => Navigator.of(context).pushNamed('/memory'),
          ),
          _switchTile(
            context: context,
            title: '允许 TA 主动找你',
            subtitle: state.proactiveChatEnabled
                ? 'TA 会不时想起你，主动来说两句'
                : '打开后，TA 会像真人一样偶尔主动找你说话',
            icon: Icons.notifications_active_outlined,
            value: state.proactiveChatEnabled,
            onChanged: (v) => _confirmProactive(context, state, v),
            p: p,
          ),
          if (state.proactiveChatEnabled)
            _switchTile(
              context: context,
              title: '消息通知栏提醒',
              subtitle: _notifySubtitle(state),
              icon: Icons.mark_chat_unread_outlined,
              value: state.systemNotifyEnabled,
              onChanged: (v) => _toggleSystemNotify(context, state, v),
              p: p,
            ),
          _switchTile(
            context: context,
            title: '深夜守护',
            subtitle: '很晚还在聊时，TA 会轻轻劝你去睡（一晚一次）',
            icon: Icons.nightlight_round,
            value: state.nightGuardEnabled,
            onChanged: (v) => state.setNightGuardEnabled(v),
            p: p,
          ),
          _switchTile(
            context: context,
            title: '人格专属背景',
            subtitle: '聊天背景随 TA 的配色变化；不喜欢可关掉',
            icon: Icons.brush_outlined,
            value: state.personaBgEnabled,
            onChanged: (v) => state.setPersonaBgEnabled(v),
            p: p,
          ),
          const SizedBox(height: 16),
          _section('外观', p),
          _switchTile(
            context: context,
            title: '深色模式',
            subtitle: '切换为深色主题',
            value: state.isDark,
            onChanged: (_) => state.toggleTheme(),
            p: p,
          ),
          const SizedBox(height: 16),
          _section('模型', p),
          _tile(
            context: context,
            title: '模型管理',
            subtitle: state.defaultModelConfig == null
                ? '还没有配置模型'
                : '默认：${state.defaultModelConfig!.name} · ${state.defaultModelConfig!.modelId}',
            icon: Icons.smart_toy_outlined,
            p: p,
            onTap: () => Navigator.of(context).pushNamed('/settings/models'),
          ),
          const SizedBox(height: 8),
          _tile(
            context: context,
            title: '连接器',
            subtitle: state.emailBound || state.githubReady
                ? '已开启 ${[
                  if (state.emailBound) '邮件',
                  if (state.githubReady) 'GitHub',
                ].join(" · ")}'
                : '把 TA 接进邮箱和 GitHub',
            icon: Icons.extension_rounded,
            p: p,
            onTap: () => Navigator.of(context).pushNamed('/settings/connectors'),
          ),
          const SizedBox(height: 8),
          _tile(
            context: context,
            title: '自动化',
            subtitle: state.automations.isEmpty
                ? '定时任务 · 对 TA 说「每天早上给我发封信」即可创建'
                : '${state.automations.where((t) => t.enabled).length} 个进行中 · 共 ${state.automations.length} 个',
            icon: Icons.schedule_send_outlined,
            p: p,
            onTap: () => Navigator.of(context).pushNamed('/settings/automations'),
          ),
          const SizedBox(height: 8),
          _tile(
            context: context,
            title: '用量统计',
            subtitle: '各模型 Token 消耗 · 按日趋势',
            icon: Icons.donut_small_rounded,
            p: p,
            onTap: () => Navigator.of(context).pushNamed('/settings/usage'),
          ),
          const SizedBox(height: 8),
          _tile(
            context: context,
            title: '联网搜索',
            subtitle: state.searchKey.trim().isEmpty
                ? '已开启（免费源）· 配置 Key 后效果更好'
                : '已开启 · ${searchProviderLabel(state.searchProvider)}',
            icon: Icons.travel_explore_rounded,
            p: p,
            onTap: () => _showSearchConfig(context, state),
          ),
          const SizedBox(height: 16),
          _section('账户', p),
          if (state.isLoggedIn) ...[
            _tile(
              context: context,
              title: state.currentUser!.name,
              subtitle: state.currentUser!.email,
              icon: Icons.person_outline,
              p: p,
              onTap: () {},
            ),
            _tile(
              context: context,
              title: '退出登录',
              subtitle: '本机账号仍会保留',
              icon: Icons.logout_rounded,
              p: p,
              onTap: () => _confirmLogout(context, state),
            ),
          ] else ...[
            _tile(
              context: context,
              title: '登录 / 注册',
              subtitle: '账号保存在这台设备，不上传服务器',
              icon: Icons.login_rounded,
              p: p,
              onTap: () => Navigator.of(context).pushNamed('/settings/auth'),
            ),
          ],
          _tile(
            context: context,
            title: '升级到 Pro',
            subtitle: '解锁更长记忆、声音克隆、数字人',
            icon: Icons.workspace_premium_outlined,
            p: p,
            onTap: () {},
          ),
          const SizedBox(height: 16),
          _section('数据与隐私', p),
          _tile(
            context: context,
            title: '备份全部数据',
            subtitle: '导出人格、对话、记忆、模型配置等本机数据',
            icon: Icons.download_outlined,
            p: p,
            onTap: () => _exportBackup(context, state),
          ),
          _tile(
            context: context,
            title: '从备份恢复',
            subtitle: '选择之前的 .sini-backup.json 整库恢复',
            icon: Icons.upload_file_outlined,
            p: p,
            onTap: () => _importBackup(context, state),
          ),
          _tile(
            context: context,
            title: '声音与肖像授权',
            subtitle: '查看 / 撤销授权',
            icon: Icons.verified_user_outlined,
            p: p,
            onTap: () => Navigator.of(context).pushNamed('/settings/consent'),
          ),
          _tile(
            context: context,
            title: '一键彻底删除',
            subtitle: '删除所有对话、Persona、克隆',
            icon: Icons.delete_outline,
            p: p,
            danger: true,
            onTap: () {},
          ),
          const SizedBox(height: 16),
          _section('关于', p),
          _tile(
            context: context,
            title: '似你 v0.1.0',
            subtitle: '数字人格交互系统 · MVP',
            icon: Icons.info_outline,
            p: p,
            onTap: () {},
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 系统通知那一行的小字说明：区分「未授权 / 不支持 / 已开 / 已关」
  String _notifySubtitle(AppState state) {
    if (!state.systemNotifySupported) return '当前浏览器不支持系统通知';
    if (state.systemNotifyEnabled) {
      return 'TA 来找你时，手机通知栏 / 桌面会弹出提醒';
    }
    if (state.systemNotifyGranted) {
      return '打开后，TA 来找你时会弹出系统提醒';
    }
    return '打开后会向浏览器申请通知权限';
  }

  /// 系统通知开关：开启会触发浏览器权限申请（必须在用户点击流里），
  /// 失败时用 SnackBar 告诉用户具体怎么处理。
  Future<void> _toggleSystemNotify(
      BuildContext context, AppState state, bool v) async {
    final messenger = ScaffoldMessenger.of(context);
    final err = await state.setSystemNotifyEnabled(v);
    if (err != null && context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(err), duration: const Duration(seconds: 4)),
      );
    }
  }

  Future<void> _confirmLogout(BuildContext context, AppState state) async {
    await showSiniSheet<void>(
      context: context,
      title: '退出登录？',
      subtitle: '本机保存的人格、模型配置与对话都不会被删除。',
      primary: ('退出', () {
        Navigator.of(context).pop();
        state.logout();
      }),
      secondary: ('取消', () => Navigator.of(context).pop()),
    );
  }

  /// 打开「主动找你」前先说清楚它是什么、以及不会立刻来消息，
  /// 避免用户以为一开就收到推送。关闭则直接关，不啰嗦。
  Future<void> _confirmProactive(
      BuildContext context, AppState state, bool v) async {
    if (!v) {
      await state.setProactiveChatEnabled(false);
      return;
    }
    await showSiniSheet<void>(
      context: context,
      title: '允许 TA 主动找你？',
      subtitle: '打开后，TA 会像真人一样，在合适的时候偶尔主动来找你说两句——'
          '不是定时推送，也不一定每天都有。说什么会结合你们的关系、'
          'TA 的性格和记住的事，深夜不会打扰你。',
      primary: ('打开并开启通知', () async {
        Navigator.of(context).pop();
        await state.setProactiveChatEnabled(true);
        // 顺手把系统通知也打开：这两个开关是一套体验，
        // 用户既然要"TA 主动来找我"，多半也希望离开页面时能被叫回来。
        if (context.mounted) {
          await _toggleSystemNotify(context, state, true);
        }
      }),
      tertiary: ('只打开，不要通知', () {
        Navigator.of(context).pop();
        state.setProactiveChatEnabled(true);
      }),
      secondary: ('先不用', () => Navigator.of(context).pop()),
    );
  }

  /// 整库备份：导出为 .sini-backup.json
  Future<void> _exportBackup(BuildContext context, AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = await state.exportBackupJson();
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '')
          .split('.')
          .first;
      final fileName = '似你整库备份_$ts.sini-backup.json';
      if (kIsWeb) {
        await saveAndNotify(
          context,
          () => downloadTextFile(fileName, json, 'application/json'),
          webMessage: '备份已开始下载，请妥善保存',
        );
        return;
      }
      final dir = await FilePicker.getDirectoryPath(dialogTitle: '选择备份保存文件夹');
      if (!context.mounted) return;
      if (dir == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已取消备份（未选择文件夹）')),
        );
        return;
      }
      var r = await exportTextToPickedDir(
        fileName: fileName,
        content: json,
        dirPath: dir,
      );
      if (!r.ok) {
        final fallback = await fallbackExportDir();
        r = await exportTextToPickedDir(
          fileName: fileName,
          content: json,
          dirPath: fallback.path,
        );
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.ok ? '备份已保存到\n${r.message}' : '备份失败：${r.message}'),
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('备份失败：$e')));
    }
  }

  /// 从 .sini-backup.json 整库恢复（会覆盖当前本机数据）
  Future<void> _importBackup(BuildContext context, AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (picked.isEmpty || !context.mounted) return;
      final f = picked.first;
      final bytes = await f.readAsBytes();
      final raw = utf8.decode(bytes, allowMalformed: true);
      final err = await state.importBackupJson(raw);
      if (!context.mounted) return;
      if (err == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('已从备份恢复，正在刷新界面…'),
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        messenger.showSnackBar(SnackBar(content: Text(err)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('恢复失败：$e')));
    }
  }

  Widget _section(String label, AppPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: p.textTertiary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _tile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required AppPalette p,
    bool danger = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: danger ? const Color(0xFFB42318) : p.textSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: danger ? const Color(0xFFB42318) : p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: p.textTertiary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: p.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required AppPalette p,
    IconData icon = Icons.dark_mode_outlined,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: p.textSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.textPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: p.textTertiary)),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// 联网搜索配置弹窗：选渠道 + 填 Key + 测试连接
Future<void> _showSearchConfig(BuildContext context, AppState state) async {
  String provider = state.searchProvider;
  final keyCtrl = TextEditingController(text: state.searchKey);
  String? testResult;
  bool testing = false;
  final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setSheet) => AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('联网搜索', style: TextStyle(color: p.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('渠道', style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: [
                  for (final sp in kSearchProviders)
                    ButtonSegment(
                        value: sp, label: Text(sp == 'tavily' ? 'Tavily' : '博查',
                            style: const TextStyle(fontSize: 12))),
                ],
                selected: {provider},
                onSelectionChanged: (sel) => setSheet(() => provider = sel.first),
              ),
              const SizedBox(height: 12),
              Text('API Key',
                  style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: keyCtrl,
                obscureText: true,
                style: TextStyle(fontSize: 13, color: p.textPrimary),
                decoration: InputDecoration(
                  hintText: '留空 = 用免费搜索源；填 Key 用${provider == 'tavily' ? ' Tavily（tvly-...）' : ' 博查'}',
                  hintStyle: TextStyle(fontSize: 12, color: p.textTertiary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),
              if (testResult != null)
                Text(testResult!,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: testResult!.startsWith('✅')
                            ? const Color(0xFF10A37F)
                            : const Color(0xFFB42318))),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: testing
                ? null
                : () async {
                    setSheet(() {
                      testing = true;
                      testResult = '测试中…';
                    });
                    final r = keyCtrl.text.trim().isEmpty && provider != 'free'
                        ? await webSearch(
                            query: '今天有什么新闻',
                            provider: 'free',
                            apiKey: '',
                            count: 3,
                          )
                        : await webSearch(
                            query: '今天有什么新闻',
                            provider: provider,
                            apiKey: keyCtrl.text,
                            count: 3,
                          );
                    setSheet(() {
                      testing = false;
                      testResult = r.ok
                          ? '✅ 连接成功，搜到 ${r.hits.length} 条结果'
                          : '❌ ${r.error}';
                    });
                  },
            child: Text(testing ? '测试中…' : '测试连接'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text('取消', style: TextStyle(color: p.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  if (ok == true) {
    await state.updateSearchConfig(provider: provider, key: keyCtrl.text);
  }
}
