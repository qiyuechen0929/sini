/// 全局设计 token：间距、圆角、字号、模糊、动效时长。
/// 所有新页面/组件必须使用这些常量，保持风格一致。
/// 不在这里定义颜色 —— 颜色统一走 AppPalette（theme.dart）。

class Spacing {
  Spacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 40;
}

class Radii {
  Radii._();
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 10;
  static const double lg = 12;
  static const double xl = 14;
  static const double xxl = 20;
  static const double pill = 999;
}

class Motion {
  Motion._();
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 180);
  static const Duration slow = Duration(milliseconds: 260);
  static const Duration sheet = Duration(milliseconds: 280);
}

/// 字号档位：display / title / body / label
class SiniText {
  SiniText._();

  // Display
  static const displayLarge = 30.0; // 空状态大标题
  static const displayMedium = 24.0;

  // Title
  static const titleXl = 20.0;
  static const titleLg = 18.0;
  static const titleMd = 16.0;
  static const titleSm = 15.0;

  // Body
  static const bodyLg = 15.5; // 聊天正文
  static const bodyMd = 14.5;
  static const bodySm = 13.5;

  // Label
  static const labelLg = 13.0;
  static const labelMd = 12.0;
  static const labelSm = 11.0;
  static const labelXs = 10.5;

  // Sub-header / 元信息
  static const meta = 12.5;
  static const small = 11.5;
}

/// iOS 风液态玻璃：模糊半径 + 透明度系数
class Glass {
  Glass._();
  static const double sigmaSheet = 22.0;
  static const double sigmaBar = 18.0;
  static const double sigmaPopup = 14.0;
}
