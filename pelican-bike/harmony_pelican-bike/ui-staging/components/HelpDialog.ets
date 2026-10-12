import { PelicanColors, PelicanMetrics } from '../theme/PelicanTheme';
import { GlassPanel } from './GlassPanel';

@Component
export struct HelpDialog {
  widthValue: number = 720;
  heightValue: number = 1280;
  onClose: () => void = (): void => {};

  @Builder
  helpItem(keyLabel: string, detail: string) {
    GridItem() {
      Row({ space: 10 }) {
        Text(keyLabel)
          .fontSize(11.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(PelicanColors.TEXT)
          .padding({ left: 7, right: 7, top: 3, bottom: 3 })
          .backgroundColor('#1FFFFFFF')
          .border({ width: 1, color: PelicanColors.STROKE_STRONG, radius: 6 })
        Text(detail)
          .fontSize(13.5)
          .fontColor(PelicanColors.TEXT_MUTED)
          .layoutWeight(1)
      }
    }
  }

  @Builder
  panelContent() {
    Column({ space: 14 }) {
      Row() {
        Text('操作说明')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(PelicanColors.TEXT)
          .layoutWeight(1)
        Button('×')
          .width(36)
          .height(36)
          .fontSize(22)
          .fontColor(PelicanColors.TEXT)
          .backgroundColor('#14FFFFFF')
          .borderRadius(12)
          .onClick((): void => {
            this.onClose();
          })
      }

      Scroll() {
        Grid() {
          this.helpItem('W / ↑', '加速')
          this.helpItem('S / ↓', '刹车，滑行有棘轮声')
          this.helpItem('A / D', '左右变道抓鱼')
          this.helpItem('空格', '跳跃')
          this.helpItem('T', '放手展翅 + 抬前轮')
          this.helpItem('B', '按车铃')
          this.helpItem('H', '鹈鹕大叫')
          this.helpItem('C', '切换镜头')
          this.helpItem('Q / E', '手动换挡')
          this.helpItem('N', '时间快进 3 小时')
          this.helpItem('M', '音乐开关')
          this.helpItem('K / F', '截图 / 沉浸式')
          this.helpItem('U', '隐藏界面')
          this.helpItem('P', '暂停')
        }
        .columnsTemplate(this.widthValue > 620 ? '1fr 1fr' : '1fr')
        .columnsGap(18)
        .rowsGap(10)
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .constraintSize({ maxHeight: Math.min(360, this.heightValue * 0.52) })

      Text('拖拽旋转视角、滚轮缩放。点击鹈鹕、车铃或远处海面都有惊喜；几秒不操作会自动驾驶追鱼。金色鱼值 5 分，背景音乐节奏跟随踏频。')
        .fontSize(12.5)
        .lineHeight(21)
        .fontColor(PelicanColors.TEXT_MUTED)

      Button('知道了')
        .height(44)
        .padding({ left: 22, right: 22 })
        .fontSize(14)
        .fontColor(PelicanColors.TEXT)
        .backgroundColor('#14FFFFFF')
        .border({ width: 1, color: PelicanColors.STROKE, radius: 999 })
        .alignSelf(ItemAlign.Start)
        .onClick((): void => {
          this.onClose();
        })
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#73000000')
        .onClick((): void => {
          this.onClose();
        })

      GlassPanel({
        strong: true,
        radius: 18,
        paddingValue: { left: 24, right: 24, top: 22, bottom: 22 },
        content: this.panelContent
      })
      .width(Math.min(PelicanMetrics.HELP_MAX_WIDTH, Math.max(320, this.widthValue - 32)))
      .onClick((event: ClickEvent): void => {
        event.stopPropagation();
      })
    }
    .width('100%')
    .height('100%')
  }
}
