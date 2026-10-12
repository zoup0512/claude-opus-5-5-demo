import { AchievementEvent, ScoreEvent } from '../model/GameModels';
import { PelicanColors } from '../theme/PelicanTheme';
import { GlassPanel } from './GlassPanel';

@Component
export struct ToastOverlay {
  event: AchievementEvent | undefined = undefined;
  safeTop: number = 0;

  @Builder
  panelContent() {
    if (this.event !== undefined) {
      Row({ space: 10 }) {
        Text(this.event.icon)
          .fontSize(24)
        Column({ space: 2 }) {
          Text(this.event.title)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(PelicanColors.TEXT)
          Text(this.event.detail)
            .fontSize(12)
            .fontColor(PelicanColors.TEXT_MUTED)
        }
        .alignItems(HorizontalAlign.Start)
      }
    }
  }

  build() {
    if (this.event !== undefined) {
      GlassPanel({
        strong: true,
        radius: 14,
        paddingValue: { left: 12, right: 16, top: 10, bottom: 10 },
        content: this.panelContent
      })
      .align(Alignment.TopCenter)
      .translate({ x: 0, y: Math.max(90, this.safeTop + 86) })
    }
  }
}

@Component
export struct ScorePopOverlay {
  event: ScoreEvent | undefined = undefined;
  widthValue: number = 720;
  heightValue: number = 1280;

  build() {
    if (this.event !== undefined) {
      Text(this.event.text)
        .fontSize(this.event.golden ? 26 : 22)
        .fontWeight(FontWeight.Bolder)
        .fontColor(this.event.golden ? PelicanColors.GOLD : '#BFF4FF')
        .textShadow({
          radius: this.event.golden ? 14 : 10,
          color: this.event.golden ? '#E6FFA000' : '#CC00B4FF',
          offsetX: 0,
          offsetY: 2
        })
        .position({
          x: this.widthValue * this.event.normalizedX,
          y: this.heightValue * this.event.normalizedY
        })
        .translate({ x: '-50%', y: '-120%' })
    }
  }
}

@Component
export struct FpsBadge {
  fps: number = 60;
  qualityLabel: string = '均衡';
  pixelRatio: number = 1.25;

  @Builder
  panelContent() {
    Text(Math.round(this.fps).toString() + ' FPS · ' + this.qualityLabel + ' · ' + this.pixelRatio.toFixed(2) + 'x')
      .fontSize(11)
      .fontColor(PelicanColors.TEXT_MUTED)
  }

  build() {
    GlassPanel({
      radius: 8,
      paddingValue: { left: 8, right: 8, top: 4, bottom: 4 },
      content: this.panelContent
    })
  }
}

@Component
export struct CinematicOverlay {
  active: boolean = false;
  flashVisible: boolean = false;
  barHeight: number = 0;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.active) {
        Column()
          .width('100%')
          .height(this.barHeight)
          .backgroundColor(PelicanColors.BLACK)
          .align(Alignment.Top)
        Column()
          .width('100%')
          .height(this.barHeight)
          .backgroundColor(PelicanColors.BLACK)
          .align(Alignment.Bottom)
      }
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(PelicanColors.BLACK)
        .opacity(this.flashVisible ? 0.85 : 0.0)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}
