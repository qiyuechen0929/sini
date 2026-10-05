import 'package:flutter/material.dart';

import 'app_router.dart';
import 'app_state.dart';
import 'data/llm_provider.dart' show onTokenUsage;
import 'theme.dart';
import 'utils/audio_bootstrap.dart' show ensureAudioReady;
import 'utils/connectors.dart' show ConnectorApi;
import 'utils/safe_text.dart' show safeClip;
import 'utils/usage_store.dart';

void main() {
  // 调试兜底：框架错误除了进浏览器控制台，还把「第一条」抓出来直接画在页面上。
  // 背景：导入面板曾在浏览器里白屏而 widget 测试正常，控制台的第一条异常
  // 被后续刷屏淹没查不到——画在页面上谁都能截图。
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    try {
      _ErrorSink.record(details.exception.toString());
    } catch (_) {
      _ErrorSink.record('框架异常（无法完整显示）');
    }
    originalOnError?.call(details);
  };
  ErrorWidget.builder = (details) {
    String msg;
    try {
      msg = details.toString();
    } catch (_) {
      msg = '无法渲染的错误对象';
    }
    return _ErrorBox(message: msg);
  };
  // Android 预设音色试听 / AI 朗读：不先设 AudioContext 很容易静音
  ensureAudioReady();
  runApp(const SiniApp());
}

/// 全局错误信箱：记录第一条框架错误，页面顶部红条展示
class _ErrorSink {
  static final ValueNotifier<String?> latest = ValueNotifier(null);
  static void record(String s) {
    String safe;
    try {
      safe = s;
    } catch (_) {
      safe = '无法序列化的错误';
    }
    latest.value ??= safeClip(safe, 1200) + (safe.length > 1200 ? '…' : '');
  }
}

/// 页面内错误显示：红底滚动文本，替代默认的灰屏 / 红屏
class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFFF1F0),
      padding: const EdgeInsets.all(12),
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        child: Text(
          '⚠️ 页面渲染出错（请把这段截图给开发者）\n\n'
          '${safeClip(message, 1500)}${message.length > 1500 ? '…' : ''}',
          style: const TextStyle(color: Color(0xFFB42318), fontSize: 12),
        ),
      ),
    );
  }
}

class SiniApp extends StatefulWidget {
  const SiniApp({super.key});

  @override
  State<SiniApp> createState() => _SiniAppState();
}

class _SiniAppState extends State<SiniApp> {
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    // Token 用量统计：LLM 层每笔消耗投递到全局 store（设置页「用量统计」读它）
    UsageStore.instance.load();
    onTokenUsage = (providerId, modelId, pt, ct, tt, personaName) {
      UsageStore.instance.add(UsageEvent(
        providerId: providerId,
        modelId: modelId,
        promptTokens: pt,
        completionTokens: ct,
        totalTokens: tt,
        ts: DateTime.now(),
        personaName: personaName,
      ));
    };
    _state = AppState();
    // 连接器/搜索代理的电脑地址：启动就恢复，否则一打开就搜会打空
    ConnectorApi.loadFromPrefs();
    // 读回本机保存的模型配置 / 账号（异步，完成后自己 notify）
    _state.restore();
    // 只有存在人格时才预开对话；首次启动没有任何人格，首页走「创建引导」
    if (_state.hasPersonas) {
      _state.selectPersona(_state.personas.first.id);
      if (_state.activeConversationId == null) _state.newConversation();
    }
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      state: _state,
      child: _ThemedApp(state: _state),
    );
  }
}

class _ThemedApp extends StatelessWidget {
  final AppState state;
  const _ThemedApp({required this.state});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return MaterialApp(
          title: '似你',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: state.themeMode,
          // 首屏路由。优先级：URL 上的 `?route=/xxx`（手机壳预览靠它跳二级页，
          // 编译一次之后还能随便换页）> 编译期 `--dart-define=SINI_ROUTE` > 首页。
          // Flutter 用的是手写路由、URL 不同步，没有它就只能靠手动点进去。
          initialRoute: _initialRoute(),
          onGenerateRoute: appRouter,
          builder: (context, child) => Stack(
            children: [
              child ?? const SizedBox.shrink(),
              const _ErrorBanner(),
              const _NightGuardOverlay(),
            ],
          ),
        );
      },
    );
  }
}

/// 首屏路由：`?route=/xxx` 这类查询参数优先。
/// 非 Web（flutter test / VM）下 [Uri.base] 是工作目录路径，没有查询参数，
/// 会自然回落到编译期常量或首页。
String _initialRoute() {
  try {
    final q = Uri.base.queryParameters['route'];
    if (q != null && q.startsWith('/')) return q;
  } catch (_) {
    // 拿不到就按默认走
  }
  return const String.fromEnvironment('SINI_ROUTE',
      defaultValue: AppRoutes.home);
}

/// 深夜守护小弹窗：TA 在聊天里补了劝睡消息后，屏幕底部弹一下
class _NightGuardOverlay extends StatelessWidget {
  const _NightGuardOverlay();

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (ctx) {
        final state = AppStateScope.of(ctx);
        final msg = state.nightGuardDialog;
        if (msg == null) return const SizedBox.shrink();
        final p = AppPalette(isDark: Theme.of(ctx).brightness == Brightness.dark);
        return Positioned(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 88,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () => state.dismissNightGuardDialog(),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text('🌙', style: TextStyle(fontSize: 18)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${state.activePersona?.name ?? 'TA'} 让你去睡觉',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: p.brand,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            msg,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: p.textPrimary,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '点一下收起 · 详情在聊天里',
                            style: TextStyle(fontSize: 11, color: p.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close_rounded, size: 18, color: p.textTertiary),
                      onPressed: () => state.dismissNightGuardDialog(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 页面顶部的错误红条：出现第一条框架错误就显示，可点 ✕ 收起
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: _ErrorSink.latest,
      builder: (context, err, _) {
        if (err == null) return const SizedBox.shrink();
        return Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Material(
            color: const Color(0xFFB42318),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '⚠️ 运行出错：$err',
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _ErrorSink.latest.value = null,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded,
                            size: 16, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
