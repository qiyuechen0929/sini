import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/safe_text.dart' show safeHead;

/// 供应商分组，用于下拉选择时分区展示
enum ProviderGroup {
  domestic('国内大模型'),
  global('国际大模型'),
  aggregator('中转 / 聚合'),
  local('本地 / 自建'),
  custom('自定义');

  final String label;
  const ProviderGroup(this.label);
}

/// 模型供应商预设。baseUrl 都填 OpenAI 兼容格式，拼接 `${baseUrl}/models` 取模型列表。
class LlmProvider {
  final String id;
  final String name;
  final String baseUrl;
  final String hint;
  final ProviderGroup group;
  const LlmProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.hint,
    this.group = ProviderGroup.custom,
  });

  static const List<LlmProvider> presets = [
    // ---- 国内大模型 ----
    LlmProvider(
      id: 'deepseek',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      hint: 'deepseek-chat / deepseek-reasoner',
      group: ProviderGroup.domestic,
    ),
    LlmProvider(
      id: 'qwen',
      name: '通义千问',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      hint: '阿里云百炼 · qwen-plus / qwen-max',
      group: ProviderGroup.domestic,
    ),
    LlmProvider(
      id: 'zhipu',
      name: '智谱 GLM',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      hint: 'glm-4-flash / glm-4-plus',
      group: ProviderGroup.domestic,
    ),
    LlmProvider(
      id: 'moonshot',
      name: 'Kimi',
      baseUrl: 'https://api.moonshot.cn/v1',
      hint: '月之暗面 · moonshot-v1-8k',
      group: ProviderGroup.domestic,
    ),
    LlmProvider(
      id: 'doubao',
      name: '豆包（火山方舟）',
      baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      hint: '模型 ID 填「接入点 ID」，如 ep-2024xxxx',
      group: ProviderGroup.domestic,
    ),
    LlmProvider(
      id: 'hunyuan',
      name: '腾讯混元',
      baseUrl: 'https://api.hunyuan.cloud.tencent.com/v1',
      hint: 'hunyuan-turbo / hunyuan-pro',
      group: ProviderGroup.domestic,
    ),
    LlmProvider(
      id: 'qianfan',
      name: '百度千帆',
      baseUrl: 'https://qianfan.baidubce.com/v2',
      hint: '文心 · ernie-4.0 / ernie-speed',
      group: ProviderGroup.domestic,
    ),
    LlmProvider(
      id: 'spark',
      name: '讯飞星火',
      baseUrl: 'https://spark-api-open.xf-yun.com/v1',
      hint: 'generalv3 / pro-128k',
      group: ProviderGroup.domestic,
    ),
    LlmProvider(
      id: 'minimax',
      name: 'MiniMax',
      baseUrl: 'https://api.minimaxi.com/v1',
      hint: 'MiniMax-Text-01（该平台无 /models，需手填）',
      group: ProviderGroup.domestic,
    ),
    LlmProvider(
      id: 'lingyi',
      name: '零一万物',
      baseUrl: 'https://api.lingyiwanwu.com/v1',
      hint: 'yi-large / yi-medium',
      group: ProviderGroup.domestic,
    ),
    LlmProvider(
      id: 'stepfun',
      name: '阶跃星辰',
      baseUrl: 'https://api.stepfun.com/v1',
      hint: 'step-1 / step-2',
      group: ProviderGroup.domestic,
    ),

    // ---- 国际大模型 ----
    LlmProvider(
      id: 'openai',
      name: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      hint: 'gpt-4o / gpt-4o-mini',
      group: ProviderGroup.global,
    ),
    LlmProvider(
      id: 'anthropic',
      name: 'Anthropic Claude',
      baseUrl: 'https://api.anthropic.com/v1',
      hint: '兼容层（chat 可用，/models 可能受限）',
      group: ProviderGroup.global,
    ),
    LlmProvider(
      id: 'gemini',
      name: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      hint: '官方 OpenAI 兼容层（末尾不要加斜杠）',
      group: ProviderGroup.global,
    ),
    LlmProvider(
      id: 'xai',
      name: 'xAI Grok',
      baseUrl: 'https://api.x.ai/v1',
      hint: 'grok-3 / grok-4',
      group: ProviderGroup.global,
    ),
    LlmProvider(
      id: 'groq',
      name: 'Groq',
      baseUrl: 'https://api.groq.com/openai/v1',
      hint: '极速推理 · llama-3.3-70b',
      group: ProviderGroup.global,
    ),
    LlmProvider(
      id: 'mistral',
      name: 'Mistral AI',
      baseUrl: 'https://api.mistral.ai/v1',
      hint: 'mistral-large-latest / codestral',
      group: ProviderGroup.global,
    ),
    LlmProvider(
      id: 'together',
      name: 'Together AI',
      baseUrl: 'https://api.together.xyz/v1',
      hint: '开源模型聚合',
      group: ProviderGroup.global,
    ),
    LlmProvider(
      id: 'fireworks',
      name: 'Fireworks AI',
      baseUrl: 'https://api.fireworks.ai/inference/v1',
      hint: '开源模型推理',
      group: ProviderGroup.global,
    ),

    // ---- 中转 / 聚合 ----
    LlmProvider(
      id: 'siliconflow',
      name: '硅基流动',
      baseUrl: 'https://api.siliconflow.cn/v1',
      hint: '国内聚合 · 多模型，注册送额度',
      group: ProviderGroup.aggregator,
    ),
    LlmProvider(
      id: 'openrouter',
      name: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      hint: '全球最大中转 · 100+ 模型',
      group: ProviderGroup.aggregator,
    ),
    LlmProvider(
      id: 'aihubmix',
      name: 'AIHubMix',
      baseUrl: 'https://api.aihubmix.com/v1',
      hint: '国产中转聚合',
      group: ProviderGroup.aggregator,
    ),
    LlmProvider(
      id: '302ai',
      name: '302.AI',
      baseUrl: 'https://api.302.ai/v1',
      hint: '按需付费中转',
      group: ProviderGroup.aggregator,
    ),
    LlmProvider(
      id: 'dmxapi',
      name: 'DMXAPI',
      baseUrl: 'https://www.dmxapi.cn/v1',
      hint: '国产中转聚合',
      group: ProviderGroup.aggregator,
    ),
    LlmProvider(
      id: 'giteeai',
      name: 'Gitee AI',
      baseUrl: 'https://ai.gitee.com/v1',
      hint: '码云 AI · 国内可用',
      group: ProviderGroup.aggregator,
    ),

    // ---- 本地 / 自建 ----
    LlmProvider(
      id: 'ollama',
      name: 'Ollama（本地）',
      baseUrl: 'http://localhost:11434/v1',
      hint: '本地运行，API Key 可随便填',
      group: ProviderGroup.local,
    ),
    LlmProvider(
      id: 'lmstudio',
      name: 'LM Studio（本地）',
      baseUrl: 'http://localhost:1234/v1',
      hint: '本地运行，API Key 可随便填',
      group: ProviderGroup.local,
    ),
    LlmProvider(
      id: 'vllm',
      name: 'vLLM（自建）',
      baseUrl: 'http://localhost:8000/v1',
      hint: '自建推理服务',
      group: ProviderGroup.local,
    ),

    // ---- 自定义 ----
    LlmProvider(
      id: 'custom',
      name: '自定义',
      baseUrl: '',
      hint: '任意 OpenAI 兼容接口 / 自建代理',
      group: ProviderGroup.custom,
    ),
  ];

  static LlmProvider byId(String id) =>
      presets.firstWhere((p) => p.id == id, orElse: () => presets.first);

  /// 按分组取供应商，用于下拉面板分区展示
  static List<LlmProvider> byGroup(ProviderGroup g) =>
      presets.where((p) => p.group == g).toList();
}

/// 模型用途：对话补全 / 图片生成
enum ModelKind { chat, image }

/// 图片模型预设（与对话模型分开挑，避免用户在几百个文本模型里找画图模型）
class ImageModelPreset {
  final String label;
  final String modelId;
  final String note;
  const ImageModelPreset(this.label, this.modelId, this.note);

  static const List<ImageModelPreset> presets = [
    ImageModelPreset('GLM-Image（智谱旗舰·推荐）', 'glm-image',
        '文字渲染开源 SOTA，海报/PPT/科普图强 · ¥0.1/张'),
    ImageModelPreset('CogView-4（智谱）', 'cogView-4-250304',
        '支持汉字生成，中英双语 · 按量计费'),
    ImageModelPreset('CogView-3-Flash（智谱·免费）', 'cogview-3-flash',
        '免费额度，速度快，适合跑通流程'),
    ImageModelPreset('gpt-image-1（OpenAI）', 'gpt-image-1',
        '效果最好，需海外 Key'),
    ImageModelPreset('FLUX.1-schnell（硅基流动）',
        'black-forest-labs/FLUX.1-schnell', '中转聚合，免费额度'),
    ImageModelPreset('Kolors（硅基流动）', 'Kwai-Kolors/Kolors',
        '中文理解好，国内直连'),
    ImageModelPreset('wanx2.1-t2i-turbo（通义万相）', 'wanx2.1-t2i-turbo',
        '阿里 DashScope，稳定'),
  ];
}

/// 粗略判断一个模型 ID 是否像是「文生图」模型。
/// 因为各供应商的 /models 接口不标注能力类型，只能靠 ID 关键词判断。
bool _looksLikeImageModel(String id) {
  final lower = id.toLowerCase();
  const kws = [
    'image', 'flux', 'cogview', 'dall', 'wanx', 'kolors', 'seedream',
    'jimeng', 'hidream', 'sd3', 'stable-diffusion', 'imagen', 'ideogram',
    'recraft', 'midjourney', 'gpt-image',
  ];
  return kws.any((k) => lower.contains(k));
}

/// 一条已保存的模型配置
class ModelConfig {
  final String id;
  final String name;
  final String providerId;
  final String modelId;
  final String apiKey;
  final String baseUrl;
  final bool isDefault;

  const ModelConfig({
    required this.id,
    required this.name,
    required this.providerId,
    required this.modelId,
    required this.apiKey,
    required this.baseUrl,
    this.isDefault = false,
  });

  ModelConfig copyWith({
    String? name,
    String? providerId,
    String? modelId,
    String? apiKey,
    String? baseUrl,
    bool? isDefault,
  }) =>
      ModelConfig(
        id: id,
        name: name ?? this.name,
        providerId: providerId ?? this.providerId,
        modelId: modelId ?? this.modelId,
        apiKey: apiKey ?? this.apiKey,
        baseUrl: baseUrl ?? this.baseUrl,
        isDefault: isDefault ?? this.isDefault,
      );

  /// 用途（对话 / 图片生成）由模型 ID 自动判断，不手动选择。
  /// 含 image/flux/cogview/wanx 等关键词的模型视为生图模型（走 /images/generations）。
  ModelKind get kind => _looksLikeImageModel(modelId) ? ModelKind.image : ModelKind.chat;

  bool get isImage => kind == ModelKind.image;

  String get providerName => LlmProvider.byId(providerId).name;

  /// Key 只留首尾，中间打码
  String get maskedKey {
    if (apiKey.length <= 10) return '••••••••';
    return '${apiKey.substring(0, 6)}••••${apiKey.substring(apiKey.length - 4)}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'providerId': providerId,
        'modelId': modelId,
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'isDefault': isDefault,
      };

  static ModelConfig fromJson(Map<String, dynamic> j) => ModelConfig(
        id: j['id'] as String,
        name: j['name'] as String? ?? '未命名模型',
        providerId: j['providerId'] as String? ?? 'custom',
        modelId: j['modelId'] as String? ?? '',
        apiKey: j['apiKey'] as String? ?? '',
        baseUrl: j['baseUrl'] as String? ?? '',
        isDefault: j['isDefault'] as bool? ?? false,
      );
}

/// 拉取结果：要么拿到 ids，要么拿到一条给人看的错误
class FetchModelsResult {
  final List<String> ids;
  final String? error;
  const FetchModelsResult.ok(this.ids) : error = null;
  const FetchModelsResult.fail(this.error) : ids = const [];
  bool get ok => error == null;
}

/// 真实去供应商拉 `/models`。
/// 注意：Web 端直连多数会被浏览器 CORS 拦截（OpenAI/DeepSeek 默认不开放跨域），
/// 这时返回可读错误，用户可以改用自建代理地址或手动填模型 ID。
Future<FetchModelsResult> fetchModels({
  required String baseUrl,
  required String apiKey,
}) async {
  final url = baseUrl.trim();
  if (url.isEmpty) return const FetchModelsResult.fail('请填写 Base URL');
  if (apiKey.trim().isEmpty) return const FetchModelsResult.fail('请填写 API Key');

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    headers: {
      'Authorization': 'Bearer ${apiKey.trim()}',
      'Content-Type': 'application/json',
    },
    // 供应商返回非 2xx 时不抛异常，自己解析状态码
    validateStatus: (_) => true,
  ));

  try {
    final res = await dio.get<dynamic>('${_trimSlash(url)}/models');
    final status = res.statusCode ?? 0;
    if (status >= 400) {
      return FetchModelsResult.fail(_statusMessage(status));
    }
    final body = res.data;
    if (body is Map<String, dynamic>) {
      final data = body['data'];
      if (data is List) {
        return FetchModelsResult.ok(_extractIds(data));
      }
    } else if (body is List) {
      return FetchModelsResult.ok(_extractIds(body));
    } else if (body is String) {
      // 极少数代理返回 JSON 字符串
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic> && decoded['data'] is List) {
          return FetchModelsResult.ok(_extractIds(decoded['data'] as List));
        }
      } catch (_) {}
    }
    return const FetchModelsResult.fail('返回格式无法识别，请检查 Base URL');
  } on DioException catch (e) {
    return FetchModelsResult.fail(_dioMessage(e));
  } catch (e) {
    final msg = e.toString();
    if (msg.contains('XMLHttpRequest') || msg.contains('CORS')) {
      return const FetchModelsResult.fail(
          '浏览器跨域被拒（CORS）。请用自建代理地址，或点击下方「手动填写模型 ID」。');
    }
    return FetchModelsResult.fail('请求失败：$msg');
  }
}

List<String> _extractIds(List list) {
  final ids = <String>[];
  for (final item in list) {
    if (item is Map) {
      final id = item['id'] ?? item['name'];
      if (id is String && id.isNotEmpty) ids.add(id);
    } else if (item is String && item.isNotEmpty) {
      ids.add(item);
    }
  }
  ids.sort();
  return ids;
}

String _trimSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

String _statusMessage(int status) {
  switch (status) {
    case 401:
      return '401 未授权：API Key 无效或已过期';
    case 403:
      return '403 禁止访问：Key 没有该接口的权限';
    case 404:
      return '404 找不到接口：Base URL 可能不对';
    case 429:
      return '429 请求过于频繁，稍后再试';
    default:
      return '$status 请求失败，请检查 Base URL 与 Key';
  }
}

String _dioMessage(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return '连接超时，检查网络或代理地址';
    case DioExceptionType.connectionError:
      return '无法连接服务器。Web 端常见原因是供应商不允许浏览器跨域（CORS），'
          '请改用自建代理地址，或点「手动填写模型 ID」。';
    case DioExceptionType.badResponse:
      return _statusMessage(e.response?.statusCode ?? 0);
    default:
      return e.message ?? '请求失败';
  }
}

/// 一次非流式聊天补全的结果：要么拿到文本，要么拿到可读错误。
/// Token 用量钩子：每次 LLM 调用成功后回调（用量统计面板的数据源）。
/// llm_provider 保持纯函数不碰存储，由外层（main）把它接到 UsageStore。
/// 当前调用归属的人格名（AppState 在发起调用前设置，用于按人格统计用量）
String? usagePersonaName;

void Function(String providerId, String modelId, int promptTokens,
        int completionTokens, int totalTokens, String? personaName)?
    onTokenUsage;

class ChatResult {
  final String? content;
  final String? error;
  final int? status;
  final String? head;
  final String? finishReason;
  final String? reasoningContent;
  const ChatResult.ok(
    this.content, {
    this.status,
    this.head,
    this.finishReason,
    this.reasoningContent,
  }) : error = null;
  const ChatResult.fail(
    this.error, {
    this.status,
    this.head,
    this.finishReason,
    this.reasoningContent,
  }) : content = null;
  bool get ok => error == null;
}

/// 调 OpenAI 兼容的 `/chat/completions`（非流式），返回完整文本或可读错误。
/// 在 Web 端直连供应商可能被浏览器 CORS 拦截，此时返回 CORS 提示，
/// 用户可把模型 Base URL 改成带 CORS 头的代理地址绕过。
///
/// 说明：部分推理模型（如 deepseek-reasoner）会把 token 预算大量消耗在
/// 「思考(reasoning_content)」上，导致真正的回答 content 为空。这里在检测到
/// 空内容时会自动把 max_tokens 翻倍重试一次，避免用户看到「返回空内容，请重试」。
Future<ChatResult> chatComplete({
  required ModelConfig cfg,
  required List<Map<String, dynamic>> messages,
  double temperature = 0.8,
  int maxTokens = 4096,
}) async {
  final url = cfg.baseUrl.trim();
  final key = cfg.apiKey.trim();
  final model = cfg.modelId.trim();
  if (url.isEmpty) return const ChatResult.fail('模型未配置 Base URL');
  if (key.isEmpty) return const ChatResult.fail('模型未配置 API Key');
  if (model.isEmpty) return const ChatResult.fail('模型 ID 为空（请在模型设置里填写）');

  int budget = maxTokens;
  ChatResult? last;
  for (int attempt = 0; attempt < 2; attempt++) {
    final r = await _postChat(
      cfg: cfg,
      messages: messages,
      temperature: temperature,
      maxTokens: budget,
    );
    last = r;
    // 成功且非空，直接返回
    if (r.ok && (r.content?.trim().isNotEmpty ?? false)) return r;
    // 空内容（推理模型把额度用在思考上 / 复杂任务超预算）：翻倍预算再试一次
    if (r.ok && (r.content?.trim().isEmpty ?? true)) {
      if (attempt == 0) {
        print('[sini:http] 返回空内容，自动以 max_tokens=${budget * 2} 重试一次');
        budget *= 2;
        continue;
      }
      return r;
    }
    // 真正的错误（401 / CORS / 解析失败）不再重试
    return r;
  }
  return last!;
}

/// 流式调用 `/chat/completions`（SSE），边收边把增量文本交给 [onDelta]。
///
/// 语音通话专用：模型吐出第一句就能立刻送去合成，不用等整段写完 ——
/// 首字出声时间能省掉「整段生成」那几秒，通话节奏全靠这个。
///
/// 返回值和 [chatComplete] 一致（完整文本或可读错误）。
/// 容错：有些供应商/代理会忽略 `stream: true` 直接回一整段 JSON，
/// 这里会自动退回按非流式解析；中途 [isCancelled] 为真则提前收尾，
/// 已收到的部分照常返回（用户打断时用）。
Future<ChatResult> chatCompleteStream({
  required ModelConfig cfg,
  required List<Map<String, dynamic>> messages,
  double temperature = 0.8,
  int maxTokens = 4096,
  void Function(String delta)? onDelta,
  bool Function()? isCancelled,
}) async {
  final url = cfg.baseUrl.trim();
  final key = cfg.apiKey.trim();
  final model = cfg.modelId.trim();
  if (url.isEmpty) return const ChatResult.fail('模型未配置 Base URL');
  if (key.isEmpty) return const ChatResult.fail('模型未配置 API Key');
  if (model.isEmpty) return const ChatResult.fail('模型 ID 为空（请在模型设置里填写）');

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 120),
    headers: {
      'Authorization': 'Bearer $key',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    },
    validateStatus: (_) => true,
  ));

  final isDeepSeek =
      cfg.providerId == 'deepseek' || url.toLowerCase().contains('deepseek');
  final data = <String, dynamic>{
    'model': model,
    'messages': messages,
    'temperature': temperature,
    'max_tokens': maxTokens,
    'stream': true,
    if (isDeepSeek) 'thinking': {'type': 'disabled'},
    // OpenAI 兼容字段：让供应商在最后一个 chunk 带 usage（不支持的会忽略）
    'stream_options': {'include_usage': true},
  };

  final fullUrl = '${_trimSlash(url)}/chat/completions';
  try {
    final res = await dio.post<ResponseBody>(
      fullUrl,
      data: data,
      options: Options(responseType: ResponseType.stream),
    );
    final status = res.statusCode ?? 0;
    print('[sini:http] POST(stream) $fullUrl -> $status model=$model');
    if (status >= 400) {
      final text = res.data == null ? '' : await _readAllText(res.data!);
      print('[sini:http] stream body=$text');
      return ChatResult.fail(_statusMessage(status), status: status);
    }
    final body = res.data;
    if (body == null) return ChatResult.fail('流式响应为空', status: status);

    final content = StringBuffer();
    final reasoning = StringBuffer();
    final rawAll = StringBuffer();
    String? finish;
    Map? streamUsage;
    var done = false;
    var carry = '';

    void handleLine(String line) {
      final l = line.trim();
      if (l.isEmpty || !l.startsWith('data:')) return;
      final payload = l.substring(5).trim();
      if (payload == '[DONE]') {
        done = true;
        return;
      }
      Map<String, dynamic>? obj;
      try {
        final v = jsonDecode(payload);
        if (v is Map<String, dynamic>) obj = v;
      } catch (_) {
        return; // 半截 JSON（跨 chunk 切断）直接跳过，SSE 本身会重发完整行
      }
      if (obj == null) return;
      // include_usage 的最后一个 chunk 只有 usage 没有 choices
      final u = obj['usage'];
      if (u is Map && streamUsage == null) {
        streamUsage = u;
      }
      final choices = obj['choices'];
      if (choices is! List || choices.isEmpty) return;
      final c0 = choices[0];
      if (c0 is! Map) return;
      final d = c0['delta'];
      if (d is Map) {
        final t = d['content'];
        if (t is String && t.isNotEmpty) {
          content.write(t);
          onDelta?.call(t);
        }
        final rc = d['reasoning_content'];
        if (rc is String && rc.isNotEmpty) reasoning.write(rc);
      }
      final f = c0['finish_reason'];
      if (f is String && f.isNotEmpty) finish = f;
    }

    await for (final chunk in body.stream) {
      if (isCancelled?.call() == true) break;
      final text = utf8.decode(chunk, allowMalformed: true);
      rawAll.write(text);
      carry += text;
      var idx = carry.indexOf('\n');
      while (idx != -1) {
        handleLine(carry.substring(0, idx));
        carry = carry.substring(idx + 1);
        if (done) break;
        idx = carry.indexOf('\n');
      }
      if (done) break;
    }
    if (!done && carry.trim().isNotEmpty) handleLine(carry);

    final text = content.toString();
    if (text.trim().isNotEmpty) {
      final h = text.replaceAll('\n', ' ');
      print('[sini:http] stream ok len=${text.length} '
          'head=${safeHead(h, 120)} finish=$finish');
            if (streamUsage != null) {
        _reportUsage(cfg, streamUsage!);
      } else {
        // 没拿到 usage：按输出字符数粗估（约 0.9 token/字），聊胜于无
        _reportUsage(cfg, {
          'prompt_tokens': 0,
          'completion_tokens': (text.length * 0.9).round(),
        });
      }
      return ChatResult.ok(
        text,
        status: status,
        finishReason: finish,
        reasoningContent: reasoning.isEmpty ? null : reasoning.toString(),
      );
    }

    // 走到这里说明没收到任何 delta：多半是供应商忽略了 stream，回了整段 JSON
    final fallback = _parseChatBodyText(rawAll.toString(), status);
    if (fallback != null) return fallback;
    if (reasoning.isNotEmpty) {
      print('[sini:http] stream content 为空但 reasoning 存在（疑似推理模型耗尽额度）');
      return ChatResult.ok('',
          status: status, finishReason: finish, reasoningContent: reasoning.toString());
    }
    return ChatResult.fail('流式响应里没有解析到内容（$status）', status: status);
  } on DioException catch (e) {
    return ChatResult.fail(_dioMessage(e));
  } catch (e) {
    final msg = e.toString();
    if (msg.contains('XMLHttpRequest') || msg.contains('CORS')) {
      return const ChatResult.fail(
        '浏览器跨域被拒（CORS）。Web 端直连供应商常被拦截，请改用自建代理地址，'
        '或在模型设置里把 Base URL 改为带 CORS 头的本地代理。',
      );
    }
    return ChatResult.fail('请求失败：$msg');
  }
}

/// 把流式响应体整体读成字符串（只用于错误分支打印诊断）。
Future<String> _readAllText(ResponseBody body) async {
  final buf = StringBuffer();
  await for (final chunk in body.stream) {
    buf.write(utf8.decode(chunk, allowMalformed: true));
    if (buf.length > 2000) break; // 诊断用，不需要全量
  }
  return buf.toString();
}

/// 兜底解析：把「本该是 SSE、实际却是一整段 JSON」的响应按非流式结构解出来。
ChatResult? _parseChatBodyText(String raw, int status) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final start = s.indexOf('{');
  final end = s.lastIndexOf('}');
  if (start == -1 || end <= start) return null;
  Map<String, dynamic>? body;
  try {
    final v = jsonDecode(s.substring(start, end + 1));
    if (v is Map<String, dynamic>) body = v;
  } catch (_) {
    return null;
  }
  if (body == null) return null;
  final choices = body['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final c0 = choices[0];
  if (c0 is! Map) return null;
  // 流式被忽略时可能把整段放在 message 里，也可能放在 delta 里
  final holder = c0['message'] ?? c0['delta'];
  if (holder is! Map) return null;
  final c = holder['content'];
  if (c is String) {
    return ChatResult.ok(c,
        status: status, finishReason: c0['finish_reason'] as String?);
  }
  return null;
}

/// 响应没带 usage 时的兜底：按字符数粗估（中文约 0.6~0.9 token/字）
void _estimateUsage(
    ModelConfig cfg, List<Map<String, dynamic>> messages, String content) {
  try {
    var promptChars = 0;
    for (final m in messages) {
      final c = m['content'];
      if (c is String) promptChars += c.length;
    }
    final pt = (promptChars * 0.6).round();
    final ct = (content.length * 0.9).round();
    if (pt + ct <= 0) return;
    onTokenUsage?.call(cfg.providerId, cfg.modelId, pt, ct, pt + ct, usagePersonaName);
  } catch (_) {}
}

/// 从响应体的 usage 字段提取 token 消耗并回调钩子
void _reportUsage(ModelConfig cfg, Map usage) {
  try {
    final pt = (usage['prompt_tokens'] as num?)?.toInt() ?? 0;
    final ct = (usage['completion_tokens'] as num?)?.toInt() ?? 0;
    final tt = (usage['total_tokens'] as num?)?.toInt() ?? (pt + ct);
    if (pt + ct <= 0) return;
    onTokenUsage?.call(cfg.providerId, cfg.modelId, pt, ct, tt, usagePersonaName);
  } catch (_) {}
}

/// 单次 POST 到 /chat/completions，解析 content / reasoning_content / finish_reason。
Future<ChatResult> _postChat({
  required ModelConfig cfg,
  required List<Map<String, dynamic>> messages,
  required double temperature,
  required int maxTokens,
}) async {
  final url = cfg.baseUrl.trim();
  final key = cfg.apiKey.trim();
  final model = cfg.modelId.trim();
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 90),
    headers: {
      'Authorization': 'Bearer $key',
      'Content-Type': 'application/json',
    },
    // 非 2xx 不抛异常，自己解析状态码
    validateStatus: (_) => true,
  ));

  // DeepSeek V4 默认开启「思考(thinking)」，会把 token 预算消耗在 reasoning_content 上，
  // 导致真正回答 content 为空（复杂/长任务尤甚）。聊天人格场景不需要推理，显式关闭，
  // 既消除空内容、又更快更省。仅对 DeepSeek 系生效，其它供应商忽略即可。
  final isDeepSeek =
      cfg.providerId == 'deepseek' || url.toLowerCase().contains('deepseek');
  final data = <String, dynamic>{
    'model': model,
    'messages': messages,
    'temperature': temperature,
    'max_tokens': maxTokens,
    'stream': false,
    if (isDeepSeek) 'thinking': {'type': 'disabled'},
  };

  try {
    final res = await dio.post<dynamic>(
      '${_trimSlash(url)}/chat/completions',
      data: data,
    );
    final status = res.statusCode ?? 0;
    final fullUrl = '${_trimSlash(url)}/chat/completions';
    print('[sini:http] POST $fullUrl -> $status model=$model max_tokens=$maxTokens');
    if (status >= 400) {
      print('[sini:http] body=${res.data}');
      return ChatResult.fail(_statusMessage(status), status: status);
    }
    final body = res.data;
    if (body is Map<String, dynamic>) {
      final choices = body['choices'];
      if (choices is List && choices.isNotEmpty) {
        final choice = choices[0] is Map ? choices[0] : null;
        final msg = choice is Map ? choice['message'] : null;
        final content = msg is Map ? msg['content'] : null;
        final reasoning = msg is Map ? msg['reasoning_content'] : null;
        final finish = choice is Map ? choice['finish_reason'] : null;
        final reasoningText =
            reasoning is String ? reasoning : (reasoning?.toString() ?? '');
        if (content is String) {
          final h = content.replaceAll('\n', ' ');
          final head = safeHead(h, 200);
          print('[sini:http] ok len=${content.length} head=$head '
              'reasoningLen=${reasoningText.length} finish=$finish');
                    final u = body['usage'];
                    if (u is Map) {
                      _reportUsage(cfg, u);
                    } else {
                      _estimateUsage(cfg, messages, content);
                    }
          return ChatResult.ok(
            content,
            status: status,
            head: head,
            finishReason: finish is String ? finish : null,
            reasoningContent: reasoningText.isNotEmpty ? reasoningText : null,
          );
        }
        // content 为空但存在推理内容（推理模型典型表现），交给上层翻倍预算重试
        if (reasoningText.isNotEmpty) {
          print('[sini:http] content 为空但 reasoning_content 存在'
              '（长度 ${reasoningText.length}），疑似推理模型耗尽额度');
          return ChatResult.ok(
            '',
            status: status,
            finishReason: finish is String ? finish : null,
            reasoningContent: reasoningText,
          );
        }
      }
    }
    final raw = body is Map ? body.toString() : (body?.toString() ?? '');
    final rawHead = safeHead(raw, 200);
    print('[sini:http] unparsed status=$status body=$body');
    return ChatResult.fail('返回格式无法解析（$status）', status: status, head: rawHead);
  } on DioException catch (e) {
    return ChatResult.fail(_dioMessage(e));
  } catch (e) {
    final msg = e.toString();
    if (msg.contains('XMLHttpRequest') || msg.contains('CORS')) {
      return const ChatResult.fail(
        '浏览器跨域被拒（CORS）。Web 端直连供应商常被拦截，请改用自建代理地址，'
        '或在模型设置里把 Base URL 改为带 CORS 头的本地代理。',
      );
    }
    return ChatResult.fail('请求失败：$msg');
  }
}

// ---------------------------------------------------------------------------
// 图片生成：OpenAI 兼容的 POST {baseUrl}/images/generations
// 智谱 glm-image / CogView、OpenAI gpt-image-1、硅基流动 Flux 等都走这个接口。
// ---------------------------------------------------------------------------

/// 图片生成结果：成功拿到图片地址（或 base64），失败拿到可读错误。
class ImageResult {
  /// 图片直链（多数供应商返回 URL）
  final String? url;
  /// 部分供应商返回 base64（data:image/png;base64,xxx）
  final String? b64;
  final String? error;
  final int? status;

  const ImageResult.ok({this.url, this.b64, this.status})
      : error = null;
  const ImageResult.fail(this.error, {this.status})
      : url = null,
        b64 = null;

  bool get ok => error == null;

  /// 可直接喂给 Image.network / Image.memory 的数据源判断
  bool get hasUrl => url != null && url!.isNotEmpty;
  bool get hasB64 => b64 != null && b64!.isNotEmpty;
}

/// 调用图片生成接口。
/// - 智谱：baseUrl=`https://open.bigmodel.cn/api/paas/v4`，model=`glm-image`
/// - 返回 `data[0].url`（智谱）或 `data[0].b64_json`（部分供应商）
Future<ImageResult> generateImage({
  required ModelConfig cfg,
  required String prompt,
  String size = '1024x1024',
}) async {
  final url = cfg.baseUrl.trim();
  final key = cfg.apiKey.trim();
  final model = cfg.modelId.trim();
  if (url.isEmpty) return const ImageResult.fail('图片模型未配置 Base URL');
  if (key.isEmpty) return const ImageResult.fail('图片模型未配置 API Key');
  if (model.isEmpty) return const ImageResult.fail('图片模型 ID 为空');
  if (prompt.trim().isEmpty) return const ImageResult.fail('画面描述为空');

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    // 生图比聊天慢得多（通常 10~60s）
    receiveTimeout: const Duration(seconds: 120),
    headers: {
      'Authorization': 'Bearer $key',
      'Content-Type': 'application/json',
    },
    validateStatus: (_) => true,
  ));

  try {
    final res = await dio.post<dynamic>(
      '${_trimSlash(url)}/images/generations',
      data: {
        'model': model,
        'prompt': prompt,
        'size': size,
      },
    );
    final status = res.statusCode ?? 0;
    print('[sini:img] POST ${_trimSlash(url)}/images/generations -> $status model=$model');
    if (status >= 400) {
      final body = res.data?.toString() ?? '';
      print('[sini:img] err body=$body');
      final head = safeHead(body, 300);
      return ImageResult.fail(
        '${_statusMessage(status)}（$status）\n$head',
        status: status,
      );
    }
    final body = res.data;
    if (body is Map<String, dynamic>) {
      final data = body['data'];
      if (data is List && data.isNotEmpty && data[0] is Map) {
        final first = data[0] as Map;
        final u = first['url'];
        final b = first['b64_json'] ?? first['b64'];
        if (u is String && u.isNotEmpty) {
          print('[sini:img] ok url=$u');
          return ImageResult.ok(url: u, status: status);
        }
        if (b is String && b.isNotEmpty) {
          print('[sini:img] ok b64 len=${b.length}');
          return ImageResult.ok(
            b64: b.startsWith('data:') ? b : 'data:image/png;base64,$b',
            status: status,
          );
        }
      }
    }
    print('[sini:img] unparsed body=$body');
    return ImageResult.fail('返回格式无法解析（$status）', status: status);
  } on DioException catch (e) {
    return ImageResult.fail(_dioMessage(e));
  } catch (e) {
    final msg = e.toString();
    if (msg.contains('XMLHttpRequest') || msg.contains('CORS')) {
      return const ImageResult.fail(
        '浏览器跨域被拒（CORS）。Web 端直连供应商常被拦截，'
        '请把图片模型的 Base URL 改成带 CORS 头的代理地址。',
      );
    }
    return ImageResult.fail('请求失败：$msg');
  }
}
