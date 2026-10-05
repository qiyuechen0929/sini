import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/route_card.dart' as rc;
import '../utils/web_bridge.dart';

/// 路线卡片：显示起终点示意 + 一键跳转高德地图 / 腾讯地图。
///
/// 合规：只用官方 URI API 跳转，不自行绘制地图底图、不接境外地图源，
/// URI API 无需 API Key。跳转后由高德/腾讯提供真实地图与导航。
class RouteCard extends StatefulWidget {
  final rc.RouteInfo route;
  const RouteCard({super.key, required this.route});

  @override
  State<RouteCard> createState() => _RouteCardState();
}

class _RouteCardState extends State<RouteCard> {
  late rc.RouteMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.route.mode;
  }

  void _open(String url) {
    // Web 新标签页打开；手机端交给系统（高德/腾讯地图 App 或浏览器）
    openExternalUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final r = rc.RouteInfo(
      from: widget.route.from,
      to: widget.route.to,
      mode: _mode,
    );

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
              Icon(Icons.near_me_outlined, size: 15, color: p.textSecondary),
              const SizedBox(width: 6),
              Text(
                '路线',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                _mode.label,
                style: TextStyle(fontSize: 11.5, color: p.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 起点 → 终点 示意
          _RouteLine(from: r.from, to: r.to, p: p),

          const SizedBox(height: 12),

          // 出行方式切换
          Wrap(
            spacing: 6,
            children: [
              for (final m in rc.RouteMode.values)
                _ModeChip(
                  label: m.label,
                  icon: _iconFor(m),
                  selected: m == _mode,
                  p: p,
                  onTap: () => setState(() => _mode = m),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // 跳转按钮
          Row(
            children: [
              Expanded(
                child: _MapButton(
                  label: '高德地图',
                  p: p,
                  onTap: () => _open(rc.buildAmapUri(r)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MapButton(
                  label: '腾讯地图',
                  p: p,
                  onTap: () => _open(rc.buildTencentUri(r)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '点上方按钮在地图中查看精确路线与实时路况',
            style: TextStyle(fontSize: 10.5, color: p.textTertiary, height: 1.4),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(rc.RouteMode m) {
    switch (m) {
      case rc.RouteMode.car:
        return Icons.directions_car_outlined;
      case rc.RouteMode.bus:
        return Icons.directions_subway_outlined;
      case rc.RouteMode.walk:
        return Icons.directions_walk_outlined;
      case rc.RouteMode.ride:
        return Icons.pedal_bike_outlined;
    }
  }
}

/// 起点 ● → 虚线 → 终点 ◆ 的路线示意
class _RouteLine extends StatelessWidget {
  final String from;
  final String to;
  final AppPalette p;
  const _RouteLine({required this.from, required this.to, required this.p});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.radio_button_checked, size: 14, color: p.brand),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                from,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: p.textPrimary),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 6.5),
          child: Column(
            children: [
              for (int i = 0; i < 3; i++)
                Container(
                  width: 1,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 1.5),
                  color: p.borderStrong,
                ),
            ],
          ),
        ),
        Row(
          children: [
            Icon(Icons.location_on, size: 15, color: Colors.red.shade400),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                to,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: p.textPrimary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 出行方式小 chip（可选中）
class _ModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final AppPalette p;
  final VoidCallback onTap;
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.p,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? p.brand.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? p.brand.withValues(alpha: 0.45) : p.border,
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: selected ? p.brand : p.textTertiary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  color: selected ? p.brand : p.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 跳转地图的按钮
class _MapButton extends StatelessWidget {
  final String label;
  final AppPalette p;
  final VoidCallback onTap;
  const _MapButton({required this.label, required this.p, required this.onTap});

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
              Icon(Icons.map_outlined, size: 14, color: p.textPrimary),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: p.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
