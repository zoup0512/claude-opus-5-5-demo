import { PelicanColors } from '../theme/PelicanTheme';
import { GlassPanel } from './GlassPanel';

@Component
export struct HudHints {
  @Builder
  panelContent() {
    Row({ space: 12 }) {
      Text('W/S 加速刹车')
      Text('A/D 变道')
      Text('空格 跳')
      Text('T 特技')
      Text('B 铃')
      Text('C 镜头')
      Text('U 隐藏界面')
    }
    .fontSize(12)
    .fontColor(PelicanColors.TEXT_MUTED)
  }

  build() {
    GlassPanel({
      radius: 14,
      paddingValue: { left: 14, right: 14, top: 8, bottom: 8 },
      content: this.panelContent
    })
  }
}
