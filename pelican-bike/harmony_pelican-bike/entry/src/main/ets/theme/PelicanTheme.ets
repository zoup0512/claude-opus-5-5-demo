export class PelicanColors {
  static readonly BACKGROUND: string = '#0D1424';
  static readonly BACKGROUND_DEEP: string = '#080A16';
  static readonly GLASS: string = '#850E1422';
  static readonly GLASS_STRONG: string = '#CC0A0E1A';
  static readonly GLASS_SOFT: string = '#60182032';
  static readonly STROKE: string = '#24FFFFFF';
  static readonly STROKE_STRONG: string = '#3DFFFFFF';
  static readonly TEXT: string = '#F4F6FB';
  static readonly TEXT_MUTED: string = '#A8ECF0FA';
  static readonly TEXT_DIM: string = '#78ECF0FA';
  static readonly ACCENT: string = '#FFB547';
  static readonly ACCENT_LIGHT: string = '#FFD27A';
  static readonly ACCENT_ORANGE: string = '#FF9A4D';
  static readonly CYAN: string = '#3FD0C9';
  static readonly CYAN_DARK: string = '#138A8A';
  static readonly DANGER: string = '#FF5A6E';
  static readonly GOLD: string = '#FFE08A';
  static readonly WHITE_WARM: string = '#FFF7E6';
  static readonly ROAD: string = '#80FFFFFF';
  static readonly BLACK: string = '#FF000000';
  static readonly TRANSPARENT: string = '#00000000';
}

export class PelicanMetrics {
  static readonly EDGE: number = 16;
  static readonly EDGE_SMALL: number = 10;
  static readonly SAFE_FALLBACK_TOP: number = 14;
  static readonly SAFE_FALLBACK_BOTTOM: number = 16;
  static readonly PANEL_RADIUS: number = 16;
  static readonly BUTTON_RADIUS: number = 11;
  static readonly TOOL_BUTTON: number = 38;
  static readonly TOOL_BUTTON_COMPACT: number = 34;
  static readonly TOUCH_BUTTON: number = 60;
  static readonly TOUCH_BUTTON_BIG: number = 72;
  static readonly TOUCH_BUTTON_COMPACT: number = 54;
  static readonly TOUCH_BUTTON_BIG_COMPACT: number = 62;
  static readonly MIN_TOUCH_TARGET: number = 48;
  static readonly TOOLBAR_MIN_WIDTH: number = 360;
  static readonly TOOLBAR_GAP: number = 6;
  static readonly PANEL_BLUR: number = 14;
  static readonly SHADOW_RADIUS: number = 40;
  static readonly INTRO_MAX_WIDTH: number = 640;
  static readonly DRAWER_WIDTH: number = 312;
  static readonly HELP_MAX_WIDTH: number = 560;
}

export class PelicanBreakpoints {
  static readonly NARROW: number = 900;
  static readonly COMPACT: number = 560;
  static readonly HIDE_HINTS: number = 1180;
  static readonly SHORT_HEIGHT: number = 620;
  static readonly TINY_HEIGHT: number = 420;
}

export function panelShadow(): ShadowOptions {
  return {
    radius: PelicanMetrics.SHADOW_RADIUS,
    color: '#59000000',
    offsetX: 0,
    offsetY: 10
  };
}

export function accentShadow(): ShadowOptions {
  return {
    radius: 30,
    color: '#73FF8C3C',
    offsetX: 0,
    offsetY: 10
  };
}

export function primaryGradient(): LinearGradientOptions {
  return {
    angle: 135,
    colors: [
      [PelicanColors.ACCENT_LIGHT, 0.0],
      [PelicanColors.ACCENT_ORANGE, 1.0]
    ]
  };
}

export function titleGradient(): LinearGradientOptions {
  return {
    angle: 92,
    colors: [
      [PelicanColors.WHITE_WARM, 0.0],
      ['#FFC27A', 0.45],
      ['#FF8A5B', 1.0]
    ]
  };
}

export function speedGradient(): LinearGradientOptions {
  return {
    angle: 135,
    colors: [
      [PelicanColors.CYAN, 0.0],
      ['#FFC27A', 0.60],
      [PelicanColors.DANGER, 1.0]
    ]
  };
}
