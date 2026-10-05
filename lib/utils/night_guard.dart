/// 深夜守护：用户还在深夜聊天时，TA 轻轻劝睡。
///
/// 设计边界（与产品确认）：
/// - 只在用户**刚发过消息**后触发（不是定时硬推）
/// - 深夜约 23:30–04:30
/// - 同一晚只出一次
/// - 可在设置里关掉

library;

/// 是否在深夜窗口（本地时间 23:30–04:30）
bool isDeepNight(DateTime now) {
  final hm = now.hour * 60 + now.minute;
  return hm >= 23 * 60 + 30 || hm < 4 * 60 + 30;
}

/// 「今晚的日期」：0 点后算前一天的日期，保证 0:30 仍算「同一晚」
String nightKey(DateTime now) {
  final d = now.hour < 12
      ? now.subtract(const Duration(days: 1))
      : now;
  return '${d.year}-${d.month}-${d.day}';
}

/// 用户这条话是否明显在聊正事/工作（深夜也劝睡，但太硬核就少打断一次）
/// 返回 true 表示「不太适合劝睡」
bool looksLikeSeriousWork(String text) {
  return RegExp(
    r'需求|排期|上线|部署|编译|debug|代码|PR |合并分支|会议纪要|'
    r'论文|答辩|报销|合同|报价|发票|周报|日报',
    caseSensitive: false,
  ).hasMatch(text);
}

/// 生成 1～2 句劝睡文案。按关系与亲密感选口吻，避免说教。
List<String> buildSleepLines({
  required String? relationship,
  required String mood,
  required String personaName,
}) {
  final lover = relationship == '恋人';
  final warm = mood == '甜蜜' || mood == '粘人' || mood == '想你';

  if (lover) {
    if (warm) {
      return [
        '几点了还撑着……手机放下，去睡。',
        '明天醒了再继续说，我不跑。',
      ];
    }
    return [
      '凌晨了。听话，去睡觉。',
      '再熬明天顶着黑眼圈，我会心疼的。',
    ];
  }

  // 朋友 / 其他
  if (warm || mood == '心疼你') {
    return [
      '这么晚还不睡呀……去躺下吧。',
      '有什么事明天再说，今晚先放过自己。',
    ];
  }
  return [
    '快去睡。再熬头发要没了。',
    '晚安。有事明天找我。',
  ];
}
