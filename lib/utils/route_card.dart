import 'dart:convert';

/// 路线卡片：识别"问路"意图、解析起终点、生成高德/腾讯地图跳转链接。
///
/// 合规说明：只使用**高德 / 腾讯地图官方 URI API** 做跳转，不自行绘制地图底图、
/// 不接入任何境外地图源。URI API 为官方提供给第三方调起的能力，无需 API Key。

/// 出行方式
enum RouteMode { car, bus, walk, ride }

extension RouteModeX on RouteMode {
  String get label {
    switch (this) {
      case RouteMode.car:
        return '驾车';
      case RouteMode.bus:
        return '公交地铁';
      case RouteMode.walk:
        return '步行';
      case RouteMode.ride:
        return '骑行';
    }
  }

  /// 高德 uri.amap.com 的 mode 参数
  String get amapMode {
    switch (this) {
      case RouteMode.car:
        return 'car';
      case RouteMode.bus:
        return 'bus';
      case RouteMode.walk:
        return 'walk';
      case RouteMode.ride:
        return 'ride';
    }
  }

  /// 腾讯 uri v1 routeplan 的 type 参数
  String get tencentType {
    switch (this) {
      case RouteMode.car:
        return 'drive';
      case RouteMode.bus:
        return 'bus';
      case RouteMode.walk:
        return 'walk';
      case RouteMode.ride:
        return 'bike';
    }
  }
}

/// 一条解析出来的路线请求
class RouteInfo {
  final String from;
  final String to;
  final RouteMode mode;

  const RouteInfo({
    required this.from,
    required this.to,
    this.mode = RouteMode.car,
  });

  bool get valid => from.isNotEmpty && to.isNotEmpty;
}

/// 判断用户这条提问是不是在"问路"。
bool isRouteQuestion(String userPrompt) {
  if (userPrompt.trim().isEmpty) return false;
  final u = userPrompt.toLowerCase();
  // 必须有"怎么去 / 怎么走 / 路线 / 多远 / 多久 / 导航"这类诉求
  final asksWay = RegExp(
    r'(怎么走|怎么去|如何去|如何去|怎么过去|走哪|哪条路|什么路线|路线|导航|多远|多长|多久|几公里|多少公里|多长距离|怎么坐|坐什么|乘地铁|坐地铁|坐公交)',
  ).hasMatch(u);
  if (!asksWay) return false;
  // 并且能从话里解析出起终点
  return parseRoute(userPrompt) != null;
}

/// 从用户提问里解析起终点，例如"从北京西站到故宫怎么走" → 北京西站 / 故宫。
/// 解析不出来返回 null（避免误触发卡片）。
RouteInfo? parseRoute(String userPrompt) {
  final text = userPrompt.trim();
  if (text.isEmpty) return null;

  String? from;
  String? to;

  // 1) "从 A 到/去/至 B ..."
  var m = RegExp(r'从(.+?)(?:到|去|至|抵达|往)(.+?)(?:怎么|如何|多远|多久|多长|几公里|多少公里|路线|导航|的|坐|乘|走|比较近|最近|最快|[,，。!！?？]|$)')
      .firstMatch(text);
  if (m != null) {
    from = m.group(1);
    to = m.group(2);
  }

  // 2) "A 到/去 B 怎么走"（没有"从"）
  if (from == null) {
    m = RegExp(r'(.+?)(?:到|去|至)(.+?)(?:怎么|如何|多远|多久|多长|几公里|多少公里|路线|导航|坐|乘|走|比较近|最近|最快|[,，。!！?？]|$)')
        .firstMatch(text);
    if (m != null) {
      from = m.group(1);
      to = m.group(2);
    }
  }

  if (from == null || to == null) return null;

  from = _cleanPlace(from);
  to = _cleanPlace(to);

  // 清理后为空 / 太短 / 两边一样 → 判定无效
  if (from.isEmpty || to.isEmpty) return null;
  if (from.length < 2 || to.length < 2) return null;
  if (from == to) return null;
  // 起终点里还残留"怎么/如何"等问法词 → 解析质量差，宁可不出卡
  if (RegExp(r'^(怎么|如何|什么|哪个|哪里)').hasMatch(to)) return null;

  return RouteInfo(from: from, to: to, mode: detectRouteMode(text));
}

/// 从提问里判断出行方式（没明说默认驾车/公交综合，后续由卡片让用户切换）
RouteMode detectRouteMode(String text) {
  if (RegExp(r'(地铁|公交|班车|换乘|轻轨|BRT|几号线)').hasMatch(text)) {
    return RouteMode.bus;
  }
  if (RegExp(r'(走路|步行|走过去|徒步)').hasMatch(text)) return RouteMode.walk;
  if (RegExp(r'(骑车|骑行|自行车|共享单车|电动车)').hasMatch(text)) {
    return RouteMode.ride;
  }
  if (RegExp(r'(开车|驾车|自驾|打车|出租车|滴滴|停车)').hasMatch(text)) {
    return RouteMode.car;
  }
  return RouteMode.car;
}

/// 去掉地点名前后的口语残留（"呀/呢/啊"、问法词、标点等）
String _cleanPlace(String s) {
  var v = s.trim();
  // 去掉开头残留的动词/介词
  v = v.replaceAll(RegExp(r'^(我想|我要|我|请问|帮我|查一下|查询|问一下|问下|去|到|在)'), '');
  // 去掉结尾的问法 / 语气词 / 标点
  v = v.replaceAll(
    RegExp(r'(怎么走|怎么去|如何去|怎么过去|比较近|最近|最快|最方便|怎么|如何|多远|多久|多长|几公里|多少公里|有好|的|呀|啊|呢|吧|吗|[，,。.!！?？、;；])$'),
    '',
  );
  return v.trim();
}

/// 生成高德地图 URI（无需 Key）。
/// 坐标系：高德用 GCJ-02，这里只传地名，由高德服务端地理编码。
String buildAmapUri(RouteInfo r) {
  final params = <String, String>{
    'from': r.from,
    'to': r.to,
    'mode': r.mode.amapMode,
    'policy': '0', // 推荐策略
    'src': 'sini',
    'callnative': '1', // 移动端尝试调起高德 App
  };
  final q = params.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');
  return 'https://uri.amap.com/navigation?$q';
}

/// 生成腾讯地图 URI（无需 Key，referer 填应用名即可）。
String buildTencentUri(RouteInfo r) {
  final params = <String, String>{
    'type': r.mode.tencentType,
    'from': r.from,
    'to': r.to,
    'policy': '0',
    'referer': 'sini',
  };
  final q = params.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');
  return 'https://apis.map.qq.com/uri/v1/routeplan?$q';
}

/// 给 AI 的提示：让它知道用户问路时该怎么答，避免瞎编精确数据或说"我没法导航"。
/// 必须是 const —— 会被拼进 `const` 的 system prompt 里。
const String routeSystemHint = '【问路场景】用户问"从 A 到 B 怎么走 / 多远 / 怎么坐车"时：\n'
    '- 给出实用的路线建议：推荐交通方式、大致距离与耗时、换乘要点或关键路口、注意事项（打车费用、拥堵时段等）。\n'
    '- 距离和耗时**只给大致估算**并说明是参考值；实时路况、具体班次请以地图 App 为准，不要编造精确数字。\n'
    '- 你的回答下方会自动出现一张路线卡片，用户点一下就能跳到高德地图或腾讯地图看精确导航，'
    '所以**不要**说"我没法导航 / 无法获取实时路况"这类拒绝的话，专注给经验和建议。';
