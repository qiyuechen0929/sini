import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/recommend_card.dart' as rec;
import '../utils/web_bridge.dart';

/// 推荐卡片：显示"找什么" + 6 个平台跳转（高德/腾讯地图、美团/大众点评、京东/淘宝）。
///
/// 合规：只用各平台官方网页入口跳转，不在 app 内抓取或展示第三方数据，
/// 跳转后由对应平台提供真实结果。
class RecommendCard extends StatelessWidget {
  final rec.RecommendInfo info;
  const RecommendCard({super.key, required this.info});

  void _open(String url) {
    // Web 新标签页打开；手机端交给系统（浏览器 / 对应 App）
    openExternalUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题行
          Row(
            children: [
              Icon(Icons.explore_outlined, size: 15, color: p.textSecondary),
              const SizedBox(width: 6),
              Text(
                '去哪儿找「${info.keyword}」',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '一键跳转',
                style: TextStyle(fontSize: 11.5, color: p.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 第一组：找附近的店 → 地图
          _GroupLabel(label: '看附近的店', p: p),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _PlatformButton(
                  label: '高德地图',
                  icon: Icons.near_me_outlined,
                  p: p,
                  onTap: () => _open(rec.buildAmapSearchUri(info)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PlatformButton(
                  label: '腾讯地图',
                  icon: Icons.map_outlined,
                  p: p,
                  onTap: () => _open(rec.buildTencentSearchUri(info)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 第二组：看团购评价 → 美团 / 点评
          _GroupLabel(label: '看团购和评价', p: p),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _PlatformButton(
                  label: '美团',
                  icon: Icons.local_dining_outlined,
                  p: p,
                  onTap: () => _open(rec.buildMeituanUri(info)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PlatformButton(
                  label: '大众点评',
                  icon: Icons.rate_review_outlined,
                  p: p,
                  onTap: () => _open(rec.buildDianpingUri(info)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 第三组：直接买 / 囤 → 京东 / 淘宝
          _GroupLabel(label: '直接下单同款', p: p),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _PlatformButton(
                  label: '京东',
                  icon: Icons.shopping_bag_outlined,
                  p: p,
                  onTap: () => _open(rec.buildJdUri(info)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PlatformButton(
                  label: '淘宝',
                  icon: Icons.storefront_outlined,
                  p: p,
                  onTap: () => _open(rec.buildTaobaoUri(info)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          Text(
            '跳转到对应平台查看真实结果（价格、距离以平台为准）',
            style: TextStyle(fontSize: 10.5, color: p.textTertiary, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// 分组小标题
class _GroupLabel extends StatelessWidget {
  final String label;
  final AppPalette p;
  const _GroupLabel({required this.label, required this.p});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 2,
          height: 10,
          decoration: BoxDecoration(
            color: p.brand.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: p.textTertiary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// 平台跳转按钮
class _PlatformButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final AppPalette p;
  final VoidCallback onTap;
  const _PlatformButton({
    required this.label,
    required this.icon,
    required this.p,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.border, width: 0.8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: p.textPrimary),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(width: 3),
              Icon(Icons.open_in_new, size: 10, color: p.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
