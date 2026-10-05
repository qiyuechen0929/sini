import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_button.dart';
import '../../../core/widgets/sini_scaffold.dart';
import '../../../core/widgets/sini_sheet.dart';
import '../../../core/widgets/sini_text_field.dart';
import '../../../data/llm_provider.dart';
import '../../../theme.dart';
import '../../../app_state.dart';

/// 新增 / 编辑一条模型配置。
/// 传 null 表示新建；传 ModelConfig 表示编辑。
class ModelEditPage extends StatefulWidget {
  final ModelConfig? initial;
  const ModelEditPage({super.key, this.initial});

  bool get isEdit => initial != null;

  @override
  State<ModelEditPage> createState() => _ModelEditPageState();
}

class _ModelEditPageState extends State<ModelEditPage> {
  late String _providerId;
  late final TextEditingController _nameCtl;
  late final TextEditingController _baseCtl;
  late final TextEditingController _keyCtl;
  late final TextEditingController _modelCtl;

  bool _obscure = true;
  bool _loading = false;
  List<String> _available = const [];
  String? _fetchError;
  String? _selectedModel;
  bool _asDefault = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _providerId = init?.providerId ?? 'deepseek';
    _nameCtl = TextEditingController(text: init?.name ?? '');
    _baseCtl = TextEditingController(
        text: init?.baseUrl ?? LlmProvider.byId(_providerId).baseUrl);
    _keyCtl = TextEditingController(text: init?.apiKey ?? '');
    _modelCtl = TextEditingController(text: init?.modelId ?? '');
    _selectedModel = init?.modelId;
    _asDefault = init?.isDefault ?? false;
    if (init != null && init.modelId.isNotEmpty) {
      _available = [init.modelId];
    }
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _baseCtl.dispose();
    _keyCtl.dispose();
    _modelCtl.dispose();
    super.dispose();
  }

  void _onProviderChanged(String id) {
    setState(() {
      _providerId = id;
      final preset = LlmProvider.byId(id);
      _baseCtl.text = preset.baseUrl;
      _available = const [];
      _selectedModel = null;
      _modelCtl.clear();
      _fetchError = null;
      // 切供应商时清空已拉取的列表，避免拿到别的供应商的模型
      if (_nameCtl.text.trim().isEmpty ||
          _nameCtl.text.trim() == LlmProvider.byId(_providerId).name) {
        _nameCtl.text = preset.name;
      }
    });
  }

  /// 粗略判断一个模型 ID 是否像是「文生图」模型，仅用于在列表里打个小标识，
  /// 不强制过滤（对话/图片由模型 ID 在保存时自动判断）。
  static final _imageKeywords = [
    'image', 'flux', 'cogview', 'dall', 'wanx', 'kolors', 'seedream',
    'jimeng', 'hidream', 'sd3', 'stable-diffusion', 'imagen', 'ideogram',
    'recraft', 'midjourney', 'gpt-image',
  ];
  bool _isLikelyImageModel(String id) {
    final lower = id.toLowerCase();
    return _imageKeywords.any((k) => lower.contains(k));
  }

  Future<void> _fetch() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _fetchError = null;
    });
    final res = await fetchModels(
      baseUrl: _baseCtl.text.trim(),
      apiKey: _keyCtl.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        _available = res.ids;
        _fetchError = res.ids.isEmpty ? '这个 Key 下没有可用模型' : null;
        if (res.ids.isNotEmpty) {
          _selectedModel ??= res.ids.first;
          _modelCtl.text = _selectedModel!;
        }
      } else {
        _available = const [];
        _fetchError = res.error;
      }
    });
  }

  Future<void> _save() async {
    final modelId = _modelCtl.text.trim();
    final name = _nameCtl.text.trim().isEmpty ? modelId : _nameCtl.text.trim();
    final key = _keyCtl.text.trim();
    // 本地 / 自建服务（Ollama、LM Studio…）不需要 Key，留空时填占位值
    // （请求仍要带 Authorization 头，给个非空占位即可）
    final isLocal = LlmProvider.byId(_providerId).group == ProviderGroup.local;
    if (key.isEmpty && !isLocal) {
      _toast('请填写 API Key');
      return;
    }
    if (modelId.isEmpty) {
      _toast('请选择或填写模型 ID');
      return;
    }
    final state = AppStateScope.of(context);
    final cfg = ModelConfig(
      id: widget.initial?.id ?? 'mc_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      providerId: _providerId,
      modelId: modelId,
      apiKey: key.isEmpty ? 'local' : key,
      baseUrl: _baseCtl.text.trim(),
      isDefault: _asDefault,
    );
    if (widget.isEdit) {
      await state.updateModelConfig(cfg);
    } else {
      await state.addModelConfig(cfg);
    }
    if (_asDefault) await state.setDefaultModelConfig(cfg.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1400)),
    );
  }

  Future<void> _confirmDelete() async {
    final cfg = widget.initial;
    if (cfg == null) return;
    await showSiniSheet<void>(
      context: context,
      title: '删除模型配置？',
      subtitle: '「${cfg.name}」及其 API Key 将从本机移除。',
      danger: true,
      primary: ('删除', () async {
        Navigator.of(context).pop();
        await AppStateScope.of(context).deleteModelConfig(cfg.id);
        if (mounted) Navigator.of(context).pop();
      }),
      secondary: ('取消', () => Navigator.of(context).pop()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return SiniScaffold(
      title: widget.isEdit ? '编辑模型' : '添加模型',
      actions: [
        if (widget.isEdit)
          IconButton(
            tooltip: '删除',
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: p.textPrimary),
            onPressed: _confirmDelete,
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.xxxl),
        children: [
          _section('供应商', p),
          const SizedBox(height: Spacing.sm),
          _ProviderSelect(
            selected: LlmProvider.byId(_providerId),
            onChanged: _onProviderChanged,
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            LlmProvider.byId(_providerId).hint,
            style: TextStyle(fontSize: SiniText.labelSm, color: p.textTertiary),
          ),
          const SizedBox(height: Spacing.xl),
          SiniTextField(
            controller: _baseCtl,
            label: 'Base URL',
            hintText: 'https://api.example.com/v1',
          ),
          const SizedBox(height: Spacing.md),
          SiniTextField(
            controller: _keyCtl,
            label: 'API Key',
            hintText: 'sk-...',
            obscureText: _obscure,
            onChanged: (_) => setState(() {}),
            suffixIcon: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 18,
                color: p.textTertiary,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: Spacing.md),
          // —— 模型选择 ——
          // 对话模型：可拉列表选择；图片模型：部分供应商（如硅基流动）会列出
          // 生图模型可直接选，纯文本供应商（DeepSeek 等）拉不到则手动填。
          SiniButton(
            label: _loading ? '正在获取…' : '获取模型列表',
            leadingIcon: Icons.cloud_download_outlined,
            onTap: _loading ? null : _fetch,
            style: SiniButtonStyle.secondary,
            expand: true,
            height: 46,
          ),
          if (_loading) ...[
            const SizedBox(height: Spacing.md),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (_fetchError != null) ...[
            const SizedBox(height: Spacing.md),
            _errorBox(p, _fetchError!),
          ],
          if (_available.isNotEmpty) ...[
            const SizedBox(height: Spacing.lg),
            _section('选择模型（${_available.length}）', p),
            const SizedBox(height: Spacing.sm),
            Container(
              decoration: BoxDecoration(
                color: p.itemHover,
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
              child: Column(
                children: [
                  for (final id in _available)
                    RadioListTile<String>(
                      value: id,
                      groupValue: _selectedModel,
                      onChanged: (v) => setState(() {
                        _selectedModel = v;
                        _modelCtl.text = v ?? '';
                      }),
                      dense: true,
                      title: Text(
                        id,
                        style: TextStyle(
                            fontSize: SiniText.bodySm, color: p.textPrimary),
                      ),
                      secondary: _isLikelyImageModel(id)
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: p.brand.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '生图',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: p.brand,
                                    fontWeight: FontWeight.w600),
                              ),
                            )
                          : null,
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Spacing.lg),
          SiniTextField(
            controller: _modelCtl,
            label: '模型 ID',
            hintText: '例如 deepseek-chat / glm-image',
          ),
          const SizedBox(height: Spacing.xl),
          _section('显示名称', p),
          const SizedBox(height: Spacing.sm),
          SiniTextField(
            controller: _nameCtl,
            hintText: '留空则使用模型 ID',
          ),
          const SizedBox(height: Spacing.lg),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('设为默认模型',
                style: TextStyle(fontSize: SiniText.bodyMd, color: p.textPrimary)),
            value: _asDefault,
            onChanged: (v) => setState(() => _asDefault = v),
          ),
          const SizedBox(height: Spacing.xl),
          SiniButton(
            label: '保存',
            onTap: _save,
            style: SiniButtonStyle.primary,
            expand: true,
            height: 48,
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'API Key 只保存在这台设备的浏览器本地，不会上传到似你服务器。',
            style: TextStyle(fontSize: SiniText.labelSm, color: p.textTertiary, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _section(String text, AppPalette p) {
    return Text(
      text,
      style: TextStyle(
        fontSize: SiniText.labelMd,
        fontWeight: FontWeight.w600,
        color: p.textSecondary,
      ),
    );
  }

  Widget _errorBox(AppPalette p, String msg) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFB42318).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFB42318)),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFFB42318),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

}

/// 供应商「下拉选择框」：收起时是一个输入框样式的选择框，
/// 点击后弹出分组列表（支持搜索）——供应商多的时候比平铺 chip 好用得多。
class _ProviderSelect extends StatelessWidget {
  final LlmProvider selected;
  final ValueChanged<String> onChanged;
  const _ProviderSelect({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return Material(
      color: p.itemHover,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: () => _openPicker(context),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selected.name,
                  style: TextStyle(
                    fontSize: SiniText.bodyMd,
                    color: p.textPrimary,
                  ),
                ),
              ),
              Icon(Icons.unfold_more_rounded, size: 18, color: p.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  void _openPicker(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    String keyword = '';

    showSiniSheet<void>(
      context: context,
      title: '选择供应商',
      subtitle: '共 ${LlmProvider.presets.length} 个预设，支持搜索',
      child: StatefulBuilder(
        builder: (ctx, setSheetState) {
          // 按关键字过滤（匹配名称 / id / hint）
          bool match(LlmProvider v) {
            if (keyword.isEmpty) return true;
            final k = keyword.toLowerCase();
            return v.name.toLowerCase().contains(k) ||
                v.id.contains(k) ||
                v.hint.toLowerCase().contains(k);
          }

          final groups = ProviderGroup.values
              .where((g) => LlmProvider.byGroup(g).any(match))
              .toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 搜索框
              TextField(
                autofocus: false,
                onChanged: (v) => setSheetState(() => keyword = v.trim()),
                style: TextStyle(fontSize: SiniText.bodyMd, color: p.textPrimary),
                decoration: InputDecoration(
                  hintText: '搜索供应商…',
                  hintStyle:
                      TextStyle(fontSize: SiniText.bodyMd, color: p.textTertiary),
                  prefixIcon:
                      Icon(Icons.search_rounded, size: 18, color: p.textTertiary),
                  filled: true,
                  fillColor: p.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
              const SizedBox(height: Spacing.md),
              // 分组列表
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final g in groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
                        child: Text(
                          g.label,
                          style: TextStyle(
                            fontSize: SiniText.labelSm,
                            fontWeight: FontWeight.w600,
                            color: p.textTertiary,
                          ),
                        ),
                      ),
                      for (final prov in LlmProvider.byGroup(g))
                        if (match(prov))
                          _ProviderTile(
                            prov: prov,
                            selected: prov.id == selected.id,
                            p: p,
                            onTap: () {
                              Navigator.pop(ctx);
                              onChanged(prov.id);
                            },
                          ),
                    ],
                    const SizedBox(height: Spacing.sm),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      tertiary: ('取消', () => Navigator.of(context).pop()),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  final LlmProvider prov;
  final bool selected;
  final AppPalette p;
  final VoidCallback onTap;
  const _ProviderTile({
    required this.prov,
    required this.selected,
    required this.p,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? p.itemActive : Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm + 2, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      prov.name,
                      style: TextStyle(
                        fontSize: SiniText.bodyMd,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: p.textPrimary,
                      ),
                    ),
                    if (prov.baseUrl.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        prov.baseUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: SiniText.labelSm,
                          color: p.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, size: 18, color: p.brand),
            ],
          ),
        ),
      ),
    );
  }
}
