import { PelicanColors } from '../theme/PelicanTheme';
import { GlassPanel } from './GlassPanel';

@Component
export struct HudHints {
  @Builder
  panelContent() {
    Row({ space: 12 }) {
      Text('W/S 加速刹车').fontSize(12).fontColor(PelicanColors.TEXT_MUTED)
      Text('A/D 变道').fontSize(12).fontColor(PelicanColors.TEXT_MUTED)
      Text('空格 跳').fontSize(12).fontColor(PelicanColors.TEXT_MUTED)
      Text('T 特技').fontSize(12).fontColor(PelicanColors.TEXT_MUTED)
      Text('B 铃').fontSize(12).fontColor(PelicanColors.TEXT_MUTED)
      Text('C 镜头').fontSize(12).fontColor(PelicanColors.TEXT_MUTED)
      Text('U 隐藏界面').fontSize(12).fontColor(PelicanColors.TEXT_MUTED)
    }
  }

  build() {
    GlassPanel({
      radius: 14,
      paddingValue: { left: 14, right: 14, top: 8, bottom: 8 }
    }) {
      this.panelContent()
    }
  }
}
