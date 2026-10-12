import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN: number = 0xF2534;
const TAG: string = 'PelicanEntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate<boolean>('pelicanAppForeground', true);
    AppStorage.setOrCreate<number>('pelicanPendingHour', -1);
    AppStorage.setOrCreate<string>('pelicanPendingCamera', '');
    this.handleRideWant(want);
    hilog.info(DOMAIN, TAG, 'Ability created');
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.handleRideWant(want);
    hilog.info(DOMAIN, TAG, 'Ability received a new Want');
  }

  private handleRideWant(want: Want): void {
    const uri: string | undefined = want.uri;
    if (uri === undefined || !uri.startsWith('pelicanbike://ride')) {
      return;
    }
    const queryIndex: number = uri.indexOf('?');
    if (queryIndex < 0 || queryIndex + 1 >= uri.length) {
      return;
    }
    const pairs: string[] = uri.substring(queryIndex + 1).split('&');
    for (let index: number = 0; index < pairs.length; index += 1) {
      const pair: string = pairs[index];
      const equalsIndex: number = pair.indexOf('=');
      const rawKey: string = equalsIndex < 0 ? pair : pair.substring(0, equalsIndex);
      const rawValue: string = equalsIndex < 0 ? '' : pair.substring(equalsIndex + 1);
      const key: string = decodeURIComponent(rawKey);
      const value: string = decodeURIComponent(rawValue);
      if (key === 'time') {
        const hour: number = Number(value);
        if (Number.isFinite(hour) && hour >= 0 && hour <= 24) {
          AppStorage.setOrCreate<number>('pelicanPendingHour', hour === 24 ? 0 : hour);
        }
      } else if (key === 'cam' && EntryAbility.isCamera(value)) {
        AppStorage.setOrCreate<string>('pelicanPendingCamera', value);
      }
    }
  }

  private static isCamera(value: string): boolean {
    return value === 'orbit' || value === 'chase' || value === 'side' || value === 'cine' || value === 'pov';
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/PelicanBikeNativePage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      try {
        const mainWindow: window.Window = windowStage.getMainWindowSync();
        mainWindow.setWindowLayoutFullScreen(true).catch((error: Error): void => {
          hilog.warn(DOMAIN, TAG, 'setWindowLayoutFullScreen failed: %{public}s', error.message);
        });
        mainWindow.setWindowKeepScreenOn(true).catch((error: Error): void => {
          hilog.warn(DOMAIN, TAG, 'setWindowKeepScreenOn failed: %{public}s', error.message);
        });
        mainWindow.setWindowSystemBarEnable([]).catch((error: Error): void => {
          hilog.warn(DOMAIN, TAG, 'setWindowSystemBarEnable failed: %{public}s', error.message);
        });
        mainWindow.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          navigationBarColor: '#00000000',
          statusBarContentColor: '#FFFFFFFF',
          navigationBarContentColor: '#FFFFFFFF'
        }).catch((error: Error): void => {
          hilog.warn(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}s', error.message);
        });
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Immersive window setup failed: %{public}s', JSON.stringify(error));
      }
      hilog.info(DOMAIN, TAG, 'Content loaded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Window stage destroyed');
  }

  onForeground(): void {
    AppStorage.set<boolean>('pelicanAppForeground', true);
    hilog.info(DOMAIN, TAG, 'Ability foreground');
  }

  onBackground(): void {
    AppStorage.set<boolean>('pelicanAppForeground', false);
    hilog.info(DOMAIN, TAG, 'Ability background');
  }
}
