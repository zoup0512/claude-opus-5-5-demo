import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { ScreenshotFrame, ScreenshotRequest, ScreenshotResult, SystemResult } from '../model/GameModels';
import { SystemCapabilityAdapter } from './SystemCapabilityAdapter';

export interface ScreenshotSaver {
  save(request: ScreenshotRequest, frame: ScreenshotFrame): Promise<ScreenshotResult>;
}

export class HarmonySystemCapabilityAdapter implements SystemCapabilityAdapter {
  private readonly context: common.UIAbilityContext;
  private readonly screenshotSaver: ScreenshotSaver;

  constructor(context: common.UIAbilityContext, screenshotSaver: ScreenshotSaver) {
    this.context = context;
    this.screenshotSaver = screenshotSaver;
  }

  copyText(text: string): Promise<SystemResult> {
    const data: pasteboard.PasteData = pasteboard.createPlainTextData(text);
    return pasteboard.getSystemPasteboard().setData(data).then((): SystemResult => {
      return new SystemResult(true, '已复制到剪贴板');
    }).catch((error: BusinessError): SystemResult => {
      return new SystemResult(false, '复制失败：' + error.code.toString());
    });
  }

  openLink(link: string): Promise<SystemResult> {
    return this.context.openLink(link).then((): SystemResult => {
      return new SystemResult(true, '已打开链接');
    }).catch((error: BusinessError): SystemResult => {
      return new SystemResult(false, '打开链接失败：' + error.code.toString());
    });
  }

  setImmersive(enabled: boolean): Promise<SystemResult> {
    const bars: Array<'status' | 'navigation'> = enabled ? [] : ['status', 'navigation'];
    return window.getLastWindow(this.context).then((mainWindow: window.Window): Promise<void> => {
      return mainWindow.setWindowLayoutFullScreen(enabled).then((): Promise<void> => {
        return mainWindow.setWindowSystemBarEnable(bars);
      });
    }).then((): SystemResult => {
      return new SystemResult(true, enabled ? '已进入沉浸式' : '已退出沉浸式');
    }).catch((error: BusinessError): SystemResult => {
      return new SystemResult(false, '沉浸式切换失败：' + error.code.toString());
    });
  }

  saveScreenshot(request: ScreenshotRequest, frame: ScreenshotFrame): Promise<ScreenshotResult> {
    return this.screenshotSaver.save(request, frame);
  }
}
