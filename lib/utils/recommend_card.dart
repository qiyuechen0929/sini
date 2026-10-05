/// 推荐卡片：识别"附近 / 推荐"意图，抽取关键词，生成 6 个平台的跳转链接。
///
/// 合规说明：不接入任何境外地图 / 生活服务平台数据；仅使用**官方网页搜索链接**
/// 跳转，由 高德 / 腾讯地图 / 美团 / 大众点评 / 京东 / 淘宝 自己返回结果。
/// 不在 app 内抓取或展示第三方平台数据。

/// 一条识别出来的推荐请求
class RecommendInfo {
  /// 用户想找的东西，例如"奶茶"、"烧烤"、"好玩的地方"
  final String keyword;
  /// 完整原始提问（用于搜索时保留语境）
  final String rawQuery;

  const RecommendInfo({required this.keyword, required this.rawQuery});

  bool get valid => keyword.isNotEmpty;
}

/// 泛推荐场景的触发词：附近 / 推荐 / 好吃 / 好喝 / 好玩 / 奶茶 ……
final RegExp _kRecommendTrigger = RegExp(
  r'(附近|周边|推荐|有什么|有啥|好吃|好喝|好玩的|好逛|去哪|哪里|哪儿|求推荐|安排|介绍个|找一[家个下]|吃啥|喝啥|玩啥|点哪家)',
);

/// 明确是"找地方消费"的品类词（命中则关键词优先取它）
final RegExp _kCategoryWords = RegExp(
  '(奶茶|果茶|咖啡|甜品|蛋糕|面包|火锅|烧烤|烤肉|川菜|湘菜|粤菜|日料|寿司|拉面|'
  '快餐|汉堡|炸鸡|披萨|米线|饺子|小吃|美食|餐厅|饭店|馆子|'
  '酒吧|清吧|livehouse|展|展览|博物馆|美术馆|电影院|电影|KTV|桌游|剧本杀|密室|'
  '公园|景点|景区|商场|超市|夜市|集市|书店|'
  '玩的地方|好玩的地方|溜达|约会|遛娃|散步|拍照|打卡|'
  '按摩|足疗|理发|洗车|健身|游泳|羽毛球|台球|网咖|'
  '早餐|午餐|晚餐|夜宵|下午茶|零食|水果|酒|饮料|果酒|精酿)',
);

/// 判断这条提问是不是"附近 / 推荐"类需求。
/// 宁可漏判也不误判：必须命中触发词，且能抽出可用关键词。
bool isRecommendQuestion(String userPrompt) {
  final t = userPrompt.trim();
  if (t.isEmpty) return false;
  if (!_kRecommendTrigger.hasMatch(t)) return false;
  return parseRecommend(t) != null;
}

/// 从提问里抽出"要找什么"。
/// 抽不出来返回 null（例如"推荐一下"这种没有具体对象的，就不出卡）。
RecommendInfo? parseRecommend(String userPrompt) {
  final t = userPrompt.trim();
  if (t.isEmpty) return null;

  // 1) 命中品类词 → 直接用它（最准）
  final cat = _kCategoryWords.firstMatch(t);
  if (cat != null) {
    var kw = cat.group(0)!;
    // "玩的地方"/"好玩的地方" 这类泛词，加"附近"更贴近用户意图
    if (RegExp(r'^(玩的地方|好玩的地方)$').hasMatch(kw)) {
      kw = '好玩的地方';
    }
    return RecommendInfo(keyword: kw, rawQuery: t);
  }

  // 2) 没命中品类，尝试从"推荐/找"后面抠名词短语：推荐几家北京的烤肉 → 兜底
  final m = RegExp(
    r'(?:推荐|找一[家个下]|介绍|安排|来点|想吃|想喝|想玩|想逛)(?:一下|点|些|个|家)?\s*([\u4e00-\u9fa5A-Za-z0-9]{2,12})',
  ).firstMatch(t);
  if (m != null) {
    var kw = m.group(1)!;
    // 去掉尾部语气词 / 常见问法残留
    kw = kw.replaceAll(RegExp(r'(的|呀|啊|呢|吧|吗|嘛|了)$'), '');
    // 太泛的词不单独成卡
    if (kw.isNotEmpty &&
        kw.length >= 2 &&
        !RegExp(r'^(什么|啥|哪个|哪些|哪里|哪儿|地方|东西|一下|一家)$').hasMatch(kw)) {
      return RecommendInfo(keyword: kw, rawQuery: t);
    }
  }

  // 3) 全是泛问（"附近有什么好玩的"）→ 用兜底泛词，让卡片给个入口
  if (RegExp(r'(好玩|好逛|玩的地方)').hasMatch(t)) {
    return RecommendInfo(keyword: '好玩的地方', rawQuery: t);
  }
  if (RegExp(r'(好吃)').hasMatch(t)) {
    return RecommendInfo(keyword: '美食', rawQuery: t);
  }
  if (RegExp(r'(好喝)').hasMatch(t)) {
    return RecommendInfo(keyword: '饮品', rawQuery: t);
  }
  return null;
}

/// 高德地图：按关键词做周边搜索。
/// 使用 uri.amap.com/marker 的正向地理编码 + 搜索入口，无需 Key。
String buildAmapSearchUri(RecommendInfo info) {
  final q = info.keyword.isEmpty ? info.rawQuery : info.keyword;
  return 'https://uri.amap.com/search?keyword=${Uri.encodeComponent(q)}'
      '&src=sini&callnative=1';
}

/// 腾讯地图：关键词搜索入口，无需 Key，referer 填应用名。
String buildTencentSearchUri(RecommendInfo info) {
  final q = info.keyword.isEmpty ? info.rawQuery : info.keyword;
  return 'https://apis.map.qq.com/uri/v1/search?keyword=${Uri.encodeComponent(q)}'
      '&referer=sini';
}

/// 美团：移动端搜索页（带"附近"语境的通用搜索入口）。
String buildMeituanUri(RecommendInfo info) {
  final q = '${info.keyword} 附近';
  return 'https://i.meituan.com/s/${Uri.encodeComponent(q)}';
}

/// 大众点评：移动端搜索页。
String buildDianpingUri(RecommendInfo info) {
  final q = info.keyword;
  return 'https://m.dianping.com/search/keyword/${Uri.encodeComponent(q)}/0';
}

/// 京东：移动端搜索（买现成的，比如茶叶 / 零食 / 器材）。
String buildJdUri(RecommendInfo info) {
  final q = info.keyword;
  return 'https://so.m.jd.com/ware/search.action?keyword=${Uri.encodeComponent(q)}';
}

/// 淘宝：移动端搜索页。
String buildTaobaoUri(RecommendInfo info) {
  final q = info.keyword;
  return 'https://s.m.taobao.com/h5?q=${Uri.encodeComponent(q)}';
}

/// 给 AI 的提示：让它知道用户问"附近/推荐"时该怎么答。
/// 必须是 const —— 会被拼进 `const` 的 system prompt 里。
const String recommendSystemHint = '【生活推荐场景】用户问"附近有什么好吃的 / 好喝的 / 好玩的 / 推荐点什么"时：\n'
    '- 从**生活经验**角度给建议：给几类选择 + 每类的特点、适合场景、人均消费大致区间、避坑提示。\n'
    '- 你**没有实时定位、没有联网**，所以不要编造具体店名、具体地址和精确价格，也不要说"我查一下"。'
    '可以说"一般来说""这类店通常"，把确定性交给下方卡片。\n'
    '- 你的回答下方会自动出现一张**推荐卡片**，用户点一下就能跳到高德/腾讯地图看附近的店，'
    '或跳到美团/大众点评看团购评价，到京东/淘宝买同款，'
    '所以**不要**说"我无法获取附近信息 / 我没法帮你找店"这类拒绝的话。';
