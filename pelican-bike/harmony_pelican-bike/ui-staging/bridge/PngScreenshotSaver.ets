import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScreenshotFrame, ScreenshotRequest, ScreenshotResult } from '../model/GameModels';
import { ScreenshotSaver } from './HarmonySystemCapabilityAdapter';

export class PngScreenshotSaver implements ScreenshotSaver {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  save(request: ScreenshotRequest, snapshot: ScreenshotFrame): Promise<ScreenshotResult> {
    if (!snapshot.success) {
      return Promise.resolve(new ScreenshotResult(false, 'Native 截图失败'));
    }
    if (snapshot.pixels === undefined || snapshot.width <= 0 || snapshot.height <= 0) {
      if (snapshot.path.length > 0) {
        return this.publishExistingFile(snapshot.path, request.fileName);
      }
      return Promise.resolve(new ScreenshotResult(false, '截图没有 RGBA 数据或临时文件'));
    }
    // glReadPixels uses a bottom-left origin. The native bridge should vertically flip RGBA before this point.
    const options: image.InitializationOptions = {
      size: {
        width: snapshot.width,
        height: snapshot.height
      },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: false
    };
    return image.createPixelMap(snapshot.pixels, options).then((pixelMap: image.PixelMap): Promise<ArrayBuffer> => {
      const packer: image.ImagePacker = image.createImagePacker();
      return packer.packToData(pixelMap, {
        format: 'image/png',
        quality: 100
      }).then((pngData: ArrayBuffer): ArrayBuffer => {
        pixelMap.release();
        packer.release();
        return pngData;
      });
    }).then((pngData: ArrayBuffer): Promise<ScreenshotResult> => {
      const path: string = this.context.cacheDir + '/' + request.fileName;
      const file: fileIo.File = fileIo.openSync(path,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, pngData);
      } finally {
        fileIo.closeSync(file);
      }
      return this.publishExistingFile(path, request.fileName);
    }).catch((error: BusinessError): ScreenshotResult => {
      return new ScreenshotResult(false, 'PNG 保存失败：' + error.code.toString());
    });
  }

  private publishExistingFile(path: string, fileName: string): Promise<ScreenshotResult> {
    const helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
    const uri: string = fileUri.getUriFromPath(path);
    const title: string = this.titleWithoutExtension(fileName);
    const configs: Array<photoAccessHelper.PhotoCreationConfig> = [{
      title: title,
      fileNameExtension: 'png',
      photoType: photoAccessHelper.PhotoType.IMAGE
    }];
    return helper.showAssetsCreationDialog([uri], configs).then((createdUris: Array<string>): ScreenshotResult => {
      const createdUri: string = createdUris.length > 0 ? createdUris[0] : '';
      return new ScreenshotResult(true, '截图已保存到图库', createdUri);
    }).catch((error: BusinessError): ScreenshotResult => {
      return new ScreenshotResult(false, '图库保存失败：' + error.code.toString());
    });
  }

  private titleWithoutExtension(fileName: string): string {
    const suffix: string = '.png';
    if (fileName.endsWith(suffix)) {
      return fileName.substring(0, fileName.length - suffix.length);
    }
    return fileName;
  }
}
