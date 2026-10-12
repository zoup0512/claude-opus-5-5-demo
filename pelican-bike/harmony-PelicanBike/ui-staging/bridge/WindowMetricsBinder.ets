import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export class WindowMetricsBinder {
  private readonly context: common.UIAbilityContext;
  private mainWindow: window.Window | undefined = undefined;
  private readonly avoidAreaCallback: (options: window.AvoidAreaOptions) => void;
  private readonly sizeCallback: (size: window.Size) => void;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.avoidAreaCallback = (options: window.AvoidAreaOptions): void => {
      this.applyAvoidArea(options.type, options.area);
    };
    this.sizeCallback = (size: window.Size): void => {
      AppStorage.setOrCreate('windowWidth', px2vp(size.width));
      AppStorage.setOrCreate('windowHeight', px2vp(size.height));
    };
  }

  bind(): Promise<void> {
    return window.getLastWindow(this.context).then((mainWindow: window.Window): void => {
      this.mainWindow = mainWindow;
      const properties: window.WindowProperties = mainWindow.getWindowProperties();
      AppStorage.setOrCreate('windowWidth', px2vp(properties.windowRect.width));
      AppStorage.setOrCreate('windowHeight', px2vp(properties.windowRect.height));
      this.applyAvoidArea(window.AvoidAreaType.TYPE_SYSTEM,
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM));
      this.applyAvoidArea(window.AvoidAreaType.TYPE_CUTOUT,
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT));
      this.applyAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR,
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR));
      mainWindow.on('avoidAreaChange', this.avoidAreaCallback);
      mainWindow.on('windowSizeChange', this.sizeCallback);
    });
  }

  unbind(): void {
    const mainWindow: window.Window | undefined = this.mainWindow;
    if (mainWindow === undefined) {
      return;
    }
    mainWindow.off('avoidAreaChange', this.avoidAreaCallback);
    mainWindow.off('windowSizeChange', this.sizeCallback);
    this.mainWindow = undefined;
  }

  private applyAvoidArea(type: window.AvoidAreaType, area: window.AvoidArea): void {
    const left: number = px2vp(area.leftRect.width);
    const top: number = px2vp(area.topRect.height);
    const right: number = px2vp(area.rightRect.width);
    const bottom: number = px2vp(area.bottomRect.height);
    if (type === window.AvoidAreaType.TYPE_CUTOUT) {
      AppStorage.setOrCreate('safeLeft', Math.max(this.storageNumber('safeLeft'), left));
      AppStorage.setOrCreate('safeTop', Math.max(this.storageNumber('safeTop'), top));
      AppStorage.setOrCreate('safeRight', Math.max(this.storageNumber('safeRight'), right));
      AppStorage.setOrCreate('safeBottom', Math.max(this.storageNumber('safeBottom'), bottom));
      return;
    }
    if (type === window.AvoidAreaType.TYPE_SYSTEM) {
      AppStorage.setOrCreate('safeLeft', left);
      AppStorage.setOrCreate('safeTop', top);
      AppStorage.setOrCreate('safeRight', right);
      AppStorage.setOrCreate('safeBottom', bottom);
      return;
    }
    if (type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
      AppStorage.setOrCreate('safeBottom', Math.max(this.storageNumber('safeBottom'), bottom));
    }
  }

  private storageNumber(key: string): number {
    const value: number | undefined = AppStorage.get<number>(key);
    return value === undefined ? 0 : value;
  }
}
