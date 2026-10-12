import { ToolAction } from '../model/GameModels';
import { PelicanColors, PelicanMetrics } from '../theme/PelicanTheme';
import { GlassPanel } from './GlassPanel';

@Component
export struct ToolBar {
  compact: boolean = false;
  mobileMenu: boolean = false;
  availableWidth: number = 420;
  @State private menuOpen: boolean = false;
  @Prop musicEnabled: boolean = true;
  @Prop settingsOpen: boolean = false;
  @Prop immersiveEnabled: boolean = false;
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
  menuItem(label: string, action: ToolAction) {
    Button(label)
      .width(label.length > 1 ? 58 : 42)
      .height(38)
      .padding({ left: 0, right: 0 })
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(PelicanColors.TEXT)
      .backgroundColor(this.isOn(action) ? '#383FD0C9' : '#1FFFFFFF')
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
    if (this.mobileMenu) {
      Column({ space: 5 }) {
        Button(this.menuOpen ? '×' : '≡')
          .width(38)
          .height(36)
          .fontSize(20)
          .fontColor(PelicanColors.TEXT)
          .backgroundColor(PelicanColors.GLASS_STRONG)
          .border({ width: 1, color: PelicanColors.STROKE, radius: 12 })
          .accessibilityText('更多设置')
          .onClick((): void => { this.menuOpen = !this.menuOpen; })
        if (this.menuOpen) {
          Column({ space: 4 }) {
            Row({ space: 4 }) {
              this.menuItem('音乐', ToolAction.MUSIC)
              this.menuItem('全屏', ToolAction.IMMERSIVE)
            }
            Row({ space: 4 }) {
              this.menuItem('截图', ToolAction.SCREENSHOT)
              this.menuItem('分享', ToolAction.SHARE)
            }
            Row({ space: 4 }) {
              this.menuItem('设置', ToolAction.SETTINGS)
              this.menuItem('帮助', ToolAction.HELP)
            }
            Row({ space: 4 }) {
              this.menuItem('GH', ToolAction.GITHUB)
              this.menuItem('X', ToolAction.X)
            }
          }
          .padding(6)
          .backgroundColor(PelicanColors.GLASS_STRONG)
          .border({ width: 1, color: PelicanColors.STROKE, radius: 12 })
        }
      }
      .alignItems(HorizontalAlign.End)
    } else {
      Stack() {
        GlassPanel({
          radius: 14,
          paddingValue: this.compact ? 4 : 6
        }) {
          this.panelContent()
        }
      }
      .width(this.availableWidth)
    }
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
