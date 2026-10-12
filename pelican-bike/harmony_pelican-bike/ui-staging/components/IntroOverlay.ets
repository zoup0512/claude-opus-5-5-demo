import { IntroChip, INTRO_CHIPS } from '../model/GameModels';
import {
  PelicanColors,
  PelicanMetrics,
  accentShadow,
  primaryGradient,
  titleGradient
} from '../theme/PelicanTheme';
import { PelicanIntroArt } from './PelicanIntroArt';

@Component
export struct IntroOverlay {
  widthValue: number = 720;
  heightValue: number = 1280;
  safeTop: number = 0;
  safeBottom: number = 0;
  compact: boolean = false;
  shortHeight: boolean = false;
  tinyHeight: boolean = false;
  onStart: (withSound: boolean) => void = (_withSound: boolean): void => {};
  onOpenGitHub: () => void = (): void => {};
  onOpenAuthor: () => void = (): void => {};

  build() {
    Scroll() {
      Column({ space: this.shortHeight ? 8 : 12 }) {
        if (!this.tinyHeight) {
          PelicanIntroArt({
            widthValue: this.shortHeight ? 150 : Math.min(300, this.widthValue * 0.70),
            heightValue: this.shortHeight ? 95 : Math.min(190, this.widthValue * 0.443)
          })
        }

        Text('鹈鹕骑单车')
          .fontSize(this.shortHeight ? 30 : Math.min(60, Math.max(34, this.widthValue * 0.07)))
          .fontWeight(FontWeight.Bolder)
          .letterSpacing(1.5)
          .fontColor(PelicanColors.WHITE_WARM)
          .linearGradient(titleGradient())
          .textAlign(TextAlign.Center)

        Text('一只戴头盔、围红围巾的白鹈鹕，骑着复古单车沿海岸线追鱼。\n黄昏、星空、海浪与路灯 —— 全部实时生成，无一张外部贴图。')
          .fontSize(this.shortHeight ? 13 : (this.compact ? 14 : 16))
          .fontColor(PelicanColors.TEXT_MUTED)
          .lineHeight(this.shortHeight ? 21 : 25)
          .textAlign(TextAlign.Center)
          .maxLines(this.shortHeight ? 2 : 4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: this.shortHeight ? 0 : 2, bottom: this.shortHeight ? 2 : 6 })

        if (!this.shortHeight) {
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            Repeat<IntroChip>(INTRO_CHIPS)
              .each((repeatItem: RepeatItem<IntroChip>) => {
                Text(repeatItem.item.label)
                  .fontSize(12.5)
                  .fontColor('#DBFFFFFF')
                  .padding({ left: 11, right: 11, top: 5, bottom: 5 })
                  .backgroundColor('#14FFFFFF')
                  .border({ width: 1, color: PelicanColors.STROKE, radius: 999 })
                  .margin({ left: 4, right: 4, top: 4, bottom: 4 })
              })
              .key((item: IntroChip): string => item.id)
          }
          .width('100%')
          .margin({ bottom: 8 })
        }

        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          Button('开始骑行 ▶')
            .height(this.shortHeight ? 42 : 50)
            .padding({ left: this.shortHeight ? 24 : 30, right: this.shortHeight ? 24 : 30 })
            .fontSize(this.shortHeight ? 15 : 17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#2A1400')
            .backgroundColor(PelicanColors.ACCENT)
            .linearGradient(primaryGradient())
            .borderRadius(999)
            .shadow(accentShadow())
            .margin({ left: 6, right: 6, top: 4, bottom: 4 })
            .onClick(() => {
              this.onStart(true);
            })

          Button('静音进入')
            .height(this.shortHeight ? 42 : 50)
            .padding({ left: this.shortHeight ? 18 : 22, right: this.shortHeight ? 18 : 22 })
            .fontSize(this.shortHeight ? 13 : 15)
            .fontColor(PelicanColors.TEXT)
            .backgroundColor('#14FFFFFF')
            .border({ width: 1, color: PelicanColors.STROKE, radius: 999 })
            .margin({ left: 6, right: 6, top: 4, bottom: 4 })
            .onClick(() => {
              this.onStart(false);
            })
        }
        .width('100%')

        if (!this.tinyHeight) {
          Text('W / S 加速刹车　A / D 变道抓鱼　空格 跳跃　T 特技\nB 铃　H 鹈鹕大叫　C 镜头　N 快进 3 小时')
            .fontSize(this.shortHeight ? 11 : 12.5)
            .fontColor(PelicanColors.TEXT_MUTED)
            .lineHeight(this.shortHeight ? 18 : 22)
            .textAlign(TextAlign.Center)
            .margin({ top: this.shortHeight ? 2 : 8 })
        }

        Row({ space: 20 }) {
          Button('GitHub 开源仓库')
            .fontSize(12.5)
            .fontColor(PelicanColors.TEXT_MUTED)
            .backgroundColor(PelicanColors.TRANSPARENT)
            .height(34)
            .padding({ left: 6, right: 6 })
            .onClick(() => {
              this.onOpenGitHub();
            })
          Button('关注作者 X')
            .fontSize(12.5)
            .fontColor(PelicanColors.TEXT_MUTED)
            .backgroundColor(PelicanColors.TRANSPARENT)
            .height(34)
            .padding({ left: 6, right: 6 })
            .onClick(() => {
              this.onOpenAuthor();
            })
        }
        .justifyContent(FlexAlign.Center)
        .margin({ top: this.shortHeight ? 0 : 4 })
      }
      .width(Math.min(PelicanMetrics.INTRO_MAX_WIDTH, Math.max(320, this.widthValue - 32)))
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .align(Alignment.Center)
    .padding({
      top: Math.max(12, this.safeTop + 8),
      bottom: Math.max(12, this.safeBottom + 8),
      left: 0,
      right: 0
    })
    .backgroundColor('#D20A0E1E')
    .linearGradient({
      angle: 180,
      colors: [
        ['#8C0A0E1E', 0.0],
        ['#D1080A16', 1.0]
      ]
    })
  }
}
