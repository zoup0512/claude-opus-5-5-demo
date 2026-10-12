import { ToolAction } from '../model/GameModels';
import { PelicanColors, PelicanMetrics } from '../theme/PelicanTheme';
import { GlassPanel } from './GlassPanel';

@Component
export struct ToolBar {
  compact: boolean = false;
  availableWidth: number = 420;
  musicEnabled: boolean = true;
  settingsOpen: boolean = false;
  immersiveEnabled: boolean = false;
  onAction: (action: ToolAction) => void = (_action: ToolAction): void => {};

  @Builder
  toolButton(icon: string, label: string, action: ToolAction, smallText: boolean = false) {
    Button(icon)
      .width(this.compact ? PelicanMetrics.TOOL_BUTTON_COMPACT : PelicanMetrics.TOOL_BUTTON)
      .height(this.compact ? PelicanMetrics.TOOL_BUTTON_COMPACT : PelicanMetrics.TOOL_BUTTON)
      .fontSize(smallText ? (this.compact ? 10 : 11) : (this.compact ? 14 : 17))
      .fontWeight(action === ToolAction.HELP ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(PelicanColors.TEXT)
      .backgroundColor(this.isOn(action) ? '#383FD0C9' : PelicanColors.TRANSPARENT)
      .borderRadius(PelicanMetrics.BUTTON_RADIUS)
      .accessibilityText(label)
      .onClick((): void => {
        this.onAction(action);
      })
  }

  @Builder
  panelContent() {
    Scroll() {
      Row({ space: this.compact ? 4 : PelicanMetrics.TOOLBAR_GAP }) {
        this.toolButton('▣', '截图', ToolAction.SCREENSHOT)
        this.toolButton('♫', '音乐', ToolAction.MUSIC)
        this.toolButton('↗', '复制分享链接', ToolAction.SHARE)
        this.toolButton('⛶', '沉浸式', ToolAction.IMMERSIVE)
        this.toolButton('⚙', '参数面板', ToolAction.SETTINGS)
        this.toolButton('?', '帮助', ToolAction.HELP)
        this.toolButton('GH', 'GitHub 源码', ToolAction.GITHUB, true)
        this.toolButton('X', '作者主页', ToolAction.X)
      }
      .width(Math.max(PelicanMetrics.TOOLBAR_MIN_WIDTH, this.toolbarContentWidth()))
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width(this.availableWidth)
  }

  build() {
    GlassPanel({
      radius: 14,
      paddingValue: this.compact ? 4 : 6,
      content: this.panelContent
    })
    .width(this.availableWidth)
  }

  toolbarContentWidth(): number {
    const buttonSize: number = this.compact ? PelicanMetrics.TOOL_BUTTON_COMPACT : PelicanMetrics.TOOL_BUTTON;
    const gap: number = this.compact ? 4 : PelicanMetrics.TOOLBAR_GAP;
    return 8 * buttonSize + 7 * gap;
  }

  isOn(action: ToolAction): boolean {
    if (action === ToolAction.MUSIC) {
      return this.musicEnabled;
    }
    if (action === ToolAction.SETTINGS) {
      return this.settingsOpen;
    }
    if (action === ToolAction.IMMERSIVE) {
      return this.immersiveEnabled;
    }
    return false;
  }
}
