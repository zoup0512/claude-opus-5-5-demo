import { PelicanBikePage } from './PelicanBikePage';

@Entry
@Component
struct PelicanBikePreview {
  aboutToAppear(): void {
    AppStorage.setOrCreate('pelicanAppForeground', true);
    AppStorage.setOrCreate('pelicanPendingHour', -1);
    AppStorage.setOrCreate('pelicanPendingCamera', '');
  }

  build() {
    PelicanBikePage({ previewMode: true })
  }
}
